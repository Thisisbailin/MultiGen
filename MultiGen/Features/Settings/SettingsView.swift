//
//  SettingsView.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var configuration: AppConfiguration
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput: String = ""
    @State private var keyStatus: String = "未检测"
    @State private var selectedTextModel: GeminiModel = .defaultTextModel
    @State private var selectedImageModel: GeminiModel = .defaultImageModel
    @State private var useMock: Bool = true
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
    @State private var relaySelectedModel: String = ""
    @State private var isSyncingRelayModels = false

    @State private var textTestInput: String = ""
    @State private var textTestResponse: String = ""
    @State private var isSubmittingTextTest = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Gemini 设置")
                .font(.system(.largeTitle, weight: .semibold))
            Text("配置官方线路或启用 API 中转服务，并在下方快速验证文本模型。")
                .foregroundStyle(.secondary)

            Form {
                Section("模型与模式") {
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
                    Toggle("使用 Mock 模式（无网/调试）", isOn: $useMock)
                }

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
                            Label("密钥已激活", systemImage: "checkmark.seal.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }

                    if revealStoredKey, let key = storedKeyPlaintext {
                        Text(key)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    HStack {
                        Button("保存 Key") { saveKey() }
                        Button("清除 Key") { clearKey() }
                        Button(revealStoredKey ? "隐藏已保存密钥" : "查看已保存密钥") {
                            revealStoredKey.toggle()
                        }
                        .disabled(storedKeyPlaintext == nil)
                        Spacer()
                        Button("测试连接") {
                            Task { await testConnection() }
                        }
                        .disabled(isTestingConnection)
                    }
                }

                Section("API 中转服务") {
                    Toggle("启用 API 中转服务", isOn: $relayEnabled)
                    TextField("中转商名称", text: $relayProviderName)
                        .disabled(!relayEnabled)
                    TextField("API 地址", text: $relayBaseURL)
                        .disabled(!relayEnabled)
                    SecureField("中转密钥", text: $relayAPIKey)
                        .disabled(!relayEnabled)
                    HStack {
                        Button {
                            Task { await fetchRelayModels() }
                        } label: {
                            if isSyncingRelayModels {
                                ProgressView()
                            } else {
                                Label("同步模型", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(!relayEnabled || relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || relayAPIKey.isEmpty || isSyncingRelayModels)

                        if !relayModels.isEmpty {
                            Picker("中转模型", selection: $relaySelectedModel) {
                                ForEach(relayModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                        }
                    }
                }

                Section("文本模型调试") {
                    HStack {
                        TextField("输入测试指令", text: $textTestInput)
                        Button {
                            submitTextTest()
                        } label: {
                            if isSubmittingTextTest {
                                ProgressView()
                            } else {
                                Label("发送", systemImage: "paperplane")
                            }
                        }
                        .disabled(isSubmittingTextTest || textTestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if textTestResponse.isEmpty == false {
                        ScrollView {
                            Text(textTestResponse)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                    }
                }
            }
            .formStyle(.grouped)

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.subheadline)
                    .foregroundStyle(feedbackColor)
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .onAppear(perform: loadState)
        .onChange(of: selectedTextModel) { configuration.updateTextModel($0) }
        .onChange(of: selectedImageModel) { configuration.updateImageModel($0) }
        .onChange(of: useMock) { configuration.updateUseMock($0) }
        .onChange(of: relayEnabled) { configuration.updateRelayEnabled($0) }
        .onChange(of: relayProviderName) { configuration.updateRelayProvider(name: $0) }
        .onChange(of: relayBaseURL) { _ in
            configuration.updateRelayEndpoint(baseURL: relayBaseURL, apiKey: relayAPIKey)
        }
        .onChange(of: relayAPIKey) { _ in
            configuration.updateRelayEndpoint(baseURL: relayBaseURL, apiKey: relayAPIKey)
        }
        .onChange(of: relaySelectedModel) { newValue in
            configuration.updateRelaySelectedModel(newValue.isEmpty ? nil : newValue)
        }
    }

    private func loadState() {
        selectedTextModel = configuration.textModel
        selectedImageModel = configuration.imageModel
        useMock = configuration.useMock
        updateKeyStatus()

        relayEnabled = configuration.relayEnabled
        relayProviderName = configuration.relayProviderName
        relayBaseURL = configuration.relayAPIBase
        relayAPIKey = configuration.relayAPIKey
        relayModels = configuration.relayAvailableModels
        relaySelectedModel = configuration.relaySelectedModel ?? ""
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

        let request = SceneJobRequest(
            action: .generateScene,
            fields: [
                "theme": "连接测试",
                "mood": "系统检测",
                "camera": "预设"
            ],
            channel: .text
        )

        do {
            let result = try await dependencies.textService().submit(job: request)
            await dependencies.auditRepository.record(
                AuditLogEntry(
                    jobID: request.id,
                    action: request.action,
                    promptHash: String(result.metadata.prompt.hashValue, radix: 16),
                    assetRefs: [],
                    modelVersion: result.metadata.model
                )
            )
            feedbackColor = .green
            feedbackMessage = "连接成功，返回内容片段：\(result.metadata.prompt.prefix(60))..."
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

        let request = SceneJobRequest(
            action: .generateScene,
            fields: ["prompt": textTestInput],
            channel: .text
        )

        Task {
            defer { isSubmittingTextTest = false }
            do {
                let result = try await dependencies.textService().submit(job: request)
                textTestResponse = result.metadata.prompt
            } catch {
                textTestResponse = "请求失败：\(error.localizedDescription)"
            }
        }
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

        let endpoint = RelayTextService.normalize(baseURL: base) + "/v1/models"
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
            relaySelectedModel = ids.first ?? ""
            configuration.updateRelayModels(ids, selected: relaySelectedModel.isEmpty ? nil : relaySelectedModel)
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
}

private struct RelayModelList: Decodable {
    struct RelayModelInfo: Decodable {
        let id: String
    }

    let data: [RelayModelInfo]
}
