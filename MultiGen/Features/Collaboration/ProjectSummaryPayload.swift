import Foundation

struct ProjectSummaryPayload: Decodable {
    struct Character: Decodable {
        let name: String
        let role: String?
        let profile: String?
    }

    struct Scene: Decodable {
        let name: String
        let description: String?
        let episodes: [Int]?
    }

    let overview: String?
    let tags: [String]?
    let characters: [Character]?
    let scenes: [Scene]?
}
