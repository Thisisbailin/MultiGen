import Foundation

struct SceneCharacter: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var role: String

    init(id: UUID = UUID(), name: String = "", role: String = "") {
        self.id = id
        self.name = name
        self.role = role
    }
}
