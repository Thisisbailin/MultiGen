import SwiftUI

struct ChatBubble: View {
    let message: AIChatMessage
    var isExpanded: Bool = false
    var onToggleDetail: () -> Void = {}

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.role.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(foregroundColor)
                    if message.images.isEmpty == false {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(message.images, id: \.self) { image in
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 140, height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.secondary.opacity(0.2))
                                        )
                                }
                            }
                        }
                        .frame(maxHeight: 160)
                    }
                }
                if let detail = message.detail {
                    Button(action: onToggleDetail) {
                        Label(isExpanded ? "收起操作详情" : "查看操作详情", systemImage: isExpanded ? "chevron.up.circle" : "chevron.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    if isExpanded {
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(detail)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 140)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.05))
                        )
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(backgroundColor)
            )
            if message.role != .user { Spacer(minLength: 0) }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor
        case .assistant:
            return Color(nsColor: .windowBackgroundColor)
        case .system:
            return Color.orange.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch message.role {
        case .user:
            return Color.white
        case .assistant:
            return .primary
        case .system:
            return .primary
        }
    }
}

struct ChatMessageList: View {
    let messages: [AIChatMessage]
    @Binding var expandedIDs: Set<UUID>

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubble(
                            message: message,
                            isExpanded: expandedIDs.contains(message.id),
                            onToggleDetail: { toggleExpand(message) }
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func toggleExpand(_ message: AIChatMessage) {
        guard message.detail != nil else { return }
        if expandedIDs.contains(message.id) {
            expandedIDs.remove(message.id)
        } else {
            expandedIDs.insert(message.id)
        }
    }
}

struct ChatInputBar: View {
    @Binding var inputText: String
    let isSending: Bool
    let allowsAttachments: Bool
    let canAddAttachments: Bool
    let onAddAttachment: () -> Void
    let onHistory: () -> Void
    let onSend: () -> Void

    @FocusState private var isTextFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField("向 AI 描述你的需求…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .focused($isTextFocused)
                .disabled(isSending)

            Button(action: onAddAttachment) {
                Image(systemName: "paperclip")
                    .font(.title3)
                    .opacity(allowsAttachments && canAddAttachments ? 1 : 0.3)
            }
            .buttonStyle(.plain)
            .disabled(isSending || allowsAttachments == false || canAddAttachments == false)

            Button(action: onHistory) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: onSend) {
                if isSending {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

struct AIChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
        case system

        var displayName: String {
            switch self {
            case .user: return "我"
            case .assistant: return "AI"
            case .system: return "系统"
            }
        }
    }

    let id: UUID
    let role: Role
    let text: String
    let detail: String?
    let images: [NSImage]

    init(id: UUID = UUID(), role: Role, text: String, detail: String? = nil, images: [NSImage] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.detail = detail
        self.images = images
    }
}

extension AIChatMessage {
    init(record: StoredChatMessage) {
        self.init(
            id: record.id,
            role: record.role.asChatRole,
            text: record.text,
            detail: record.detail,
            images: []
        )
    }

    var record: StoredChatMessage {
        StoredChatMessage(
            id: id,
            role: StoredChatMessage.Role(role: role),
            text: text,
            detail: detail
        )
    }
}
