import SwiftUI
import AppKit

private enum SettingsSection: Hashable, CaseIterable, Identifiable {
    case general
    case gemini
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "通用"
        case .gemini: return "Gemini"
        case .about: return "关于"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .gemini: return "sparkles"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SettingsSection = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("应用设置")
                    .font(.system(.largeTitle, weight: .semibold))
                Text("集中管理外观偏好、Gemini 连接与应用信息。")
                    .foregroundStyle(.secondary)
            }

            TabView(selection: $selection) {
                GeneralSettingsTab()
                    .tabItem {
                        Label(SettingsSection.general.title, systemImage: SettingsSection.general.icon)
                    }
                    .tag(SettingsSection.general)
                GeminiSettingsTab()
                    .tabItem {
                        Label(SettingsSection.gemini.title, systemImage: SettingsSection.gemini.icon)
                    }
                    .tag(SettingsSection.gemini)
                AboutSettingsTab()
                    .tabItem {
                        Label(SettingsSection.about.title, systemImage: SettingsSection.about.icon)
                    }
                    .tag(SettingsSection.about)
            }
            .padding(.top, 8)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 520)
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var configuration: AppConfiguration
    @EnvironmentObject private var navigationStore: NavigationStore

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { configuration.appearance },
            set: { configuration.updateAppearance($0) }
        )
    }

    private var aiMemoryBinding: Binding<Bool> {
        Binding(
            get: { configuration.aiMemoryEnabled },
            set: { configuration.updateAIMemoryEnabled($0) }
        )
    }

    var body: some View {
        Form {
            Section("外观") {
                Picker("界面模式", selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                Text("默认跟随系统外观；如需固定浅色或深色，可在此切换。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("对话历史") {
                Button {
                    navigationStore.sidebarMode = .ai
                    navigationStore.selection = .home
                    navigationStore.isShowingConversationHistory = true
                } label: {
                    Label("打开对话历史中心", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderedProminent)
                Text("历史中心统一管理各模块对话，可在其中查看、切换或删除记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("提示：对话历史默认始终保存于本地（仅当前设备），关闭应用后也可继续同一对话。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("AI 记忆") {
                Toggle("启用 AI 记忆能力", isOn: aiMemoryBinding)
                Text("开启后，我们会在单次对话中自动注入近期历史上下文，帮助 Gemini 记住之前的交流。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }
}

private struct GeminiSettingsTab: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var configuration: AppConfiguration

    @State private var apiKeyInput: String = ""
    @State private var keyStatus: String = "未检测"
    @State private var selectedTextModel: GeminiModel = .defaultTextModel
    @State private var selectedImageModel: GeminiModel = .defaultImageModel
    @State private var feedbackMessage: String?
    @State private var feedbackColor: Color = .secondary
    @State private var isTestingConnection = false
    @State private var showInputPlaintext = false
    @State private var revealStoredKey = false
    @State private var storedKeyPlaintext: String?

    @State private var relayEnabled = false
    @State private var relayProviderName = ""
    @State private var relayBaseURL = ""
    @State private var relayAPIKey = ""
    @State private var relayModels: [String] = []
    @State private var relaySelectedTextModel: String = ""
    @State private var relaySelectedImageModel: String = ""
    @State private var isSyncingRelayModels = false

    @State private var textTestInput: String = ""
    @State private var textTestResponse: String = ""
    @State private var isSubmittingTextTest = false
    @State private var isSubmittingImageTest = false
    @State private var imageTestStatus: String?
    @State private var imageTestImage: NSImage?
    @State private var isExportingAudit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                modelSection
                apiKeySection
                testSection
                imageTestSection
                relaySection
                auditSection
            }
            .formStyle(.grouped)

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.subheadline)
                    .foregroundStyle(feedbackColor)
            }
        }
        .padding(.horizontal, 4)
        .onAppear(perform: loadState)
        .onChange(of: selectedTextModel) { _, newValue in
            configuration.updateTextModel(newValue)
        }
        .onChange(of: selectedImageModel) { _, newValue in
            configuration.updateImageModel(newValue)
        }
        .onChange(of: relayEnabled) { _, newValue in
            configuration.updateRelayEnabled(newValue)
        }
        .onChange(of: relayProviderName) { _, newValue in
            configuration.updateRelayProvider(name: newValue)
        }
        .onChange(of: relayBaseURL) { _, _ in
            configuration.updateRelayEndpoint(baseURL: relayBaseURL, apiKey: relayAPIKey)
        }
        .onChange(of: relayAPIKey) { _, _ in
            configuration.updateRelayEndpoint(baseURL: relayBaseURL, apiKey: relayAPIKey)
        }
        .onChange(of: relaySelectedTextModel) { _, newValue in
            configuration.updateRelaySelectedTextModel(newValue.isEmpty ? nil : newValue)
        }
        .onChange(of: relaySelectedImageModel) { _, newValue in
            configuration.updateRelaySelectedImageModel(newValue.isEmpty ? nil : newValue)
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        Section("模型设置") {
            Picker("文本模型", selection: $selectedTextModel) {
                ForEach(GeminiModel.textOptions) { model in
                    Text(model.displayName).tag(model)
                }
            }
            Picker("图像模型", selection: $selectedImageModel) {
                ForEach(GeminiModel.imageOptions) { model in
                    Text(model.displayName).tag(model)
                }
            }
        }
    }

    @ViewBuilder
    private var imageTestSection: some View {
        Section("图像连通性测试") {
            VStack(alignment: .leading, spacing: 8) {
                Text("使用当前图像模型发起一次简单生成，确认官方或中转路线可用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    submitImageTest()
                } label: {
                    if isSubmittingImageTest {
                        ProgressView()
                    } else {
                        Label("生成测试图像", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmittingImageTest)

                if let imageTestStatus {
                    Text(imageTestStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let preview = imageTestImage {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        Section("API Key") {
            HStack {
                if showInputPlaintext {
                    TextField("输入 Gemini API Key", text: $apiKeyInput)
                } else {
                    SecureField("输入 Gemini API Key", text: $apiKeyInput)
                }
                Button {
                    showInputPlaintext.toggle()
                } label: {
                    Image(systemName: showInputPlaintext ? "eye.slash" : "eye")
                }
                .help(showInputPlaintext ? "隐藏输入内容" : "显示输入内容")
            }

            HStack(spacing: 8) {
                Text("当前状态：\(keyStatus)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if isKeyActive {
                    Button(revealStoredKey ? "隐藏密钥" : "查看密钥") {
                        withAnimation(.easeInOut) { revealStoredKey.toggle() }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button("保存密钥") { saveKey() }
                    .buttonStyle(.borderedProminent)
                Button("清除密钥", role: .destructive) { clearKey() }
            }
            if revealStoredKey, let storedKeyPlaintext {
                Text("当前密钥：\(storedKeyPlaintext)")
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            HStack {
                TextField("粘贴或输入新的密钥", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .disableAutocorrection(true)
                Button("粘贴") {
                    if let clipboard = NSPasteboard.general.string(forType: .string) {
                        apiKeyInput = clipboard
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var testSection: some View {
        Section("官方模型调试") {
            VStack(alignment: .leading, spacing: 8) {
                Text("输入任意提示词测试文本模型。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("向 Gemini 输入一句需求", text: $textTestInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)
                Button {
                    submitTextTest()
                } label: {
                    if isSubmittingTextTest {
                        ProgressView()
                    } else {
                        Label("发送测试", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmittingTextTest || textTestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if textTestResponse.isEmpty == false {
                    if let imageURL = detectedImageURL(from: textTestResponse) {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 160)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.2))
                                    )
                            case .failure:
                                Text("图像加载失败：\(imageURL.absoluteString)")
                                    .font(.footnote)
                            case .empty:
                                ProgressView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        ScrollView {
                            Text(textTestResponse)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 100, maxHeight: 180)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var relaySection: some View {
        Section("API 中转服务（可选）") {
            Toggle("启用中转", isOn: $relayEnabled)
            TextField("服务名称", text: $relayProviderName)
            TextField("API 地址", text: $relayBaseURL)
            SecureField("中转密钥", text: $relayAPIKey)

            if relayModels.isEmpty == false {
                Picker("文本模型", selection: $relaySelectedTextModel) {
                    ForEach(relayModels, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
                Picker("图像模型", selection: $relaySelectedImageModel) {
                    ForEach(relayModels, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
            }
            HStack {
                Button {
                    Task { await fetchRelayModels() }
                } label: {
                    if isSyncingRelayModels {
                        ProgressView()
                    } else {
                        Label("同步模型列表", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)

                Button("测试连接") {
                    Task { await testConnection() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTestingConnection)
            }
        }
    }

    @ViewBuilder
    private var auditSection: some View {
        Section("审计日志") {
            Button {
                exportAuditLog()
            } label: {
                if isExportingAudit {
                    ProgressView()
                } else {
                    Label("导出 JSON", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(isExportingAudit)
        }
    }

    private func loadState() {
        selectedTextModel = configuration.textModel
        selectedImageModel = configuration.imageModel
        updateKeyStatus()

        relayEnabled = configuration.relayEnabled
        relayProviderName = configuration.relayProviderName
        relayBaseURL = configuration.relayAPIBase
        relayAPIKey = configuration.relayAPIKey
        relayModels = configuration.relayAvailableModels
        relaySelectedTextModel = configuration.relaySelectedTextModel ?? ""
        relaySelectedImageModel = configuration.relaySelectedImageModel ?? ""
    }

    private func updateKeyStatus() {
        do {
            let key = try dependencies.credentialsStore.fetchAPIKey()
            storedKeyPlaintext = key
            keyStatus = "已保存（长度 \(key.count)）"
        } catch CredentialsStoreError.notFound {
            keyStatus = "未保存"
            storedKeyPlaintext = nil
        } catch {
            keyStatus = "读取失败：\(error.localizedDescription)"
            storedKeyPlaintext = nil
        }
    }

    private func saveKey() {
        guard apiKeyInput.isEmpty == false else {
            feedbackColor = .orange
            feedbackMessage = "请输入密钥再保存。"
            return
        }

        do {
            try dependencies.credentialsStore.save(apiKey: apiKeyInput)
            storedKeyPlaintext = apiKeyInput
            apiKeyInput = ""
            updateKeyStatus()
            feedbackColor = .green
            feedbackMessage = "密钥已保存。"
        } catch {
            feedbackColor = .red
            feedbackMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func clearKey() {
        do {
            try dependencies.credentialsStore.clear()
            updateKeyStatus()
            revealStoredKey = false
            feedbackColor = .green
            feedbackMessage = "密钥已清除。"
        } catch {
            feedbackColor = .red
            feedbackMessage = "清除失败：\(error.localizedDescription)"
        }
    }

    private func testConnection() async {
        isTestingConnection = true
        feedbackMessage = "正在测试连接..."
        feedbackColor = .secondary

        do {
            let request = AIActionRequest(
                kind: .diagnostics,
                action: .aiConsole,
                channel: .text,
                fields: [
                    "theme": "连接测试",
                    "mood": "系统检测",
                    "camera": "预设"
                ],
                assetReferences: [],
                module: .aiConsole,
                context: .general,
                contextSummaryOverride: "设置 · 连接测试",
                origin: "设置诊断"
            )
            let result = try await actionCenter.perform(request)
            let snippet = (result.text ?? result.metadata.prompt).prefix(60)
            feedbackColor = .green
            feedbackMessage = "连接成功，返回内容片段：\(snippet)…"
        } catch {
            feedbackColor = .red
            feedbackMessage = "测试失败：\(error.localizedDescription)"
        }

        isTestingConnection = false
    }

    private func submitTextTest() {
        guard textTestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        isSubmittingTextTest = true
        textTestResponse = ""

        Task {
            defer { isSubmittingTextTest = false }
            do {
                let request = AIActionRequest(
                    kind: .diagnostics,
                    action: .aiConsole,
                    channel: .text,
                    fields: ["prompt": textTestInput],
                    assetReferences: [],
                    module: .aiConsole,
                    context: .general,
                    contextSummaryOverride: "设置 · 文本测试",
                    origin: "设置诊断"
                )
                let result = try await actionCenter.perform(request)
                textTestResponse = result.text ?? result.metadata.prompt
            } catch {
                textTestResponse = "请求失败：\(error.localizedDescription)"
            }
        }
    }

    private func submitImageTest() {
        isSubmittingImageTest = true
        imageTestStatus = "正在生成连接测试图像…"
        imageTestImage = nil

        let request = AIActionRequest(
            kind: .diagnostics,
            action: .generateScene,
            channel: .image,
            fields: ["prompt": "连接测试：生成一张简单的静物照片，强调光影"],
            assetReferences: [],
            module: nil,
            context: nil,
            contextSummaryOverride: "设置 · 图像测试",
            origin: "设置诊断"
        )

        Task {
            defer { isSubmittingImageTest = false }
            do {
                let result = try await actionCenter.perform(request)
                await MainActor.run {
                    imageTestStatus = "生成成功 · \(result.metadata.model) · \(result.route.displayName)"
                    imageTestImage = result.image
                    if result.image == nil {
                        imageTestStatus = "生成成功但未返回图像数据。"
                    }
                }
            } catch {
                await MainActor.run {
                    imageTestStatus = "图像测试失败：\(error.localizedDescription)"
                    imageTestImage = nil
                }
            }
        }
    }

    private func detectedImageURL(from text: String) -> URL? {
        let pattern = #"!\[[^\]]*\]\((.*?)\)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let urlRange = Range(match.range(at: 1), in: text) {
                return URL(string: String(text[urlRange]))
            }
        }
        return nil
    }

    private func fetchRelayModels() async {
        guard relayEnabled else { return }
        let base = relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = relayAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard base.isEmpty == false, key.isEmpty == false else {
            feedbackColor = .orange
            feedbackMessage = "请先填写 API 地址和中转密钥。"
            return
        }
        isSyncingRelayModels = true
        defer { isSyncingRelayModels = false }

        let endpoint = RelaySettingsSnapshot.normalize(baseURL: base) + "/v1/models"
        guard let url = URL(string: endpoint) else {
            feedbackColor = .red
            feedbackMessage = "API 地址无效。"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let modelList = try JSONDecoder().decode(RelayModelList.self, from: data)
            let ids = modelList.data.map { $0.id }
            relayModels = ids
            if relaySelectedTextModel.isEmpty {
                relaySelectedTextModel = ids.first ?? ""
            }
            if relaySelectedImageModel.isEmpty {
                relaySelectedImageModel = ids.first ?? ""
            }
            configuration.updateRelayModels(ids)
            configuration.updateRelaySelectedTextModel(relaySelectedTextModel.isEmpty ? nil : relaySelectedTextModel)
            configuration.updateRelaySelectedImageModel(relaySelectedImageModel.isEmpty ? nil : relaySelectedImageModel)
            feedbackColor = .green
            feedbackMessage = "已同步 \(ids.count) 个模型。"
        } catch {
            feedbackColor = .red
            feedbackMessage = "同步失败：\(error.localizedDescription)"
        }
    }

    private var isKeyActive: Bool {
        guard let key = storedKeyPlaintext else { return false }
        return key.isEmpty == false
    }

    private func exportAuditLog() {
        isExportingAudit = true
        Task {
            let entries = await dependencies.auditRepository.loadAllEntries()
            guard entries.isEmpty == false else {
                await MainActor.run {
                    feedbackColor = .orange
                    feedbackMessage = "暂无审计记录可导出。"
                    isExportingAudit = false
                }
                return
            }
            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "MultiGen-Audit-\(Date.now.formatted(date: .numeric, time: .shortened)).json"
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        encoder.dateEncodingStrategy = .iso8601
                        let data = try encoder.encode(entries)
                        try data.write(to: url, options: .atomic)
                        feedbackColor = .green
                        feedbackMessage = "审计日志已导出：\(url.lastPathComponent)"
                    } catch {
                        feedbackColor = .red
                        feedbackMessage = "导出失败：\(error.localizedDescription)"
                    }
                }
                isExportingAudit = false
            }
        }
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("关于 MultiGen")
                .font(.title2.bold())
            Text("MultiGen 是一款面向影视创作流程的 macOS 原生应用，聚焦剧本、分镜与 AIGC 工作流的统一体验。")
                .foregroundStyle(.secondary)
            Divider()
            HStack(spacing: 12) {
                Text("开发者：Codex（占位）")
                Spacer()
                Link("访问开发者主页", destination: URL(string: "https://example.com/codex")!)
                    .disabled(true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
    }
}

private struct RelayModelList: Decodable {
    struct RelayModelInfo: Decodable {
        let id: String
    }

    let data: [RelayModelInfo]
}
