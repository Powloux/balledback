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

    // Gesture-driven horizontal month paging
    @GestureState private var dragOffsetX: CGFloat = 0

    // Collapse progress from 0 (expanded month) to 1 (collapsed week)
    @State private var collapseProgress: CGFloat = 0

    private let calendar = Calendar.current

    // MARK: - Formatting

    private let monthFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "LLLL yyyy"
        return df
    }()

    private let weekdaySymbols: [String] = {
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = cal.locale
        // Match Apple Calendar’s very short symbols (S M T W T F S), localized
        let symbols = df.veryShortStandaloneWeekdaySymbols ?? df.shortStandaloneWeekdaySymbols ?? ["S","M","T","W","T","F","S"]
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

    // MARK: - Month math

    private var startOfVisibleMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonthAnchor)) ?? visibleMonthAnchor
    }

    private var startOfNextMonth: Date {
        calendar.date(byAdding: .month, value: 1, to: startOfVisibleMonth) ?? startOfVisibleMonth
    }

    // Generate a full grid with leading/trailing days to fill 6 rows x 7 columns (like Apple Calendar)
    private func gridDays(for monthStart: Date) -> [Date] {
        let weekdayOfFirst = calendar.component(.weekday, from: monthStart)
        let firstWeekday = calendar.firstWeekday
        let leading = ((weekdayOfFirst - firstWeekday) + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) ?? monthStart
        let totalCells = 6 * 7
        return (0..<totalCells).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    // Week row for the week containing a given anchor date (7 days, aligned to firstWeekday)
    private func weekRow(containing anchor: Date) -> [Date] {
        let weekday = calendar.component(.weekday, from: anchor)
        let first = calendar.firstWeekday
        let deltaToWeekStart = ((weekday - first) + 7) % 7
        let start = calendar.date(byAdding: .day, value: -deltaToWeekStart, to: anchor) ?? anchor
        return (0..<7).compactMap { i in
            calendar.date(byAdding: .day, value: i, to: start)
        }
    }

    private func isInMonth(_ date: Date, monthStart: Date) -> Bool {
        calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    // MARK: - Jobs

    private func jobs(on date: Date) -> [ScheduledJob] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        let interval = DateInterval(start: startOfDay, end: endOfDay)
        return store.jobs(on: date, in: interval)
    }

    private func jobCount(on date: Date) -> Int {
        jobs(on: date).count
    }

    private var jobsForSelectedDay: [ScheduledJob] {
        jobs(on: selectedDate)
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Collapsible calendar header
                    CollapsibleMonthHeader(
                        monthFormatter: monthFormatter,
                        weekdaySymbols: weekdaySymbols,
                        calendar: calendar,
                        selectedDate: $selectedDate,
                        visibleMonthAnchor: $visibleMonthAnchor,
                        collapseProgress: $collapseProgress,
                        jobCount: { jobCount(on: $0) },
                        handleDayTap: { date, currentMonthStart in
                            handleTap(on: date, currentMonthStart: currentMonthStart)
                        }
                    )

                    // Selected day's jobs
                    jobsSection
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .id("jobsList")
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: CollapseOffsetPreferenceKey.self,
                                        value: geo.frame(in: .named("Scroll")).minY
                                    )
                            }
                        )

                    Spacer(minLength: 8)
                }
            }
            .coordinateSpace(name: "Scroll")
            .onPreferenceChange(CollapseOffsetPreferenceKey.self) { minY in
                // Map content offset to collapse progress [0, 1]
                // Expanded month height approx: weekday header 22 + 6*44 + paddings (~290)
                // Collapsed height approx: weekday header 22 + one row 44 (~66)
                let expanded: CGFloat = CGFloat(22 + 6*44 + 16)
                let collapsed: CGFloat = CGFloat(22 + 44 + 12)
                let range = max(1, expanded - collapsed)
                let offset = max(0, min(expanded, -min(0, minY))) // clamp
                collapseProgress = max(0, min(1, offset / range))
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            let today = Date()
                            selectedDate = today
                            visibleMonthAnchor = today
                            // Optionally scroll to top to fully expand
                            proxy.scrollTo("jobsList", anchor: .top)
                        }
                    } label: {
                        Text("Today")
                    }
                }
            }
            .onAppear {
                visibleMonthAnchor = selectedDate
            }
        }
    }

    // MARK: - Jobs section

    private var jobsSection: some View {
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
        .padding(.bottom, 12)
    }

    // MARK: - Day selection tap handler

    private func handleTap(on date: Date, currentMonthStart: Date) {
        let inThisMonth = calendar.isDate(date, equalTo: currentMonthStart, toGranularity: .month)
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = date
            if !inThisMonth {
                visibleMonthAnchor = date
            } else {
                visibleMonthAnchor = currentMonthStart
            }
        }
    }
}

// MARK: - Collapsible Header

private struct CollapsibleMonthHeader: View {
    let monthFormatter: DateFormatter
    let weekdaySymbols: [String]
    let calendar: Calendar

    @Binding var selectedDate: Date
    @Binding var visibleMonthAnchor: Date
    @Binding var collapseProgress: CGFloat

    // Dots count provider from parent
    var jobCount: (Date) -> Int
    // Tap handler from parent
    var handleDayTap: (Date, Date) -> Void

    // Gesture-driven horizontal month paging
    @GestureState private var dragOffsetX: CGFloat = 0

    private var startOfVisibleMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonthAnchor)) ?? visibleMonthAnchor
    }

    private var startOfNextMonth: Date {
        calendar.date(byAdding: .month, value: 1, to: startOfVisibleMonth) ?? startOfVisibleMonth
    }

    var body: some View {
        VStack(spacing: 8) {
            header

            weekdayHeader

            // Interpolate between full month pager and single week row
            ZStack {
                // Full month pager (fades out as collapse progresses)
                monthPager
                    .opacity(1 - Double(collapseProgress))

                // Collapsed single week for selected date (fades in)
                weekStrip
                    .opacity(Double(collapseProgress))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(
            Rectangle()
                .fill(Color(.systemBackground))
        )
    }

    // Header with chevrons and month title
    private var header: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    visibleMonthAnchor = calendar.date(byAdding: .month, value: -1, to: visibleMonthAnchor) ?? visibleMonthAnchor
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }

            Spacer()

            Text(monthFormatter.string(from: startOfVisibleMonth))
                .font(.headline)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
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
        HStack {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 2)
    }

    // Month pager with swipe gestures (3 pages: prev, current, next)
    private var monthPager: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 0) {
                monthGrid(for: calendar.date(byAdding: .month, value: -1, to: startOfVisibleMonth) ?? startOfVisibleMonth)
                    .frame(width: width)
                monthGrid(for: startOfVisibleMonth)
                    .frame(width: width)
                monthGrid(for: startOfNextMonth)
                    .frame(width: width)
            }
            .offset(x: -width + dragOffsetX)
            .gesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .updating($dragOffsetX) { value, state, _ in
                        state = value.translation.width
                    }
                    .onEnded { value in
                        let threshold = width * 0.25
                        let translation = value.translation.width
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if translation < -threshold {
                                // Swipe left -> next month
                                visibleMonthAnchor = calendar.date(byAdding: .month, value: 1, to: visibleMonthAnchor) ?? visibleMonthAnchor
                            } else if translation > threshold {
                                // Swipe right -> previous month
                                visibleMonthAnchor = calendar.date(byAdding: .month, value: -1, to: visibleMonthAnchor) ?? visibleMonthAnchor
                            }
                        }
                    }
            )
        }
        .frame(height: CGFloat(6 * 44 + 8)) // 6 rows, Apple-like height
        .clipped()
    }

    private func monthGrid(for monthStart: Date) -> some View {
        let days = gridDays(for: monthStart)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(days, id: \.self) { date in
                dayCell(date, currentMonthStart: monthStart)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleDayTap(date, monthStart)
                    }
            }
        }
        .padding(.vertical, 4)
    }

    private func gridDays(for monthStart: Date) -> [Date] {
        let weekdayOfFirst = calendar.component(.weekday, from: monthStart)
        let firstWeekday = calendar.firstWeekday
        let leading = ((weekdayOfFirst - firstWeekday) + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) ?? monthStart
        let totalCells = 6 * 7
        return (0..<totalCells).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    // Single week strip anchored to the selected date's week
    private var weekStrip: some View {
        let weekDays = weekRow(containing: selectedDate)
        return HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { date in
                dayCell(date, currentMonthStart: startOfVisibleMonth)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleDayTap(date, startOfVisibleMonth)
                    }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Day cell

    @ViewBuilder
    private func dayCell(_ date: Date, currentMonthStart: Date) -> some View {
        let isInMonth = calendar.isDate(date, equalTo: currentMonthStart, toGranularity: .month)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isTodayFlag = calendar.isDateInToday(date)
        let count = jobCount(date)

        ZStack {
            // Background selection like Apple: circle fill for selected; today has a thin ring
            if isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
            } else if isTodayFlag {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: 32, height: 32)
            }

            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : (isInMonth ? Color.primary : Color.secondary.opacity(0.6)))

                // Event indicators: up to 3 dots, otherwise show +N
                if count > 0 {
                    if count <= 3 {
                        HStack(spacing: 3) {
                            ForEach(0..<count, id: \.self) { _ in
                                Circle()
                                    .fill(isSelected ? Color.white : Color.accentColor)
                                    .frame(width: 4.5, height: 4.5)
                            }
                        }
                    } else {
                        Text("+\(count - 3)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.accentColor)
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 6)
        .background(
            Rectangle()
                .fill(Color.clear)
        )
    }

    // MARK: - Helpers for week/month rows

    private func weekRow(containing anchor: Date) -> [Date] {
        let weekday = calendar.component(.weekday, from: anchor)
        let first = calendar.firstWeekday
        let deltaToWeekStart = ((weekday - first) + 7) % 7
        let start = calendar.date(byAdding: .day, value: -deltaToWeekStart, to: anchor) ?? anchor
        return (0..<7).compactMap { i in
            calendar.date(byAdding: .day, value: i, to: start)
        }
    }
}

// MARK: - Collapse offset preference

private struct CollapseOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Use the latest
        value = nextValue()
    }
}

#Preview {
    NavigationStack {
        CalendarView()
            .environmentObject(EstimatorStore())
            .environmentObject(PremiumRouter())
    }
}
