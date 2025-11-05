import Foundation

struct ScheduledJob: Identifiable, Hashable, Codable {
    let id: UUID
    let estimateID: UUID
    var startDate: Date
    var endDate: Date
    var notes: String?

    init(
        id: UUID = UUID(),
        estimateID: UUID,
        startDate: Date,
        endDate: Date,
        notes: String? = nil
    ) {
        self.id = id
        self.estimateID = estimateID
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
    }
}
