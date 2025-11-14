//
//  PromptTemplate.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

public struct PromptField: Identifiable, Hashable, Codable, Sendable {
    public enum FieldKind: String, Codable, Sendable {
        case text
        case options
        case numeric
        case assetReference
    }

    public let id: String
    public let title: String
    public let placeholder: String
    public let kind: FieldKind
    public let options: [String]
    public let defaultValue: String?

    public init(
        id: String,
        title: String,
        placeholder: String = "",
        kind: FieldKind,
        options: [String] = [],
        defaultValue: String? = nil
    ) {
        self.id = id
        self.title = title
        self.placeholder = placeholder
        self.kind = kind
        self.options = options
        self.defaultValue = defaultValue
    }
}

public struct PromptTemplate: Identifiable, Hashable, Codable, Sendable {
    public let id: SceneAction
    public let summary: String
    public let fields: [PromptField]
    public let systemHint: String

    public init(id: SceneAction, summary: String, fields: [PromptField], systemHint: String) {
        self.id = id
        self.summary = summary
        self.fields = fields
        self.systemHint = systemHint
    }
}

public enum PromptTemplateCatalog {
    public static let templates: [PromptTemplate] = SceneAction.allCases.map { action in
        switch action {
        case .generateScene:
            return PromptTemplate(
                id: action,
                summary: "构建场景骨架并指定主叙事元素。",
                fields: [
                    PromptField(id: "theme", title: "主题", placeholder: "例如：赛博朋克市场", kind: .text),
                    PromptField(id: "mood", title: "氛围", placeholder: "例如：雨夜、霓虹、烟雾", kind: .text),
                    PromptField(id: "camera", title: "镜头语言", placeholder: "广角、远景、航拍", kind: .options, options: ["广角", "远景", "航拍", "俯视"]),
                    PromptField(id: "lighting", title: "光照", placeholder: "体积光、逆光", kind: .text)
                ],
                systemHint: "你是一名概念设计师，负责根据结构化字段生成简洁清晰的场景描述。"
            )
        case .enhanceDetails:
            return PromptTemplate(
                id: action,
                summary: "为已有场景补充材质、道具与光影细节。",
                fields: [
                    PromptField(id: "baseScene", title: "原始场景描述", placeholder: "引用上一轮场景概述", kind: .text),
                    PromptField(id: "detailFocus", title: "细节焦点", placeholder: "服饰、天气、氛围特效", kind: .text),
                    PromptField(id: "texture", title: "材质/质感", placeholder: "磨砂金属、柔软织物", kind: .text)
                ],
                systemHint: "你是一名美术修饰师，请在不改变主题的前提下强化细节。"
            )
        case .perspectiveShift:
            return PromptTemplate(
                id: action,
                summary: "生成不同视角/镜头下的同一场景。",
                fields: [
                    PromptField(id: "referenceScene", title: "参考场景", placeholder: "可粘贴上一轮提示或摘要", kind: .text),
                    PromptField(id: "targetAngle", title: "目标视角", placeholder: "低机位、肩扛、过肩", kind: .text),
                    PromptField(id: "focalLength", title: "焦段/镜头参数", placeholder: "35mm, 85mm", kind: .text),
                    PromptField(id: "motion", title: "运动方式", placeholder: "推拉、跟随、摇镜", kind: .options, options: ["推镜", "拉镜", "跟拍", "摇镜"])
                ],
                systemHint: "保持原始人物/场景一致，仅改变镜头语言。"
            )
        case .createCharacter:
            return PromptTemplate(
                id: action,
                summary: "快速生成角色设定与站姿。",
                fields: [
                    PromptField(id: "characterRole", title: "角色身份", placeholder: "游侠、黑客、指挥官", kind: .text),
                    PromptField(id: "silhouette", title: "轮廓/体态", placeholder: "高挑、厚重装备", kind: .text),
                    PromptField(id: "attire", title: "服饰要点", placeholder: "披风、机甲、古典礼服", kind: .text),
                    PromptField(id: "emotion", title: "表情/精神状态", placeholder: "果断、疲惫、狂热", kind: .text)
                ],
                systemHint: "你是角色美术导演，请构建具有戏剧张力的角色形象。"
            )
        case .editCharacter:
            return PromptTemplate(
                id: action,
                summary: "在之前角色基础上做属性微调。",
                fields: [
                    PromptField(id: "baseCharacter", title: "基线角色", placeholder: "可引用历史提示或描述", kind: .text),
                    PromptField(id: "editFocus", title: "修改重点", placeholder: "颜色、材质、姿态", kind: .text),
                    PromptField(id: "restrictions", title: "需要保持的要素", placeholder: "角色关系、核心装备", kind: .text)
                ],
                systemHint: "保持角色身份与叙事一致，仅对指定特征做精修。"
            )
        case .blendCharacterAndScene:
            return PromptTemplate(
                id: action,
                summary: "将角色与场景融合，强调互动关系。",
                fields: [
                    PromptField(id: "characterRef", title: "角色引用", placeholder: "可使用 <img:id> 占位符", kind: .assetReference),
                    PromptField(id: "sceneRef", title: "场景引用", placeholder: "可使用 <img:id> 占位符", kind: .assetReference),
                    PromptField(id: "interaction", title: "互动方式", placeholder: "奔跑、对峙、合作", kind: .text),
                    PromptField(id: "mood", title: "整体氛围", placeholder: "紧张、浪漫、史诗", kind: .text)
                ],
                systemHint: "生成的画面需要突出人物与环境的呼应关系。"
            )
        case .aiConsole:
            return PromptTemplate(
                id: action,
                summary: "自由对话，默认不附带指令，可在资料库自定义。",
                fields: [],
                systemHint: ""
            )
        }
    }
}
