import SwiftUI
import UniformTypeIdentifiers

struct BatchStoryboardWizardView: View {
    @ObservedObject var flow: BatchStoryboardFlowStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingStoryboardGuideImporter = false
    @State private var showingPromptGuideImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            progressStrip
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stageContextSection
                    if flow.phase == .storyboard {
                        storyboardSection
                    } else if flow.phase == .sora {
                        soraSection
                    } else if flow.phase == .completed {
                        completionSection
                    } else if flow.phase == .cancelled {
                        cancelledSection
                    }
                }
                .padding(.vertical, 4)
            }
            if let error = flow.errorMessage {
                Text("错误：\(error)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("关闭") { dismiss() }
                Spacer()
                if flow.phase == .completed {
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 880, minHeight: 640)
        .fileImporter(isPresented: $showingStoryboardGuideImporter, allowedContentTypes: markdownTypes) { result in
            if case .success(let url) = result, let text = try? String(contentsOf: url, encoding: .utf8) {
                flow.storyboardGuide = text
            }
        }
        .fileImporter(isPresented: $showingPromptGuideImporter, allowedContentTypes: markdownTypes) { result in
            if case .success(let url) = result, let text = try? String(contentsOf: url, encoding: .utf8) {
                flow.promptGuide = text
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("批量转写分镜 / 提示词").font(.title3.weight(.bold))
                Text(flow.project.title).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var progressStrip: some View {
        HStack(spacing: 12) {
            Capsule().fill(flow.phase == .context ? Color.accentColor : .secondary.opacity(0.3))
                .frame(height: 6)
            Capsule().fill(flow.phase == .storyboard ? Color.accentColor : .secondary.opacity(0.3))
                .frame(height: 6)
            Capsule().fill(flow.phase == .sora ? Color.accentColor : .secondary.opacity(0.3))
                .frame(height: 6)
        }
    }

    private var stageContextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("阶段 1：上下文构造").font(.headline)
                Spacer()
                Button("导入分镜指导文档") { showingStoryboardGuideImporter = true }
                    .disabled(true) // 当前仅支持粘贴
                    .help("当前版本请直接粘贴 md 内容")
            }
            TextEditor(text: Binding(
                get: { flow.storyboardGuide },
                set: { flow.storyboardGuide = $0 }
            ))
            .frame(minHeight: 80)
            .border(Color.secondary.opacity(0.2))
            HStack(spacing: 10) {
                Button("生成上下文（项目简介/角色/剧集概述）") {
                    Task { await flow.generateContext() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(flow.isWorking || flow.storyboardGuide.isEmpty)

                Button("确认并进入分镜阶段") {
                    flow.phase = .storyboard
                }
                .disabled(flow.projectSummary.isEmpty || flow.characterSummary.isEmpty || flow.episodeOverview.isEmpty)
            }
            if flow.contextPreview.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI 生成结果").font(.subheadline.bold())
                    TextEditor(text: .constant(flow.contextPreview))
                        .frame(minHeight: 120)
                        .border(Color.secondary.opacity(0.2))
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("项目简介").font(.subheadline.bold())
                    Text(flow.projectSummary.isEmpty ? "尚未生成" : flow.projectSummary)
                        .font(.footnote).textSelection(.enabled)
                    Text("角色概述").font(.subheadline.bold())
                    Text(flow.characterSummary.isEmpty ? "尚未生成" : flow.characterSummary)
                        .font(.footnote).textSelection(.enabled)
                    Text("剧集概述").font(.subheadline.bold())
                    Text(flow.episodeOverview.isEmpty ? "尚未生成" : flow.episodeOverview)
                        .font(.footnote).textSelection(.enabled)
                }
            }
        }
    }

    private var storyboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let ep = flow.currentEpisode
            HStack {
                Text("阶段 2：分镜生成").font(.headline)
                Spacer()
                Text("进度 \(flow.currentEpisodeIndex + 1)/\(flow.episodes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let episode = ep {
                Text("当前剧集：\(episode.displayLabel)").font(.subheadline)
                Button("生成本集分镜") {
                    Task { await flow.generateStoryboardForCurrentEpisode() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(flow.isWorking)

                if let draft = flow.episodeStates[episode.id]?.storyboardText {
                    TextEditor(text: .constant(draft))
                        .frame(minHeight: 220)
                        .border(Color.secondary.opacity(0.2))
                        .textSelection(.enabled)
                    HStack {
                        Button("确认写入并下一集") { flow.confirmStoryboardForCurrentEpisode(); flow.goToNextStoryboardEpisode() }
                            .buttonStyle(.borderedProminent)
                        Button("重写本集") {
                            Task { await flow.generateStoryboardForCurrentEpisode() }
                        }
                        Button("取消任务") { flow.cancel() }
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var soraSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let ep = flow.currentEpisode
            HStack {
                Text("阶段 3：Sora 提示词").font(.headline)
                Spacer()
                Text("进度 \(flow.currentEpisodeIndex + 1)/\(flow.episodes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("导入提示词指导文档") { showingPromptGuideImporter = true }
                    .disabled(true)
                    .help("当前版本请直接粘贴 md 内容")
            }
            if let episode = ep {
                Text("当前剧集：\(episode.displayLabel)").font(.subheadline)
                Button("生成本集提示词") {
                    Task { await flow.generateSoraForCurrentEpisode() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(flow.isWorking || flow.promptGuide.isEmpty)

                if let draft = flow.episodeStates[episode.id]?.soraText {
                    TextEditor(text: .constant(draft))
                        .frame(minHeight: 200)
                        .border(Color.secondary.opacity(0.2))
                        .textSelection(.enabled)
                    HStack {
                        Button("确认写入并下一集") { flow.confirmSoraForCurrentEpisode(); flow.goToNextSoraEpisode() }
                            .buttonStyle(.borderedProminent)
                        Button("重写本集") {
                            Task { await flow.generateSoraForCurrentEpisode() }
                        }
                        Button("取消任务") { flow.cancel() }
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var completionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("全部完成").font(.headline)
            Text("所有剧集已完成分镜转写与 Sora 提示词生成。").foregroundStyle(.secondary)
        }
    }

    private var cancelledSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("任务已取消").font(.headline)
            Text("已确认的剧集结果会保留，其他不会写入。").foregroundStyle(.secondary)
        }
    }

    private var markdownTypes: [UTType] {
        var types: [UTType] = []
        if let md = UTType(filenameExtension: "md") {
            types.append(md)
        }
        types.append(.plainText)
        return types
    }
}
