import SwiftUI

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
                ForEach(AgentData.agents) { agent in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(agent.name)
                            .font(.headline)
                        Text(agent.role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("对应模块：\(agent.module)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if agent.id != AgentData.agents.last?.id {
                        Divider()
                    }
                }
            }
            Section("技能（工具）") {
                ForEach(AgentData.skills) { skill in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.name)
                            .font(.headline)
                        Text(skill.scope)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("适用代理：\(skill.agents)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if skill.id != AgentData.skills.last?.id {
                        Divider()
                    }
                }
                Text("以上为前端占位说明，后续扩展时可在此增加配置项。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }
}

private enum AgentData {
    struct Agent: Identifiable {
        let id = UUID()
        let name: String
        let role: String
        let module: String
    }

    struct Skill: Identifiable {
        let id = UUID()
        let name: String
        let scope: String
        let agents: String
    }

    static let agents: [Agent] = [
        .init(name: "创意师", role: "主页聊天 · 灵感/对话建议", module: "主页模块"),
        .init(name: "剧作师", role: "剧本助手 · 按集润色/总结", module: "剧本模块"),
        .init(name: "分镜师", role: "分镜助手 · 场景分镜生成", module: "分镜模块"),
        .init(name: "指令师", role: "提示词助手 · 角色/场景提示词生成", module: "角色/场景模块")
    ]

    static let skills: [Skill] = [
        .init(name: "项目总结", scope: "生成项目简介/标签/人物/场景", agents: "剧作师"),
        .init(name: "分镜生成", scope: "整场景镜头拆解并写入分镜板", agents: "分镜师"),
        .init(name: "提示词生成", scope: "角色/场景文生图提示词", agents: "指令师"),
        .init(name: "通用协作", scope: "开放式对话/创意建议", agents: "创意师"),
        .init(name: "上下文工具（规划中）", scope: "更精细的上下文抽取/检索", agents: "创意师、剧作师、分镜师、指令师"),
        .init(name: "内容优化（规划中）", scope: "剧情、文案、提示词的质量优化", agents: "剧作师、指令师")
    ]
}

private struct CollaborationSettingsTab: View {
    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var configuration: AppConfiguration

    @State private var providerName = ""
    @State private var relayBaseURL = ""
    @State private var relayAPIKey = ""
    @State private var relayModels: [String] = []
    @State private var relaySelectedTextModel: String = ""
    @State private var isSyncingRelayModels = false
    @State private var syncStatus: String?

    @State private var textTestInput: String = "请回复 OK"
    @State private var testStatus: String?
    @State private var testResponse: String = ""
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
            TextField("测试提示词", text: $textTestInput, axis: .vertical)
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

    private func loadState() {
        providerName = configuration.relayProviderName
        relayBaseURL = configuration.relayAPIBase
        relayAPIKey = configuration.relayAPIKey
        relayModels = configuration.relayAvailableModels
        relaySelectedTextModel = configuration.relaySelectedTextModel ?? ""
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
        defer { isTesting = false }

        let prompt = textTestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.isEmpty == false else {
            testStatus = "请输入测试提示词。"
            return
        }

        guard relaySelectedTextModel.isEmpty == false else {
            testStatus = "请先选择文本模型。"
            return
        }
        await submitTextTest(prompt: prompt)
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
                Text("当前版本仅使用 OpenAI 样式 API 中转，聚焦文本模型。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }
}
