import Foundation

struct ProductionTask: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var startDate: Date
    var endDate: Date
    var isDone: Bool

    init(id: UUID = UUID(), name: String, startDate: Date, endDate: Date, isDone: Bool = false) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.isDone = isDone
    }
}
