//
//  SceneComposerView.swift
//  MultiGen
//
//  Created by Codex on 2025/02/15.
//

import SwiftUI
import UniformTypeIdentifiers

struct SceneComposerView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var configuration: AppConfiguration
    @StateObject private var store = SceneComposerStore()
    @State private var isImportingAsset = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mainBody
        }
        .background(Color(NSColor.windowBackgroundColor))
        .fileImporter(isPresented: $isImportingAsset, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    store.attachAsset(url: url)
                }
            case .failure:
                break
            }
        }
        .onAppear {
            store.refreshKeyAvailability(credentialsStore: dependencies.credentialsStore)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SceneComposer · 场景编排控制台")
                    .font(.system(.title, weight: .semibold))
                Text("使用模板化字段快速生成 Gemini 提示，素材抽屉/Inspector 与结果区域保持联动。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("文本模型：\(configuration.textModel.displayName) · \(dependencies.currentTextRoute().displayName)", systemImage: "text.book.closed")
                .font(.footnote)
            Label("图像模型：\(configuration.imageModel.displayName) · \(dependencies.currentImageRoute().displayName)", systemImage: "photo.on.rectangle")
                .font(.footnote)
            Label("API Key：\(store.hasAPIKey ? "已配置" : "未配置")", systemImage: store.hasAPIKey ? "checkmark.shield" : "exclamationmark.shield")
                .foregroundStyle(store.hasAPIKey ? .green : .orange)
                .font(.footnote.weight(.semibold))
            Button {
                store.refreshKeyAvailability(credentialsStore: dependencies.credentialsStore)
            } label: {
                Label("刷新状态", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var mainBody: some View {
        HStack(alignment: .top, spacing: 20) {
            assetDrawer
            Divider()
            VStack(spacing: 16) {
                resultCanvas
                Divider()
                statusBanner
            }
            Divider()
            inspectorPanel
        }
        .padding(20)
    }

    private var assetDrawer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("素材抽屉", systemImage: "photo.stack")
                    .font(.headline)
                Spacer()
                Button {
                    isImportingAsset = true
                } label: {
                    Label("导入图片", systemImage: "square.and.arrow.down")
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.assets) { asset in
                        SceneComposerAssetRow(
                            asset: asset,
                            onRemove: { store.removeAsset(id: asset.id) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 240, alignment: .topLeading)
    }

    private var resultCanvas: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("生成结果", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button(role: .none) {
                    Task {
                        await store.performGenerate(using: dependencies)
                    }
                } label: {
                    if store.isGenerating {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Label("生成", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isGenerating || store.hasAPIKey == false)
                .help(store.hasAPIKey ? "根据当前 Inspector 字段发送请求" : "请先配置 API Key")
            }
            if store.results.isEmpty {
                resultPlaceholder
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.results) { result in
                            SceneComposerResultCard(result: result)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var resultPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("尚未生成结果")
                .font(.headline)
            Text("填写右侧字段并点击“生成”即可在这里看到 Gemini 返回的结构化提示。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Inspector", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Picker("动作", selection: Binding(get: {
                    store.selectedAction
                }, set: { action in
                    store.select(action: action)
                })) {
                    ForEach(store.actions) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .pickerStyle(.menu)
            }
            if let template = store.activeTemplate {
                Text(template.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Form {
                    ForEach(template.fields) { field in
                        SceneComposerFieldView(field: field, value: store.binding(for: field))
                    }
                }
                .formStyle(.grouped)
            } else {
                Text("未找到模板")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(width: 300, alignment: .topLeading)
    }

    private var statusBanner: some View {
        Group {
            if let error = store.errorMessage {
                SceneComposerStatusBanner(
                    text: error,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange,
                    onDismiss: store.clearStatusMessages
                )
            } else if let status = store.statusMessage {
                SceneComposerStatusBanner(
                    text: status,
                    systemImage: "checkmark.seal",
                    tint: .green,
                    onDismiss: store.clearStatusMessages
                )
            } else {
                EmptyView()
            }
        }
    }
}

private struct SceneComposerAssetRow: View {
    let asset: SceneComposerStore.ComposerAsset
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: asset.kind == .placeholder ? "photo" : "photo.fill.on.rectangle.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(.subheadline)
                if let url = asset.url {
                    Text(url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("占位素材")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct SceneComposerResultCard: View {
    let result: SceneComposerStore.ComposerResult
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.action.displayName)
                    .font(.headline)
                Spacer()
                Text(result.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(result.summary)
                .font(.subheadline)
            Text(result.responseSnippet)
                .font(.body)
                .lineLimit(isExpanded ? nil : 3)
            if isExpanded {
                Divider()
                Text(result.promptText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            if result.assets.isEmpty == false {
                HStack {
                    Image(systemName: "paperclip")
                    Text(result.assets.map(\.displayToken).joined(separator: "，"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button(isExpanded ? "收起详情" : "展开详情") {
                withAnimation {
                    isExpanded.toggle()
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct SceneComposerFieldView: View {
    let field: PromptField
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            switch field.kind {
            case .text, .assetReference:
                TextField(field.placeholder, text: $value, axis: .vertical)
            case .options:
                Picker(field.title, selection: $value) {
                    ForEach(field.options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
            case .numeric:
                TextField(field.placeholder, text: $value)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct SceneComposerStatusBanner: View {
    let text: String
    let systemImage: String
    let tint: Color
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(text)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .font(.footnote)
        .foregroundStyle(tint)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}
