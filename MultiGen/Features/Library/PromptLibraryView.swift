//
//  PromptLibraryView.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import SwiftUI

struct PromptLibraryView: View {
    @EnvironmentObject private var store: PromptLibraryStore
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var navigationStore: NavigationStore
    @State private var selectedModule: PromptDocument.Module = .aiConsole
    @State private var draftContent: String = ""
    @State private var showSavedToast = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                PromptCard(title: "系统指令 · \(selectedModule.displayName)") {
                    editor
                }
                if showSavedToast {
                    Label("已保存自定义提示词", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                if selectedModule == .storyboard {
                    StoryboardPromptBlueprintView(
                        context: storyboardContext(),
                        promptText: draftContent
                    )
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loadDraft() }
        .onChange(of: selectedModule) { _, _ in loadDraft() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("指令资料库")
                .font(.largeTitle.bold())
            Text("维护各模块所使用的系统提示词模版，可依据团队风格做定制。")
                .foregroundStyle(.secondary)
            Picker("模块", selection: $selectedModule) {
                ForEach(PromptDocument.Module.allCases) { module in
                    Text(module.displayName).tag(module)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            let document = store.document(for: selectedModule)
            Text(document.module.moduleDescription)
                .font(.subheadline)
            TextEditor(text: $draftContent)
                .font(.body.monospaced())
                .padding(12)
                .frame(minHeight: 320)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2))
                )
            HStack {
                Spacer()
                Button {
                    store.updateDocument(module: selectedModule, content: draftContent)
                    showSavedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showSavedToast = false
                    }
                } label: {
                    Label("保存自定义提示词", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive) {
                    store.resetDocument(module: selectedModule)
                    loadDraft()
                } label: {
                    Label("恢复默认", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }


    private func storyboardContext() -> StoryboardBlueprintContext {
        if let episodeID = navigationStore.currentStoryboardEpisodeID {
            for project in scriptStore.projects {
                if let episode = project.episodes.first(where: { $0.id == episodeID }) {
                    return StoryboardBlueprintContext(project: project, episode: episode)
                }
            }
        }
        let fallbackProject = scriptStore.projects.first
        return StoryboardBlueprintContext(
            project: fallbackProject,
            episode: fallbackProject?.orderedEpisodes.first
        )
    }

    private func loadDraft() {
        let doc = store.document(for: selectedModule)
        draftContent = doc.content
    }
}


private struct StoryboardBlueprintContext {
    let project: ScriptProject?
    let episode: ScriptEpisode?

    var scenes: [ScriptScene] {
        guard let episode else { return [] }
        return episode.scenes.sorted { $0.order < $1.order }
    }
}

private struct StoryboardPromptBlueprintView: View {
    let context: StoryboardBlueprintContext
    let promptText: String
    @State private var showVariables = true
    @State private var showScenes = false
    @State private var showMetadata = false

    var body: some View {
        PromptCard(title: "分镜助手 · 请求构造器") {
            BlueprintSection(title: "构造顺序") {
                BlueprintBullet(text: "1. 读取系统提示词 (Prompt Library) 作为 systemPrompt")
                BlueprintBullet(text: "2. 注入项目标题 project.title 与 synopsis")
                BlueprintBullet(text: "3. 写入当前剧集 episode.displayLabel 与所有场景正文")
                BlueprintBullet(text: "4. 追加 sceneMetadata JSON (scene.id/title/summary/order)")
                BlueprintBullet(text: "5. 拼装输出约束，要求 AI 返回 {\"scenes\": [...]}")
            }
            DisclosureGroup(isExpanded: $showVariables) {
                KeyValueRow(label: "项目标题 (project.title)", value: context.project?.title ?? "未选择项目")
                KeyValueRow(label: "项目简介 (project.synopsis)", value: context.project?.synopsis.ifEmptyPlaceholder() ?? "未提供")
                KeyValueRow(label: "剧集 (episode.displayLabel)", value: context.episode?.displayLabel ?? "未选择剧集")
                KeyValueRow(label: "场景数量", value: "\(context.scenes.count)")
            } label: {
                Text("实时变量")
                    .font(.headline)
            }
            if context.scenes.isEmpty == false {
                DisclosureGroup(isExpanded: $showScenes) {
                    ForEach(context.scenes.prefix(5), id: \.id) { scene in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scene.title)
                                .font(.headline)
                            Text(scene.body.ifEmptyPlaceholder())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                    if context.scenes.count > 5 {
                        Text("… 其余 \(context.scenes.count - 5) 个场景以相同方式注入")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("场景引用（scene.title + scene.body）")
                        .font(.headline)
                }
            }
            DisclosureGroup("场景元数据 (sceneMetadataJSON) 示例", isExpanded: $showMetadata) {
                ScrollView(.horizontal) {
                    Text(sceneMetadataSample)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .background(.thinMaterial)
                        .cornerRadius(8)
                }
            }
            BlueprintSection(title: "控制台字段映射") {
                KeyValueRow(label: "systemPrompt", value: "来自当前模块的指令文案")
                KeyValueRow(label: "prompt", value: "AIActionCenter.Fields[\"prompt\"]（由上述变量拼装）")
                KeyValueRow(label: "responseFormat", value: "StoryboardResponseParser.responseFormatHint")
            }
            Text("当前 Prompt 字面内容 (供校对)：")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(promptText)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor)))
            }
            .frame(minHeight: 140)
        }
    }

    private var sceneMetadataSample: String {
        guard context.scenes.isEmpty == false else { return "[]" }
        struct Metadata: Codable {
            let id: UUID
            let title: String
            let summary: String
            let order: Int
        }
        let payload = context.scenes.prefix(3).map { scene in
            Metadata(id: scene.id, title: scene.title, summary: scene.summary, order: scene.order)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "[]"
    }
}

private struct BlueprintSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlueprintBullet: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .padding(.top, 6)
            Text(text)
                .font(.subheadline)
        }
    }
}

private struct KeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 220, alignment: .leading)
            Text(value.ifEmptyPlaceholder())
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PromptCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.bold())
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}


private extension String {
    func ifEmptyPlaceholder(_ placeholder: String = "（暂无内容）") -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : trimmed
    }
}
