//
//  CreateOperation.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

public enum CreateFocusGroup: String, CaseIterable, Identifiable, Sendable {
    case character
    case scene
    case blend

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .character: return "角色创作"
        case .scene: return "场景创作"
        case .blend: return "溶图创作"
        }
    }

    public var description: String {
        switch self {
        case .character: return "支持描述文生图或添加人物参考图后进行图生图。"
        case .scene: return "用文字生成场景或基于参考图片进行场景变换。"
        case .blend: return "同时输入角色图与场景图，完成溶图合成。"
        }
    }
}

public struct CreateOperation: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let group: CreateFocusGroup
    public let title: String
    public let subtitle: String
    public let action: SceneAction

    public init(group: CreateFocusGroup, title: String, subtitle: String, action: SceneAction) {
        self.id = UUID()
        self.group = group
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    public var iconName: String {
        switch group {
        case .character: return "person.crop.square"
        case .scene: return "square.grid.3x3"
        case .blend: return "person.2.square.stack"
        }
    }

    public var template: PromptTemplate? {
        PromptTemplateCatalog.templates.first { $0.id == action }
    }
}

public enum CreateOperationCatalog {
    public static let characterOps: [CreateOperation] = [
        CreateOperation(
            group: .character,
            title: "角色设定",
            subtitle: "描述 + 可选角色图，生成全新角色。",
            action: .createCharacter
        ),
        CreateOperation(
            group: .character,
            title: "角色微调",
            subtitle: "引用角色图进行姿态/风格微调。",
            action: .editCharacter
        )
    ]

    public static let sceneOps: [CreateOperation] = [
        CreateOperation(
            group: .scene,
            title: "场景生成",
            subtitle: "通过文字快速搭建场景。",
            action: .generateScene
        ),
        CreateOperation(
            group: .scene,
            title: "场景细化",
            subtitle: "为现有场景补充材质与细节。",
            action: .enhanceDetails
        ),
        CreateOperation(
            group: .scene,
            title: "视角转换",
            subtitle: "基于参考图调整镜头视角。",
            action: .perspectiveShift
        )
    ]

    public static let blendOps: [CreateOperation] = [
        CreateOperation(
            group: .blend,
            title: "溶图创作",
            subtitle: "输入人物与场景双图完成合成。",
            action: .blendCharacterAndScene
        )
    ]

    public static let allGroups: [CreateFocusGroup] = [.character, .scene, .blend]
}
