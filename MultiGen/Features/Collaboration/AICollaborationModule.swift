import SwiftUI

struct AICollaborationModule: View {
    @EnvironmentObject private var navigationStore: NavigationStore

    var body: some View {
        switch currentModule {
        case .script:
            ScriptCollaborationView()
        case .storyboard:
            StoryboardCollaborationView()
        case .promptHelperStyle:
            PromptHelperCollaborationView()
        case .promptHelper:
            PromptHelperCollaborationView()
        case .general:
            GeneralCollaborationView()
        }
    }

    private var currentModule: AIChatModule {
        switch navigationStore.selection {
        case .script:
            return .script
        case .storyboard:
            return .storyboard
        case .libraryStyles, .libraryCharacters, .libraryScenes, .libraryPrompts:
            return .promptHelper
        default:
            return .general
        }
    }
}

struct GeneralCollaborationView: View {
    var body: some View {
        AIChatSidebarView(moduleOverride: .general)
    }
}

struct ScriptCollaborationView: View {
    @EnvironmentObject private var scriptStore: ScriptStore

    private var needsGuidance: Bool {
        scriptStore.projects.isEmpty
    }

    var body: some View {
        AIChatSidebarView(moduleOverride: .script)
            .overlay(alignment: .center) {
                if needsGuidance {
                    ModuleCollaborationHint(
                        icon: "text.badge.plus",
                        title: "尚未创建剧本项目",
                        message: "请在剧本模块中新建项目或选择已有项目，以便智能协同读取上下文提供建议。"
                    )
                    .padding()
                    .allowsHitTesting(false)
                }
            }
    }
}

struct PromptHelperCollaborationView: View {
    @EnvironmentObject private var navigationStore: NavigationStore
    @EnvironmentObject private var scriptStore: ScriptStore

    private var hasProject: Bool {
        navigationStore.currentScriptProjectID.flatMap { id in
            scriptStore.projects.first(where: { $0.id == id })
        } != nil
    }

    var body: some View {
        AIChatSidebarView(moduleOverride: .promptHelper)
            .overlay(alignment: .center) {
                if hasProject == false {
                    ModuleCollaborationHint(
                        icon: "sparkles.rectangle.stack",
                        title: "请选择项目",
                        message: "在角色/场景/指令模块中选择项目后，提示词助手才能读取剧本文本生成形象设计提示词。"
                    )
                    .padding()
                    .allowsHitTesting(false)
                }
            }
    }
}

struct StoryboardCollaborationView: View {
    @EnvironmentObject private var navigationStore: NavigationStore

    private var needsSceneSelection: Bool {
        navigationStore.currentStoryboardSceneID == nil &&
        navigationStore.currentStoryboardSceneSnapshot == nil
    }

    var body: some View {
        AIChatSidebarView(moduleOverride: .storyboard)
            .overlay(alignment: .center) {
                if needsSceneSelection {
                    ModuleCollaborationHint(
                        icon: "rectangle.stack.badge.plus",
                        title: "请选择分镜场景",
                        message: "在分镜模块中选中场景，再切换至智能协同即可自动生成镜头。"
                    )
                    .padding()
                    .allowsHitTesting(false)
                }
            }
    }
}
