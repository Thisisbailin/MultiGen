import Foundation

struct ChatHistoryEntry: Identifiable {
    let key: ChatThreadKey
    let module: AIChatModule
    let title: String
    let subtitle: String
    let preview: String
    let messageCount: Int

    var id: ChatThreadKey { key }
}
