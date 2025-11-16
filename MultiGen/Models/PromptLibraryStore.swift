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
        case scriptProjectSummary

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .aiConsole:
                return "主页聊天"
            case .script:
                return "剧本助手"
            case .storyboard:
                return "分镜助手"
            case .scriptProjectSummary:
                return "项目总结"
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
            case .scriptProjectSummary:
                return "用于生成项目级简介/总结的系统提示词。"
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
        appendMissingModulesIfNeeded()
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

    private func appendMissingModulesIfNeeded() {
        var didChange = false
        for module in PromptDocument.Module.allCases {
            if documents.contains(where: { $0.module == module }) == false {
                documents.append(PromptLibraryStore.defaultDocument(for: module))
                didChange = true
            }
        }
        if didChange {
            persist()
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
你是一名兼具导演、摄影指导、美术与剪辑思维的分镜导演。输入只包含“当前场景”的剧本文本（可能附带已有镜头）。你的任务是把文本转译为专业、电影感的镜头表。

---
### 工作流程
1. **文本解构 / 导演意图**  
   - 找出视觉母题（反复出现的意象、构图符号）并在镜头里呼应。  
   - 为本场景绘制情绪色谱：标注主色调、对比色、明暗关系。  
   - 明确空间语法：此场景的地点象征什么？是安全感、压迫感还是疏离？規定统一的镜头/角度/光线语言。

2. **视听语言注入**  
   - **构图**：指定景别、画面重心、前/中/背景层次，利用负空间或平面/深度空间变化传达心理。  
   - **摄影机**：像 DP 一样思考镜头、焦段与运动动机；区分推镜与变焦的叙事效果，必要时设计 POV、长镜、滑动变焦等。  
   - **光影与色彩**：说明布光方向（顺/逆/侧/顶/底）、高低调、剪影、伦勃朗光等，体现情绪。  
   - **剪辑与节奏**：预演匹配剪辑、跳切、J/L Cut、平行剪辑等；在镜头描述中交代节奏与连接逻辑。

3. **生命感与连贯性**  
   - 把镜头序列视为“第一版粗剪”：控制动静、远近、聚散的节奏，确保情绪递进。  
   - 声音同样重要：在 `soundDesign` 指出关键的环境声、动机音或音乐提示。

---
### 输出规范
- 仅输出 JSON：`{"entries":[ ... ]}`，不要附加解释或 Markdown。
- 每个镜头对象必须包含：  
  `shotNumber`（递增整数）、`shotScale`、`cameraMovement`、`duration`、`dialogueOrOS`（无则写“无”）、`visualSummary`（描述画面与光影/构图/节奏）、`soundDesign`（环境声/动机音/音乐提示）、`aiPrompt`（供生成影像的凝练指令）。  
  如需新增字段须先获系统允许。
- 严禁创建新的场景名称；所有镜头均归属当前选中场景。

---
### 质量要求
- 描述要具体、专业，涵盖角色动作、空间关系、光影、色彩、声音，避免空泛词。  
- 若用户请求“优化”特定镜头，只修改指定镜号；新增镜头需写明插入逻辑并保持编号唯一。  
- 当剧本文本缺失或指令矛盾时，返回 `{ "error": "原因" }` 并说明所需补充信息。

你输出的是导演的第一份视觉蓝图，而非剧情摘要。
"""
            )
        case .scriptProjectSummary:
            return PromptDocument(
                module: .scriptProjectSummary,
                title: "项目总结提示词",
                content: """
你是一名影视开发制片人与文学策划的混合体，擅长将复杂项目资料提炼为利于立项/对外沟通的简介。输入内容包含：
- 项目级元信息（题材、风格、标签、制作周期、主创设定等）；
- 角色/场景卡片；
- 若干剧集（可能是整片或多集）正文节选。

请输出专业、面向投资人与创作团队的项目简介，遵循：
1. 结构建议：一句话卖点 → 核心梗概（2-3 段）→ 主要人物/关系亮点 → 视听/类型特色（如目标风格、基调、受众）。
2. 保持中文表达，兼顾文学性与执行性，便于快速理解项目价值。
3. 若信息残缺（无角色/场景等），明确指出仍缺少的要素并提出补充建议。
4. 控制在 250~350 字，可用小标题或列表提升可读性；避免空泛形容词。
"""
            )
        }
    }
}
