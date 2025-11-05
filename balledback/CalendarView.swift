//
//  CalendarView.swift
//  balledback
//
//  Created by James Perrow on 11/5/25.
//


import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: EstimatorStore
    @EnvironmentObject private var router: PremiumRouter
    @Environment(\.dismiss) private var dismiss

    // Selection and visible month
    @State private var selectedDate: Date = Date()
    @State private var visibleMonthAnchor: Date = Date() // any date within the visible month

    // Zoom
    @State private var zoomScale: CGFloat = 1.0
    private let minZoom: CGFloat = 0.9
    private let maxZoom: CGFloat = 1.6
    private let baseDaySize: CGFloat = 40 // base size before scaling

    private let calendar = Calendar.current

    // MARK: - Formatting

    private let monthFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "LLLL yyyy"
        return df
    }()

    private let weekdaySymbols: [String] = {
        // Use short weekday symbols, starting from the current calendar’s firstWeekday
        let cal = Calendar.current
        let symbols = DateFormatter().shortStandaloneWeekdaySymbols ?? ["S","M","T","W","T","F","S"]
        let first = cal.firstWeekday // 1 = Sunday in Gregorian
        // Rotate to start from firstWeekday
        let left = Array(symbols[(first-1)...])
        let right = Array(symbols[..<(first-1)])
        return left + right
    }()

    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .none
        return df
    }()

    // MARK: - Derived

    private var daySize: CGFloat {
        max(minZoom, min(maxZoom, zoomScale)) * baseDaySize
    }

    private var visibleMonthRange: (start: Date, end: Date) {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonthAnchor)) ?? visibleMonthAnchor
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: startOfMonth)) ?? startOfMonth
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return (start: start, end: nextMonth)
    }

    // Only days within the currently visible month (no leading/trailing padding)
    private var daysForGrid: [Date] {
        let startOfMonth = visibleMonthRange.start
        // Last day of month = (start of next month) - 1 day
        let lastDay = calendar.date(byAdding: DateComponents(day: -1), to: visibleMonthRange.end) ?? visibleMonthRange.end

        var days: [Date] = []
        var d = startOfMonth
        while d <= lastDay {
            days.append(d)
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return days
    }

    private func isInVisibleMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: visibleMonthRange.start, toGranularity: .month)
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    // Jobs for selected day (full day in the full calendar view)
    private var jobsForSelectedDay: [ScheduledJob] {
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? selectedDate
        let interval = DateInterval(start: startOfDay, end: endOfDay)
        return store.jobs(on: selectedDate, in: interval)
    }

    // Count jobs for a given date (used for day indicators)
    private func jobCount(on date: Date) -> Int {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        let interval = DateInterval(start: startOfDay, end: endOfDay)
        return store.jobs(on: date, in: interval).count
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                weekdayHeader

                monthGrid
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                zoomScale = value
                            }
                            .onEnded { value in
                                withAnimation(.easeOut(duration: 0.15)) {
                                    zoomScale = min(maxZoom, max(minZoom, value))
                                }
                            }
                    )

                // Selected day’s jobs
                jobsList

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 8)
            .padding(.horizontal, 12)
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    router.dismissCalendar()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                        Text("Back")
                    }
                }
            }
        }
        .onAppear {
            // Ensure selectedDate is within the visible month initially
            visibleMonthAnchor = selectedDate
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    visibleMonthAnchor = calendar.date(byAdding: .month, value: -1, to: visibleMonthAnchor) ?? visibleMonthAnchor
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }

            Spacer()

            Text(monthFormatter.string(from: visibleMonthAnchor))
                .font(.headline)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    visibleMonthAnchor = calendar.date(byAdding: .month, value: 1, to: visibleMonthAnchor) ?? visibleMonthAnchor
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
        }
        .padding(.horizontal, 4)
    }

    private var weekdayHeader: some View {
        let fontSize = max(10, min(14, daySize * 0.3))
        return HStack {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 2)
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: daySize), spacing: 6, alignment: .center), count: 7)

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(daysForGrid, id: \.self) { day in
                dayCell(day)
                    .frame(width: daySize, height: daySize)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDate = day
                        // If user taps a day from a different month (no longer shown), keep logic for safety
                        if !isInVisibleMonth(day) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                visibleMonthAnchor = day
                            }
                        }
                    }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isTodayFlag = isToday(date)
        let jobs = jobCount(on: date)

        let numberFontSize = max(12, min(18, daySize * 0.45))
        let badgeSize = max(5, min(10, daySize * 0.18))

        ZStack {
            // Backgrounds for selected or today
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.18))
            } else if isTodayFlag {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.12))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
            }

            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 0.5)

            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: numberFontSize, weight: .semibold))

                // Simple indicator: dot(s) or a small count badge
                if jobs > 0 {
                    if jobs <= 3 {
                        HStack(spacing: 3) {
                            ForEach(0..<min(jobs, 3), id: \.self) { _ in
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: badgeSize, height: badgeSize)
                            }
                        }
                    } else {
                        Text("\(jobs)")
                            .font(.system(size: numberFontSize * 0.55, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(6)
        }
    }

    private var jobsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if jobsForSelectedDay.isEmpty {
                Text("No jobs scheduled for this date.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(jobsForSelectedDay) { job in
                    if let estimate = (store.premiumEstimates.first { $0.id == job.estimateID } ?? store.standardEstimates.first { $0.id == job.estimateID }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(timeFormatter.string(from: job.startDate)) – \(timeFormatter.string(from: job.endDate))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(estimate.jobName.isEmpty ? "Untitled Estimate" : estimate.jobName)
                                .font(.headline)
                            if !estimate.jobLocation.isEmpty {
                                Text(estimate.jobLocation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(timeFormatter.string(from: job.startDate)) – \(timeFormatter.string(from: job.endDate))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Job")
                                .font(.headline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}

#Preview {
    NavigationStack {
        CalendarView()
            .environmentObject(EstimatorStore())
            .environmentObject(PremiumRouter())
    }
}
