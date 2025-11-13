//
//  CreateView.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import SwiftUI
import AppKit

struct CreateView: View {
    @StateObject private var store: CreateStore

    init(store: CreateStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        mainContent
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar(content: toolbarContent)
        .alert("错误", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { _ in store.errorMessage = nil }
        )) {
            Button("确定", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .padding(.top, 8)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let entry = store.selectedEntry {
                Text("当前镜头：第 \(entry.fields.shotNumber) 镜 · \(entry.fields.shotScale.isEmpty ? "未设置景别" : entry.fields.shotScale)")
                    .font(.title3.bold())
            } else {
                Text("请从左侧选择一个镜头开始创作。")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }

            tagSection(title: "角色创作", description: CreateFocusGroup.character.description, operations: store.characterOperations)
            tagSection(title: "场景创作", description: CreateFocusGroup.scene.description, operations: store.sceneOperations)
            tagSection(title: "溶图创作", description: CreateFocusGroup.blend.description, operations: store.blendOperations)

            if store.selectedOperation != nil {
                fieldSection
                promptPreviewSection
            }

            generationSection

            resultsSection
        }
        .padding(.trailing, 24)
    }

    private func tagSection(title: String, description: String, operations: [CreateOperation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(operations) { operation in
                        OperationChip(
                            operation: operation,
                            isSelected: store.selectedOperation == operation
                        ) {
                            store.selectOperation(operation)
                        }
                    }
                }
            }
        }
    }

    private var fieldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let template = store.selectedOperation?.template {
                ForEach(template.fields, id: \.id) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.title)
                            .font(.subheadline.bold())
                        if field.kind == .options {
                            Picker(field.title, selection: Binding(
                                get: { store.fieldValues[field.id] ?? "" },
                                set: { store.updateField(id: field.id, value: $0) }
                            )) {
                                ForEach(field.options, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                            .labelsHidden()
                        } else {
                            TextField(field.placeholder, text: Binding(
                                get: { store.fieldValues[field.id] ?? "" },
                                set: { store.updateField(id: field.id, value: $0) }
                            ), axis: field.kind == .text ? .vertical : .horizontal)
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }

            if store.selectedOperation?.group == .character || store.selectedOperation?.group == .scene {
                VStack(alignment: .leading, spacing: 8) {
                    Text("图生图设置")
                        .font(.headline)
                    baseImageControls
                    referenceImageControls
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 8)
    }

    private var promptPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("提示词预览")
                .font(.headline)
            ScrollView {
                Text(store.promptPreview)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 140)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private var baseImageControls: some View {
        HStack(spacing: 12) {
            Menu {
                if store.results.contains(where: { $0.imageData != nil }) {
                    Section("从结果选择") {
                        ForEach(store.results.filter { $0.imageData != nil }) { result in
                            Button(result.operation.title) {
                                store.useResultAsBaseImage(result.id)
                            }
                        }
                    }
                }
                Button("从文件导入") {
                    store.importBaseImageFromFile()
                }
                if store.baseImageSelection != nil || store.baseImageURL != nil {
                    Button("清除 Base Image", role: .destructive) {
                        store.clearBaseImage()
                    }
                }
            } label: {
                Label("Base Image：\(store.baseImageDescription)", systemImage: "photo")
            }

            Slider(value: $store.imageScale, in: 0.5...2.0) {
                Text("尺寸倍率")
            }
            Text(String(format: "%.2f×", store.imageScale))
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: $store.guidanceStrength, in: 0.2...1.0) {
                Text("引导强度")
            }
            Text(String(format: "%.2f", store.guidanceStrength))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var referenceImageControls: some View {
        let hasReference = store.characterReferenceImage != nil
        return VStack(alignment: .leading, spacing: 8) {
            if store.selectedOperation?.group == .blend {
                HStack(spacing: 12) {
                    Button {
                        store.characterReferenceImage = store.results.first(where: { $0.imageData != nil })?.imageData
                    } label: {
                        Label("角色参考图", systemImage: "person.crop.square")
                    }
                    Button {
                        store.sceneReferenceImage = store.results.dropFirst().first(where: { $0.imageData != nil })?.imageData
                    } label: {
                        Label("场景参考图", systemImage: "square.grid.3x3")
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        store.characterReferenceImage = store.results.first(where: { $0.imageData != nil })?.imageData
                    } label: {
                        Label("引用上一轮图像", systemImage: "arrow.shape.turn.up.left")
                    }
                    Button {
                        store.characterReferenceImage = nil
                    } label: {
                        Label("清除引用图", systemImage: "xmark.circle")
                    }
                    .disabled(!hasReference)
                }
            }
        }
    }

    private var generationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI 生成")
                .font(.headline)
            HStack(spacing: 12) {
                Button {
                    store.generateText()
                } label: {
                    if store.isGeneratingText {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Label("生成文本", systemImage: "text.append")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.canGenerate == false || store.isGeneratingText)

                Button {
                    store.generateImage()
                } label: {
                    if store.isGeneratingImage {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Label("生成图像", systemImage: "photo.on.rectangle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(store.canGenerate == false || store.isGeneratingImage)
                Spacer()
            }
            Text("文本模型：\(store.currentTextModelName) · 图像模型：\(store.currentImageModelName) · 线路：\(store.currentRouteDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("生成结果")
                .font(.headline)
            if store.results.isEmpty {
                Text("尚未生成内容。")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.results) { result in
                            ResultCard(
                                result: result,
                                useAsBaseImage: result.imageData == nil ? nil : { store.useResultAsBaseImage(result.id) }
                            )
                        }
                    }
                }
                .frame(minHeight: 220)
            }
        }
    }

    private var entrySelection: Binding<UUID?> {
        Binding(
            get: { store.selectedEntryID },
            set: { store.selectEntry(id: $0) }
        )
    }

    private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup {
            Picker("分镜集", selection: Binding(
                get: { store.selectedWorkspaceID },
                set: { store.selectWorkspace(id: $0) }
            )) {
                ForEach(store.workspaces) { workspace in
                    Text(workspace.episodeTitle).tag(Optional(workspace.id))
                }
            }
            .labelsHidden()
            .frame(width: 220)

            if store.availableEntries.isEmpty == false {
                Picker("镜头", selection: entrySelection) {
                    ForEach(store.availableEntries) { entry in
                        Text("镜 \(entry.fields.shotNumber)")
                            .tag(Optional(entry.id))
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
        }
    }
}

private struct OperationChip: View {
    let operation: CreateOperation
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: operation.iconName)
                    Text(operation.title)
                        .font(.subheadline.bold())
                }
                Text(operation.subtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 160, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

private struct ResultCard: View {
    let result: CreateResult
    let useAsBaseImage: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.operation.title)
                    .font(.headline)
                Spacer()
                Text(result.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(result.channel == .text ? "文本" : "图像") · \(result.model)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let data = result.imageData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .cornerRadius(12)
                if let useAsBaseImage {
                    Button("设为 Base Image") {
                        useAsBaseImage()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Text(result.promptPreview)
                    .font(.body)
                    .lineLimit(6)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct CreateScreen: View {
    @StateObject private var store: CreateStore

    init(builder: @escaping () -> CreateStore) {
        _store = StateObject(wrappedValue: builder())
    }

    var body: some View {
        CreateView(store: store)
    }
}
