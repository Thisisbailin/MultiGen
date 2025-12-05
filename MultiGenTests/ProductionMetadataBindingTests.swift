import Foundation
import Testing
@testable import MultiGen

struct ProductionMetadataBindingTests {
    @Test func persistsMembersTasksAndAssignments() throws {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storageURL) }

        let episodeA = ScriptEpisode(episodeNumber: 1, title: "Ep1", markdown: "md1")
        let episodeB = ScriptEpisode(episodeNumber: 2, title: "Ep2", markdown: "md2")
        let project = ScriptProject(
            id: UUID(),
            title: "Production Binding",
            episodes: [episodeA, episodeB]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode([project])
        try data.write(to: storageURL)

        let store = ScriptStore(storageURL: storageURL)

        let memberA = ProductionMember(name: "Alice", colorHex: "#FF7A00")
        let memberB = ProductionMember(name: "Bob", colorHex: "#4A90E2")
        let tasks = [
            ProductionTask(
                name: "Prep",
                startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 3600)
            )
        ]
        let assignments: [UUID: UUID?] = [
            episodeA.id: memberA.id,
            episodeB.id: nil
        ]

        store.updateProductionMetadata(
            projectID: project.id,
            members: [memberA, memberB],
            tasks: tasks,
            assignments: assignments
        )

        guard let updated = store.project(id: project.id) else {
            Issue("Project missing after production metadata update")
            return
        }

        #expect(updated.productionMembers == [memberA, memberB])
        #expect(updated.productionTasks == tasks)
        let storedAssignments = Dictionary(uniqueKeysWithValues: updated.episodes.map { ($0.id, $0.producerID) })
        #expect(storedAssignments[episodeA.id] == memberA.id)
        #expect(storedAssignments[episodeB.id] == nil)
    }
}
