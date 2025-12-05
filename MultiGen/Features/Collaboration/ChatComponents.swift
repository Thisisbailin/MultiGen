import SwiftUI
import Foundation

struct ChatBubble: View {
    let message: AIChatMessage
    var isExpanded: Bool = false
    var onToggleDetail: () -> Void = {}
    var onImageTap: (NSImage) -> Void = { _ in }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 8) {
                bubbleContent
                if hasAttachments {
                    attachmentStrip
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            if message.role != .user { Spacer(minLength: 0) }
        }
    }

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message.text)
                .font(.body)
                .foregroundStyle(foregroundColor)
                .textSelection(.enabled)
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
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(message.images.enumerated()), id: \.offset) { _, image in
                    AttachmentCard(image: image)
                        .onTapGesture { onImageTap(image) }
                }
                if message.images.isEmpty, let remoteURL = extractImageURL(from: message.text) {
                    RemoteAttachmentCard(url: remoteURL)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var hasAttachments: Bool {
        message.images.isEmpty == false || extractImageURL(from: message.text) != nil
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

    private func extractImageURL(from text: String) -> URL? {
        if let markdownURL = extractMarkdownImageURL(from: text) {
            return markdownURL
        }
        let pattern = #"https?://\S+"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            let candidate = String(text[range]).trimmingCharacters(in: .punctuationCharacters)
            return URL(string: candidate)
        }
        return nil
    }

    private func extractMarkdownImageURL(from text: String) -> URL? {
        let pattern = #"!\[.*?\]\((https?://.*?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard let match = results.first, match.numberOfRanges >= 2 else { return nil }
        let urlString = nsText.substring(with: match.range(at: 1)).replacingOccurrences(of: "\\", with: "")
        return URL(string: urlString)
    }
}

private struct AttachmentCard: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 132, height: 100)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2))
            )
    }
}

private struct RemoteAttachmentCard: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(width: 132, height: 100)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 132, height: 100)
                    .clipped()
            case .failure:
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("图片加载失败")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 132, height: 100)
            @unknown default:
                EmptyView()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.2))
        )
    }
}

struct ChatMessageList: View {
    let messages: [AIChatMessage]
    @Binding var expandedIDs: Set<UUID>
    var onImageTap: (NSImage) -> Void = { _ in }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubble(
                            message: message,
                            isExpanded: expandedIDs.contains(message.id),
                            onToggleDetail: { toggleExpand(message) },
                            onImageTap: onImageTap
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
                .onSubmit(onSend)
                .submitLabel(.send)
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

struct ImagePreviewSheet: View {
    let image: NSImage
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.9).ignoresSafeArea()
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: max(320, geo.size.width - 80),
                            maxHeight: max(240, geo.size.height - 120)
                        )
                        .padding()
                }
            }

            Button {
                onClose()
            } label: {
                Label("关闭", systemImage: "xmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .padding(10)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
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
