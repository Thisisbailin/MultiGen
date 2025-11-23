//
//  PainPoint.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

/// AIGC 场景创作中常见的痛点，用于在应用内展示与记录。
public struct PainPoint: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let title: String
    public let detail: String
    public let solution: String

    public init(id: String, title: String, detail: String, solution: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.solution = solution
    }
}

public enum SceneAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case generateScene
    case enhanceDetails
    case perspectiveShift
    case createCharacter
    case editCharacter
    case blendCharacterAndScene
    case aiConsole

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .generateScene: return "生成场景"
        case .enhanceDetails: return "生成场景细节"
        case .perspectiveShift: return "场景视角转换"
        case .createCharacter: return "生成角色"
        case .editCharacter: return "角色编辑"
        case .blendCharacterAndScene: return "人与场景溶图"
        case .aiConsole: return "智能协作"
        }
    }

    public var iconName: String {
        switch self {
        case .generateScene: return "square.grid.3x3.fill"
        case .enhanceDetails: return "sparkles"
        case .perspectiveShift: return "cube.transparent"
        case .createCharacter: return "person.crop.square"
        case .editCharacter: return "paintbrush.pointed"
        case .blendCharacterAndScene: return "person.2.square.stack"
        case .aiConsole: return "bubble.left.and.bubble.right"
        }
    }

    public static var workflowActions: [SceneAction] {
        [.generateScene, .enhanceDetails, .perspectiveShift, .createCharacter, .editCharacter, .blendCharacterAndScene]
    }
}

/// 静态数据源，后续可替换为 SwiftData/远程配置。
public enum PainPointCatalog {
    public static let corePainPoints: [PainPoint] = [
        PainPoint(
            id: "prompt-fragmentation",
            title: "提示链条割裂",
            detail: "场景、角色、视角提示散落在多个对话中，难以复用与追溯。",
            solution: "MultiGen 以模板化 Schema 统一描述提示，在同一视图中展示并可一键复制重用。"
        ),
        PainPoint(
            id: "asset-detachment",
            title: "素材与提示脱节",
            detail: "本地参考图无法直接参与提示编排，导致上下文不完整。",
            solution: "支持素材抽屉与引用占位符，任何图片都可以绑定到特定模板字段。"
        ),
        PainPoint(
            id: "audit-gap",
            title: "缺乏可审计记录",
            detail: "团队无法快速定位一张图对应的提示、素材与模型参数。",
            solution: "每次生成都写入审计日志，包含 prompt hash、资产引用与模型版本。"
        ),
        PainPoint(
            id: "key-security",
            title: "API Key 管理混乱",
            detail: "密钥多以文本共享，存在泄露与失效风险。",
            solution: "应用提供本地安全存储与权限检测，必要时可提示用户更新密钥或启用中转兜底。"
        ),
        PainPoint(
            id: "iteration-cost",
            title: "多视角/角色迭代成本高",
            detail: "每次视角或角色变体都需要重写大量提示。",
            solution: "六类场景动作封装常用字段，可直接派生衍生任务并复用历史记录。"
        )
    ]
}
