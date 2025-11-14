//
//  PromptLibraryStore.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation
import Combine

struct PromptDocument: Identifiable, Codable, Hashable {
    enum Module: String, Codable, CaseIterable, Identifiable {
        case aiConsole
        case script
        case storyboard

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .aiConsole:
                return "主页聊天"
            case .script:
                return "剧本助手"
            case .storyboard:
                return "分镜助手"
            }
        }

        var moduleDescription: String {
            switch self {
            case .aiConsole:
                return "默认的智能协作提示词；当其他模块没有绑定提示词时使用。"
            case .script:
                return "用于剧本阶段（按集优化/润色）的系统提示词。"
            case .storyboard:
                return "用于 AI 分镜助手的系统提示词模版。"
            }
        }
    }

    let id: UUID
    let module: Module
    var title: String
    var content: String
    var lastUpdated: Date

    init(
        id: UUID = UUID(),
        module: Module,
        title: String,
        content: String,
        lastUpdated: Date = .now
    ) {
        self.id = id
        self.module = module
        self.title = title
        self.content = content
        self.lastUpdated = lastUpdated
    }
}

@MainActor
final class PromptLibraryStore: ObservableObject {
    @Published private(set) var documents: [PromptDocument]
    private let storageURL: URL
    
    init() {
        storageURL = PromptLibraryStore.makeStorageURL()
        documents = PromptLibraryStore.load(from: storageURL)
        if documents.isEmpty {
            documents = PromptLibraryStore.defaultDocuments()
            persist()
        }
    }
    
    func document(for module: PromptDocument.Module) -> PromptDocument {
        if let doc = documents.first(where: { $0.module == module }) {
            return doc
        }
        let fallback = PromptLibraryStore.defaultDocument(for: module)
        documents.append(fallback)
        persist()
        return fallback
    }
    
    func updateDocument(module: PromptDocument.Module, content: String) {
        guard let index = documents.firstIndex(where: { $0.module == module }) else { return }
        documents[index].content = content
        documents[index].lastUpdated = .now
        persist()
    }
    
    func resetDocument(module: PromptDocument.Module) {
        let defaultDoc = PromptLibraryStore.defaultDocument(for: module)
        if let index = documents.firstIndex(where: { $0.module == module }) {
            documents[index] = defaultDoc
        } else {
            documents.append(defaultDoc)
        }
        persist()
    }
    
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(documents)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("PromptLibraryStore persist error: \(error)")
        }
    }
    
    private static func load(from url: URL) -> [PromptDocument] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([PromptDocument].self, from: data)) ?? []
    }
    
    private static func makeStorageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("MultiGen", isDirectory: true)
            .appendingPathComponent("prompt-library.json")
    }
    
    private static func defaultDocuments() -> [PromptDocument] {
        PromptDocument.Module.allCases.map { defaultDocument(for: $0) }
    }
    
    private static func defaultDocument(for module: PromptDocument.Module) -> PromptDocument {
        switch module {
        case .aiConsole:
            return PromptDocument(
                module: .aiConsole,
                title: "主页聊天提示词",
                content: """
你是 MultiGen 的常驻创意合伙人——一位友好、专业且具备影视剧本与短片创作经验的中文助理。无论用户处于哪种创作阶段，你都应：
- 先复述需求以确保理解，再给出洞察或可执行建议；
- 语气温和、启发式，避免直接否定；
- 必要时给出分条行动建议、引用经典案例，帮助用户拓展思路；
- 若问题超出影视/创意范畴，也要以通俗方式作答，但避免涉政/隐私等敏感内容；
- 没有把握时提示需要进一步信息，切勿捏造事实。
"""
            )
        case .script:
            return PromptDocument(
                module: .script,
                title: "剧本助手提示词",
                content: """
你是一名资深剧本统筹/剧作顾问，擅长分析长篇剧本与单集脚本。收到的上下文包含：
- 项目信息（题材、简介等）；
- 当前剧集的 Markdown 正文（可部分截断）。

工作准则：
1. 先用 1-2 句话概括该集核心冲突/主题，再按「人物」「情节节奏」「场景调度」「对白」等维度给出建议。
2. 指出可量化的修改方向（例如“第2幕高潮铺垫不足，可增加xx”），必要时给出替代表达。
3. 若文本残缺或上下文不足，需明确说明缺失信息并提出收集建议。
4. 输出以中文为主，条理清晰，可使用编号/小标题，避免长段落。
"""
            )
        case .storyboard:
            return PromptDocument(
                module: .storyboard,
                title: "分镜助手提示词",
                content: """
你是影视分镜导演，需要根据剧本文本与（可选）既有分镜条目生成/优化“场景-镜头”结构化脚本。必须严格遵守以下格式与约束：

【输出目标】
以 JSON 形式返回 `scenes` 数组，每个场景对象包含：
- `sceneTitle`: 场景名称
- `sceneSummary`: 场景画面/情绪概述
- `shots`: 镜头数组（至少 1 个）

每个镜头对象必须包含以下字段（全部为字符串，`shotNumber` 为整数）：
- `shotNumber`（阿拉伯数字，保证递增且唯一）
- `shotScale`（如：大全景/中景/特写）
- `cameraMovement`（如：推镜/摇镜/航拍/固定）
- `duration`（如：“5秒”“00:06”）
- `visualSummary`（画面主体与动作，重点描述画面而非对白）
- `dialogueOrOS`（若无对白填“无”）
- `soundDesign`（环境声/音效/音乐，若无填“无”）
- `aiPrompt`（供后续影像生成的精炼提示词）

【操作模式】
- 当用户请求“首次转写”时，你需要覆盖整集关键场景；若请求“优化/补全”，请只对指定镜头进行增删改，并保持原有编号，新增镜头可在末尾或指定位置插入并解释原因。
- 必须只返回合法 JSON，不添加前后缀、解释或 Markdown；如需提示错误，应返回 `{ "error": "<原因>" }`。
- 若输入剧本不足以支撑分镜（例如缺少剧情），请返回 error 并说明需要的附加资料。

确保所有字段内容为中文，避免出现未定义的键、空数组或 null。
"""
            )
        }
    }
}
