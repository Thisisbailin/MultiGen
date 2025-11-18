import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

struct AIChatSidebarView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var promptLibraryStore: PromptLibraryStore
    @EnvironmentObject private var navigationStore: NavigationStore
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var storyboardStore: StoryboardStore
    @State private var messages: [AIChatMessage] = []
    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isTextFocused: Bool
    @State private var expandedMessageIDs: Set<UUID> = []
    @State private var pendingSummaryMessageID: UUID?
    @State private var imageAttachments: [ImageAttachment] = []
    private let projectSummaryPromptText = "请基于 projectContext 中提供的资料生成一段 250-350 字的专业项目简介，强调核心卖点、主冲突以及视听/类型特色，并指出潜在受众。"

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubble(
                                message: message,
                                isExpanded: expandedMessageIDs.contains(message.id),
                                onToggleDetail: {
                                    guard message.detail != nil else { return }
                                    if expandedMessageIDs.contains(message.id) {
                                        expandedMessageIDs.remove(message.id)
                                    } else {
                                        expandedMessageIDs.insert(message.id)
                                    }
                                }
                            )
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .padding(.horizontal, -2)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if imageAttachments.isEmpty == false {
                    attachmentStrip
                }
                modelStatusView
                inputComposer
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .onAppear {
            processPendingProjectSummary()
        }
        .onChange(of: navigationStore.pendingProjectSummaryID) { _, _ in
            processPendingProjectSummary()
        }
        .onChange(of: navigationStore.pendingAIChatSystemMessage) { _, newValue in
            guard let message = newValue else { return }
            navigationStore.pendingAIChatSystemMessage = nil
            let systemMessage = AIChatMessage(role: .system, text: message)
            messages.append(systemMessage)
        }
    }

    private func processPendingProjectSummary() {
        guard let projectID = navigationStore.pendingProjectSummaryID else { return }
        navigationStore.pendingProjectSummaryID = nil
        guard let project = scriptStore.projects.first(where: { $0.id == projectID }) else {
            return
        }
        let context = ChatContext.scriptProject(project: project)
        let module = PromptDocument.Module.scriptProjectSummary
        sendProjectSummary(project, context: context, module: module)
    }

    private func sendProjectSummary(_ project: ScriptProject, context: ChatContext, module: PromptDocument.Module) {
        guard isSending == false else { return }
        isSending = true
        errorMessage = nil
        let userMessage = AIChatMessage(role: .system, text: "正在生成《\(project.title)》的项目总结...")
        messages.append(userMessage)
        pendingSummaryMessageID = userMessage.id

        Task {
            do {
                let request = makeChatActionRequest(
                    prompt: projectSummaryPromptText,
                    context: context,
                    module: module,
                    kind: .projectSummary,
                    origin: originLabel(for: context),
                    attachments: []
                )
                var collected = ""
                let stream = actionCenter.stream(request)
                messages.append(AIChatMessage(role: .assistant, text: "（正在生成...）", detail: nil))
                let placeholderID = messages.last!.id
                for try await event in stream {
                    switch event {
                    case .partial(let partialText):
                        collected += partialText
                        if let index = messages.firstIndex(where: { $0.id == placeholderID }) {
                            messages[index] = AIChatMessage(id: placeholderID, role: .assistant, text: collected)
                        }
                    case .completed(let result):
                        handleAIResponse(result: result, context: context, targetMessageID: placeholderID)
                        let finalSummary = (result.text ?? collected).trimmingCharacters(in: .whitespacesAndNewlines)
                        if finalSummary.isEmpty == false {
                            await persistProjectSummary(finalSummary, project: project)
                        }
                    }
                }
            } catch {
                errorMessage = "生成失败：\(error.localizedDescription)"
            }
            isSending = false
            pendingSummaryMessageID = nil
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard isSending == false else { return }

        let context = activeContext
        let module = activePromptModule
        let origin = originLabel(for: context)
        let request = makeChatActionRequest(
            prompt: trimmed,
            context: context,
            module: module,
            kind: .conversation,
            origin: origin,
            attachments: imageAttachments
        )

        messages.append(AIChatMessage(role: .user, text: trimmed))
        inputText = ""
        errorMessage = nil
        isSending = true

        Task {
            defer { isSending = false }
            var collected = ""
            let stream = actionCenter.stream(request)
            messages.append(AIChatMessage(role: .assistant, text: "（正在生成...）", detail: nil))
            let placeholderID = messages.last!.id

            do {
                for try await event in stream {
                    switch event {
                    case .partial(let text):
                        collected += text
                        if let index = messages.firstIndex(where: { $0.id == placeholderID }) {
                            messages[index] = AIChatMessage(id: placeholderID, role: .assistant, text: collected)
                        }
                    case .completed(let result):
                        handleAIResponse(result: result, context: context, targetMessageID: placeholderID)
                    }
                }
                await MainActor.run {
                    imageAttachments.removeAll()
                }
            } catch {
                errorMessage = "请求失败：\(error.localizedDescription)"
                if let index = messages.firstIndex(where: { $0.id == placeholderID }) {
                    messages.remove(at: index)
                }
            }
        }
    }

    private func addImageAttachment() {
        let remaining = max(0, 3 - imageAttachments.count)
        guard remaining > 0 else {
            errorMessage = "最多只能附加 3 张图片。"
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType.jpeg,
            UTType.png,
            UTType.tiff,
            UTType.bmp,
            UTType.gif,
            UTType.heic
        ].compactMap { $0 }
        panel.prompt = "添加"

        if panel.runModal() == .OK {
            let urls = Array(panel.urls.prefix(remaining))
            for url in urls {
                guard let data = try? Data(contentsOf: url),
                      let image = NSImage(data: data) else {
                    errorMessage = "无法读取图片：\(url.lastPathComponent)"
                    continue
                }
                imageAttachments.append(
                    ImageAttachment(
                        data: data,
                        preview: image,
                        fileName: url.lastPathComponent
                    )
                )
            }
        }
    }

    private func removeAttachment(_ id: UUID) {
        imageAttachments.removeAll { $0.id == id }
    }

    private func handleAIResponse(result: AIActionResult, context: ChatContext, targetMessageID: UUID? = nil) {
        let detail = """
        Route: \(result.route.displayName)
        Model: \(result.metadata.model)
        Duration: \(result.metadata.duration)s
        """
        if let targetMessageID, let index = messages.firstIndex(where: { $0.id == targetMessageID }) {
            messages[index] = AIChatMessage(
                id: targetMessageID,
                role: .assistant,
                text: result.text ?? "(无文本输出)",
                detail: detail
            )
        } else {
            messages.append(
                AIChatMessage(
                    role: .assistant,
                    text: result.text ?? "(无文本输出)",
                    detail: detail
                )
            )
        }
        if let summaryID = pendingSummaryMessageID,
           let index = messages.firstIndex(where: { $0.id == summaryID }) {
            messages.remove(at: index)
        }
    }

    private func persistProjectSummary(_ summary: String, project: ScriptProject) async {
        await MainActor.run {
            scriptStore.updateProject(id: project.id) { editable in
                editable.synopsis = summary
            }
            navigationStore.pendingAIChatSystemMessage = "项目《\(project.title)》简介已更新。"
        }
    }

    @ViewBuilder
    private var modelStatusView: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("当前路线：\(dependencies.currentTextRoute().displayName) · \(dependencies.currentTextModelLabel())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(contextStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(contextModeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inputComposer: some View {
        HStack(spacing: 10) {
            TextField("向 Gemini 描述你的需求…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .focused($isTextFocused)
                .disabled(isSending)

            Button {
                addImageAttachment()
            } label: {
                Image(systemName: "paperclip")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(isSending || imageAttachments.count >= 3)

            Button {
                sendMessage()
            } label: {
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

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(imageAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: attachment.preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.2))
                            )
                        Button {
                            removeAttachment(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
        }
    }

    private func contextModeText(for context: ChatContext) -> String {
        switch context {
        case .general:
            return "模式：主页 · 对话建议"
        case .script(_, let episode):
            return "模式：剧本 · \(episode.displayLabel)"
        case .storyboard(_, let episode, let scene, let snapshot, _):
            var base = "模式：分镜 · \(episode.displayLabel)"
            if let title = scene?.title ?? snapshot?.title {
                base += " · \(title)"
            }
            return base
        case .scriptProject(let project):
            return "模式：项目总结 · \(project.title)"
        }
    }

    private func contextStatusText(for context: ChatContext) -> String {
        switch context {
        case .general:
            switch navigationStore.selection {
            case .script:
                return "上下文：剧本 · 列表"
            case .storyboard:
                return "上下文：分镜 · 列表"
            default:
                return "上下文：主页聊天"
            }
        case .script(_, let episode):
            return "上下文：剧本 · \(episode.displayLabel)"
        case .storyboard(_, let episode, let scene, let snapshot, let workspace):
            let count = workspace?.entries.count ?? 0
            var base = "上下文：分镜 · \(episode.displayLabel)"
            if let title = scene?.title ?? snapshot?.title {
                base += " · \(title)"
            }
            base += " · \(count) 镜头"
            return base
        case .scriptProject(let project):
            return "上下文：项目 · \(project.title)"
        }
    }

    private func originLabel(for context: ChatContext) -> String {
        switch context {
        case .general:
            return "智能协同"
        case .script:
            return "剧本助手"
        case .storyboard:
            return "分镜助手"
        case .scriptProject:
            return "项目总结"
        }
    }

    private var activeContext: ChatContext {
        switch navigationStore.selection {
        case .script:
            if let episode = scriptEpisode(for: navigationStore.currentScriptEpisodeID) {
                return .script(project: project(for: episode.id), episode: episode)
            }
        case .storyboard:
            if let episodeID = navigationStore.currentStoryboardEpisodeID,
               let episode = scriptEpisode(for: episodeID) {
                let project = project(for: episode.id)
                let workspace = storyboardStore.workspace(for: episodeID)
                let scene = episode.scenes.first(where: { $0.id == navigationStore.currentStoryboardSceneID })
                let snapshot = navigationStore.currentStoryboardSceneSnapshot
                return .storyboard(project: project, episode: episode, scene: scene, snapshot: snapshot, workspace: workspace)
            }
        default:
            break
        }
        return .general
    }

    private var activePromptModule: PromptDocument.Module {
        switch activeContext {
        case .general:
            return .aiConsole
        case .script:
            return .script
        case .storyboard:
            return .storyboard
        case .scriptProject:
            return .scriptProjectSummary
        }
    }

    private var contextStatusText: String {
        contextStatusText(for: activeContext)
    }

    private var contextModeText: String {
        contextModeText(for: activeContext)
    }

    private func makeChatActionRequest(
        prompt: String,
        context: ChatContext,
        module: PromptDocument.Module,
        kind: AIActionKind,
        origin: String,
        attachments: [ImageAttachment]
    ) -> AIActionRequest {
        let fields = makeRequestFields(prompt: prompt, context: context, module: module, attachments: attachments)
        let summary = contextStatusText(for: context)
        return AIActionRequest(
            kind: kind,
            action: .aiConsole,
            channel: .text,
            fields: fields,
            assetReferences: attachments.map(\.fileName),
            module: module,
            context: context,
            contextSummaryOverride: summary,
            origin: origin
        )
    }

    private func makeRequestFields(
        prompt: String,
        context: ChatContext,
        module: PromptDocument.Module,
        attachments: [ImageAttachment]
    ) -> [String: String] {
        let systemPrompt = promptLibraryStore.document(for: module)
            .content.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = contextStatusText(for: context)
        var fields = AIChatRequestBuilder.makeFields(
            prompt: prompt,
            context: context,
            module: module,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
            statusText: summary
        )
        if attachments.isEmpty == false {
            fields["imageAttachmentCount"] = "\(attachments.count)"
            for (index, attachment) in attachments.enumerated() {
                let key = "imageAttachment\(index + 1)"
                fields["\(key)FileName"] = attachment.fileName
                fields["\(key)Base64"] = attachment.base64String
            }
        }
        return fields
    }

    private func scriptEpisode(for id: UUID?) -> ScriptEpisode? {
        guard let id else { return nil }
        for project in scriptStore.projects {
            if let episode = project.episodes.first(where: { $0.id == id }) {
                return episode
            }
        }
        return nil
    }

    private func project(for episodeID: UUID) -> ScriptProject? {
        scriptStore.projects.first { project in
            project.episodes.contains(where: { $0.id == episodeID })
        }
    }

    private func makeProjectContext(project: ScriptProject) -> String {
        var lines: [String] = []
        lines.append("项目：\(project.title)")
        lines.append("类型：\(project.type.displayName)")
        if project.tags.isEmpty == false {
            lines.append("标签：\(project.tags.joined(separator: "｜"))")
        }
        if let start = project.productionStartDate {
            lines.append("制作起始：\(start.formatted(date: .abbreviated, time: .omitted))")
        }
        if let end = project.productionEndDate {
            lines.append("制作结束：\(end.formatted(date: .abbreviated, time: .omitted))")
        }
        if project.synopsis.isEmpty == false {
            lines.append("简介：\(project.synopsis)")
        }
        return lines.joined(separator: "\n")
    }

    private func makeScriptContext(episode: ScriptEpisode, project: ScriptProject?) -> String {
        var lines: [String] = []
        if let project {
            lines.append("项目：\(project.title)")
        }
        lines.append("剧集：\(episode.displayLabel)")
        if episode.synopsis.isEmpty == false {
            lines.append("简介：\(episode.synopsis)")
        }
        let body = sanitizedBody(episode.markdown, limit: 6000)
        lines.append("正文：\n\(body)")
        return lines.joined(separator: "\n")
    }

    private func makeSceneContext(scene: ScriptScene) -> String {
        makeSceneContext(
            title: scene.title,
            order: scene.order,
            summary: scene.summary,
            body: scene.body
        )
    }

    private func makeSceneContext(snapshot: StoryboardSceneContextSnapshot) -> String {
        makeSceneContext(
            title: snapshot.title,
            order: snapshot.order,
            summary: snapshot.summary,
            body: snapshot.body
        )
    }

    private func makeSceneContext(title: String, order: Int?, summary: String, body: String) -> String {
        var lines: [String] = []
        if let order {
            lines.append("场景：\(title) · 序号 \(order)")
        } else {
            lines.append("场景：\(title)")
        }
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines.append("摘要：\(summary)")
        }
        let normalizedBody = sanitizedBody(body, limit: 3000)
        lines.append("正文：\n\(normalizedBody)")
        return lines.joined(separator: "\n")
    }

    private func makeStoryboardContext(workspace: StoryboardWorkspace?) -> String? {
        guard let workspace else { return nil }
        let entries = workspace.orderedEntries
        guard entries.isEmpty == false else { return nil }
        let maxShots = 12
        var blocks: [String] = []
        for entry in entries.prefix(maxShots) {
            var segment: [String] = []
            segment.append("镜\(entry.fields.shotNumber) · \(entry.sceneTitle)")
            let tags = [
                entry.fields.shotScale.isEmpty ? nil : "景别：\(entry.fields.shotScale)",
                entry.fields.cameraMovement.isEmpty ? nil : "运镜：\(entry.fields.cameraMovement)",
                entry.fields.duration.isEmpty ? nil : "时长：\(entry.fields.duration)"
            ].compactMap { $0 }.joined(separator: "｜")
            if tags.isEmpty == false {
                segment.append(tags)
            }
            if entry.sceneSummary.isEmpty == false {
                segment.append("画面：\(entry.sceneSummary)")
            }
            if entry.fields.dialogueOrOS.isEmpty == false {
                segment.append("台词/OS：\(entry.fields.dialogueOrOS)")
            }
            if entry.fields.aiPrompt.isEmpty == false {
                segment.append("提示词：\(entry.fields.aiPrompt)")
            }
            if entry.notes.isEmpty == false {
                segment.append("备注：\(entry.notes)")
            }
            blocks.append(segment.joined(separator: "\n"))
        }
        if entries.count > maxShots {
            blocks.append("……其余 \(entries.count - maxShots) 个镜头已省略。")
        }
        return blocks.joined(separator: "\n\n")
    }

    private func sanitizedBody(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "（尚未提供剧本文本）"
        }
        if trimmed.count <= limit {
            return trimmed
        }
        let prefixText = trimmed.prefix(limit)
        return "\(prefixText)…（已截断）"
    }
}

enum ChatContext: Equatable {
    case general
    case script(project: ScriptProject?, episode: ScriptEpisode)
    case storyboard(project: ScriptProject?, episode: ScriptEpisode, scene: ScriptScene?, snapshot: StoryboardSceneContextSnapshot?, workspace: StoryboardWorkspace?)
    case scriptProject(project: ScriptProject)
}

private struct ChatBubble: View {
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
                }
                if let detail = message.detail {
                    Button {
                        onToggleDetail()
                    } label: {
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
            return Color(nsColor: .controlBackgroundColor)
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

struct AIChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
        case system

        var displayName: String {
            switch self {
            case .user: return "我"
            case .assistant: return "Gemini"
            case .system: return "系统"
            }
        }
    }

    let id: UUID
    let role: Role
    let text: String
    let detail: String?

    init(id: UUID = UUID(), role: Role, text: String, detail: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.detail = detail
    }
}

private struct ImageAttachment: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let preview: NSImage
    let fileName: String

    var base64String: String { data.base64EncodedString() }
}
