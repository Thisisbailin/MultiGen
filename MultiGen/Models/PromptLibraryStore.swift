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
        case promptHelperCharacterScene
        case promptHelperStyle
        case promptHelperStoryboard
        case imagingAssistant

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
            case .promptHelperCharacterScene:
                return "提示词助手 · 角色/场景"
            case .promptHelperStyle:
                return "提示词助手 · 风格"
            case .promptHelperStoryboard:
                return "提示词助手 · 分镜（占位）"
            case .imagingAssistant:
                return "影像模块系统提示"
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
            case .promptHelperCharacterScene:
                return "为角色与场景生成/优化文生图提示词，偏重造型/材质/光线/空间感等美术向描述。"
            case .promptHelperStyle:
                return "分析风格参考图，提炼可复用的风格提示词（导演/美术向）。"
            case .promptHelperStoryboard:
                return "分镜提示词助手占位，后续用于补充镜头级提示词。"
            case .imagingAssistant:
                return "影像模块的系统提示，用于多模态对话/图生图的安全与风格约束。"
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
        case .promptHelperCharacterScene:
            return PromptDocument(
                module: .promptHelperCharacterScene,
                title: "提示词助手 · 角色/场景",
                content: """
你是影视项目的美术设计师，需为角色或场景撰写中文文生图提示词。
输入只包含：角色/场景名称与简短描述（无剧本原文）。

要求：
1. 仅输出一段提示词，不要列表/解释/代码块。
2. 角色：写清外观、服装、材质、气质、姿态、光线、镜头感/景别、时代与地域风格；可加入情绪或标志性道具。
3. 场景：写清空间/环境、光线/色调、时间、材质细节、景别/构图、氛围与关键道具。
4. 避免堆砌英语或空泛词，控制在一段内可直接用于专业生图平台。
"""
            )
        case .promptHelperStyle:
            return PromptDocument(
                module: .promptHelperStyle,
                title: "提示词助手 · 风格",
                content: """
你是一名具备导演和美术指导经验的风格分析师。系统会提供一张参考图（imageAttachment1Base64 / imageBase64）。请先客观观察图片内容，再输出一段可直接用于文生图的中文提示词。

要求：
1. 只输出提示词正文，不要解释、不要代码块；长度 300-500 字。
2. 必须根据图片反推：主体/场景、外观细节、光线方向与质感、色调对比、材质纹理、构图/景别/镜头感、时代或流派（如胶片颗粒/新黑色/赛博朋克等）。如图片无人物/无主体，请明确写“无人物”并仅描绘可见场景。
3. 用简短中文短语串联，保持连贯，避免堆砌英文或无关形容词。
4. 图片以 Base64 提供，必须基于图片内容描述；若无法解码或画面不清晰，请直接说明问题，禁止臆造不存在的元素。
"""
            )
        case .promptHelperStoryboard:
            return PromptDocument(
                module: .promptHelperStoryboard,
                title: "提示词助手 · 分镜",
                content: """
你是专业分镜提示词设计师。输入包含当前场景的分镜脚本（按镜号顺序，含景别/运镜/画面概述/台词/声音）。

任务：为每个镜头生成中文文生图提示词。
- 输出 JSON：{"prompts":[{"shotNumber":1,"prompt":"..."}]}，仅输出 JSON。
- 每条提示词聚焦镜头画面/光线/色调/构图/焦段/运动/材质等，避免多余解释。
"""
            )
        case .imagingAssistant:
            return PromptDocument(
                module: .imagingAssistant,
                title: "影像模块系统提示",
                content: """
你是多模态影像编辑助手，负责在保留参考图主体/构图/色调前提下，按用户与控制面板的要求做最小必要修改，生成可直接用于文生图/图生图的中文提示词与结果。

原则：
- 默认保持原图全部细节不变，只对用户指定的规格（张数/比例）、镜头旋转、景别、景深、俯仰等做对应调整。
- 严禁添加不存在的元素或改变主体身份；如需求与“保持原图”冲突，需明确说明并优先保证主体不变形。
- 输出时用简洁中文短语描述：主体、姿态/表情、场景/光线/色调、构图/镜头感、材质/纹理。必要时补充渲染特征（写实/插画等）。
- 若识别到 data URI / base64 图像即按图内容工作；如无法读取图片或指令矛盾，直接指出问题。
"""
            )
        }
    }
}
