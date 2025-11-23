import SwiftUI
import AppKit

private enum SettingsSection: Hashable, CaseIterable, Identifiable {
    case general
    case flow
    case collaboration
    case agent
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "通用"
        case .flow: return "流程"
        case .collaboration: return "协同"
        case .agent: return "代理"
        case .about: return "关于"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .flow: return "arrow.triangle.branch"
        case .collaboration: return "sparkles"
        case .agent: return "person.2"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SettingsSection = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabView(selection: $selection) {
                GeneralSettingsTab()
                    .tabItem {
                        Label(SettingsSection.general.title, systemImage: SettingsSection.general.icon)
                    }
                    .tag(SettingsSection.general)
                FlowSettingsTab()
                    .tabItem {
                        Label(SettingsSection.flow.title, systemImage: SettingsSection.flow.icon)
                    }
                    .tag(SettingsSection.flow)
                CollaborationSettingsTab()
                    .tabItem {
                        Label(SettingsSection.collaboration.title, systemImage: SettingsSection.collaboration.icon)
                    }
                    .tag(SettingsSection.collaboration)
                AgentSettingsTab()
                    .tabItem {
                        Label(SettingsSection.agent.title, systemImage: SettingsSection.agent.icon)
                    }
                    .tag(SettingsSection.agent)
                AboutSettingsTab()
                    .tabItem {
                        Label(SettingsSection.about.title, systemImage: SettingsSection.about.icon)
                    }
                    .tag(SettingsSection.about)
            }

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
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }
}

private struct FlowSettingsTab: View {
    var body: some View {
        Form {
            Section("流程") {
                Text("流程配置即将上线，敬请期待。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }
}

private struct AgentSettingsTab: View {
    var body: some View {
        Form {
            Section("代理") {
                Text("代理能力配置即将上线。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }
}

private struct CollaborationSettingsTab: View {
    enum TestChannel: String, CaseIterable, Identifiable {
        case text
        case image
        case video

        var id: String { rawValue }

        var title: String {
            switch self {
            case .text: return "文本"
            case .image: return "图像"
            case .video: return "视频"
            }
        }

        var promptPlaceholder: String {
            switch self {
            case .text: return "请回复 OK"
            case .image: return "一张简洁的测试图片"
            case .video: return "一个 2 秒的简短测试视频"
            }
        }
    }

    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var configuration: AppConfiguration

    @State private var providerName = ""
    @State private var relayBaseURL = ""
    @State private var relayAPIKey = ""
    @State private var relayModels: [String] = []
    @State private var relaySelectedTextModel: String = ""
    @State private var relaySelectedImageModel: String = ""
    @State private var relaySelectedVideoModel: String = ""
    @State private var relaySelectedMultimodalModel: String = ""
    @State private var isSyncingRelayModels = false
    @State private var syncStatus: String?

    @State private var testChannel: TestChannel = .text
    @State private var textTestInput: String = TestChannel.text.promptPlaceholder
    @State private var imageTestInput: String = TestChannel.image.promptPlaceholder
    @State private var videoTestInput: String = TestChannel.video.promptPlaceholder
    @State private var testStatus: String?
    @State private var testResponse: String = ""
    @State private var testImage: NSImage?
    @State private var testVideoURL: URL?
    @State private var isTesting = false

    @State private var isExportingAudit = false

    private var aiMemoryBinding: Binding<Bool> {
        Binding(
            get: { configuration.aiMemoryEnabled },
            set: { configuration.updateAIMemoryEnabled($0) }
        )
    }

    var body: some View {
        Form {
            providerSection
            modelSection
            aiMemorySection
            availabilityTestSection
            auditSection
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
        .onAppear(perform: loadState)
        .onChange(of: providerName) { _, newValue in
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
        .onChange(of: relaySelectedVideoModel) { _, newValue in
            configuration.updateRelaySelectedVideoModel(newValue.isEmpty ? nil : newValue)
        }
        .onChange(of: relaySelectedMultimodalModel) { _, newValue in
            configuration.updateRelaySelectedMultimodalModel(newValue.isEmpty ? nil : newValue)
        }
    }

    @ViewBuilder
    private var providerSection: some View {
        Section("提供商") {
            TextField("服务名称", text: $providerName)
            TextField("API 地址", text: $relayBaseURL)
            SecureField("密钥", text: $relayAPIKey)

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
            .disabled(isSyncingRelayModels)

            if let syncStatus {
                Text(syncStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        Section("模型") {
            if relayModels.isEmpty {
                Text("请先同步模型列表。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Picker("文本模型", selection: $relaySelectedTextModel) {
                ForEach(relayModels, id: \.self) { id in
                    Text(id).tag(id)
                }
            }
            .disabled(relayModels.isEmpty)

            Picker("多模态模型", selection: $relaySelectedMultimodalModel) {
                ForEach(relayModels, id: \.self) { id in
                    Text(id).tag(id)
                }
            }
            .disabled(relayModels.isEmpty)

            Picker("图像模型", selection: $relaySelectedImageModel) {
                ForEach(relayModels, id: \.self) { id in
                    Text(id).tag(id)
                }
            }
            .disabled(relayModels.isEmpty)

            Picker("视频模型", selection: $relaySelectedVideoModel) {
                ForEach(relayModels, id: \.self) { id in
                    Text(id).tag(id)
                }
            }
            .disabled(relayModels.isEmpty)
        }
    }

    @ViewBuilder
    private var aiMemorySection: some View {
        Section("AI 记忆") {
            Toggle("启用 AI 记忆能力", isOn: aiMemoryBinding)
            Text("开启后，我们会在单次对话中自动注入近期历史上下文。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var availabilityTestSection: some View {
        Section("可用性测试") {
            Picker("测试类型", selection: $testChannel) {
                ForEach(TestChannel.allCases) { channel in
                    Text(channel.title).tag(channel)
                }
            }
            .pickerStyle(.segmented)

            TextField("测试提示词", text: currentPromptBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

            Button {
                Task { await runAvailabilityTest() }
            } label: {
                if isTesting {
                    ProgressView()
                } else {
                    Label("开始测试", systemImage: "paperplane.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTesting || relayModels.isEmpty)

            if let testStatus {
                Text(testStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            switch testChannel {
            case .text:
                if testResponse.isEmpty == false {
                    ScrollView {
                        Text(testResponse)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 100, maxHeight: 180)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )
                }
            case .image:
                if let preview = testImage {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                }
            case .video:
                if let url = testVideoURL {
                    Text(url.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
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

    // MARK: - Helpers

    private var currentPromptBinding: Binding<String> {
        Binding<String>(
            get: {
                switch testChannel {
                case .text: return textTestInput
                case .image: return imageTestInput
                case .video: return videoTestInput
                }
            },
            set: { newValue in
                switch testChannel {
                case .text: textTestInput = newValue
                case .image: imageTestInput = newValue
                case .video: videoTestInput = newValue
                }
            }
        )
    }

    private func loadState() {
        providerName = configuration.relayProviderName
        relayBaseURL = configuration.relayAPIBase
        relayAPIKey = configuration.relayAPIKey
        relayModels = configuration.relayAvailableModels
        relaySelectedTextModel = configuration.relaySelectedTextModel ?? ""
        relaySelectedImageModel = configuration.relaySelectedImageModel ?? ""
        relaySelectedVideoModel = configuration.relaySelectedVideoModel ?? ""
        relaySelectedMultimodalModel = configuration.relaySelectedMultimodalModel ?? ""
    }

    // MARK: - Actions

    private func fetchRelayModels() async {
        isSyncingRelayModels = true
        syncStatus = nil
        defer { isSyncingRelayModels = false }

        let base = relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = relayAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard base.isEmpty == false, key.isEmpty == false else {
            syncStatus = "请先填写 API 地址与密钥。"
            return
        }

        let modelsEndpoint: String
        if base.hasSuffix("/models") {
            modelsEndpoint = base
        } else if base.hasSuffix("/") {
            modelsEndpoint = base + "models"
        } else {
            modelsEndpoint = base + "/models"
        }

        guard let url = URL(string: modelsEndpoint) else {
            syncStatus = "API 地址格式不正确。"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                syncStatus = "无效响应。"
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                syncStatus = "HTTP \(http.statusCode)：\(body)"
                return
            }

            let models = try parseModelIDs(from: data)
            guard models.isEmpty == false else {
                syncStatus = "未获取到模型列表。"
                return
            }

            relayModels = models
            configuration.updateRelayModels(models)

            if relaySelectedTextModel.isEmpty { relaySelectedTextModel = models.first ?? "" }
            if relaySelectedImageModel.isEmpty { relaySelectedImageModel = models.first ?? "" }
            if relaySelectedVideoModel.isEmpty { relaySelectedVideoModel = models.first ?? "" }
            if relaySelectedMultimodalModel.isEmpty { relaySelectedMultimodalModel = models.first ?? "" }
            syncStatus = "同步完成，共 \(models.count) 个模型。"
        } catch {
            syncStatus = "同步失败：\(error.localizedDescription)"
        }
    }

    private func parseModelIDs(from data: Data) throws -> [String] {
        struct ModelListResponse: Decodable {
            struct ModelInfo: Decodable {
                let id: String?
                let name: String?
            }
            let data: [ModelInfo]?
            let models: [ModelInfo]?
        }

        if let decoded = try? JSONDecoder().decode(ModelListResponse.self, from: data) {
            let ids = (decoded.data ?? []) + (decoded.models ?? [])
            let names = ids.compactMap { $0.id ?? $0.name }
            return Array(Set(names)).sorted()
        }

        if let array = try? JSONDecoder().decode([String].self, from: data) {
            return array.sorted()
        }

        if let single = String(data: data, encoding: .utf8) {
            let ids = single
                .split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .map(String.init)
                .filter { $0.isEmpty == false }
            if ids.isEmpty == false { return ids }
        }

        return []
    }

    private func runAvailabilityTest() async {
        isTesting = true
        testStatus = nil
        testResponse = ""
        testImage = nil
        testVideoURL = nil
        defer { isTesting = false }

        let prompt = currentPromptBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.isEmpty == false else {
            testStatus = "请输入测试提示词。"
            return
        }

        switch testChannel {
        case .text:
            guard relaySelectedTextModel.isEmpty == false else {
                testStatus = "请先选择文本模型。"
                return
            }
            await submitTextTest(prompt: prompt)
        case .image:
            guard relaySelectedImageModel.isEmpty == false else {
                testStatus = "请先选择图像模型。"
                return
            }
            await submitImageTest(prompt: prompt)
        case .video:
            guard relaySelectedVideoModel.isEmpty == false else {
                testStatus = "请先选择视频模型。"
                return
            }
            await submitVideoTest(prompt: prompt)
        }
    }

    private func submitTextTest(prompt: String) async {
        let request = AIActionRequest(
            kind: .diagnostics,
            action: .aiConsole,
            channel: .text,
            fields: ["prompt": prompt],
            assetReferences: [],
            module: .aiConsole,
            context: .general,
            contextSummaryOverride: "设置 · 文本可用性",
            origin: "设置诊断"
        )

        do {
            let stream = actionCenter.stream(request)
            var collected = ""
            for try await event in stream {
                switch event {
                case .partial(let delta):
                    collected += delta
                    testResponse = collected
                case .completed(let result):
                    testResponse = result.text ?? collected
                }
            }
            testStatus = "文本测试完成。"
        } catch {
            testStatus = "失败：\(error.localizedDescription)"
        }
    }

    private func submitImageTest(prompt: String) async {
        let request = AIActionRequest(
            kind: .diagnostics,
            action: .generateScene,
            channel: .image,
            fields: ["prompt": prompt],
            assetReferences: [],
            module: .aiConsole,
            context: .general,
            contextSummaryOverride: "设置 · 图像可用性",
            origin: "设置诊断"
        )

        do {
            let result = try await actionCenter.perform(request)
            if let image = result.image {
                testImage = image
                testStatus = "图像测试成功 · \(result.metadata.model)"
            } else {
                testStatus = "返回中未包含图像。"
            }
        } catch {
            testStatus = "失败：\(error.localizedDescription)"
        }
    }

    private func submitVideoTest(prompt: String) async {
        let request = AIActionRequest(
            kind: .diagnostics,
            action: .generateScene,
            channel: .video,
            fields: ["prompt": prompt],
            assetReferences: [],
            module: .aiConsole,
            context: .general,
            contextSummaryOverride: "设置 · 视频可用性",
            origin: "设置诊断"
        )

        do {
            let result = try await actionCenter.perform(request)
            if let url = result.videoURL {
                testVideoURL = url
                testStatus = "视频测试成功。"
            } else {
                testStatus = "未返回视频 URL。"
            }
        } catch {
            testStatus = "失败：\(error.localizedDescription)"
        }
    }

    private func exportAuditLog() {
        isExportingAudit = true
        testStatus = "审计文件位于 Application Support/MultiGen/audit-log.json"
        isExportingAudit = false
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        Form {
            Section("关于") {
                Text("MultiGen — 智能协同创作工具（单一中转线路版）")
                Text("当前版本仅使用 OpenAI 样式 API 中转，支持文本/图像/视频模型。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }
}
