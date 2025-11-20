import SwiftUI

struct AICollaborationModule: View {
    @EnvironmentObject private var navigationStore: NavigationStore

    var body: some View {
        switch currentModule {
        case .script:
            ScriptCollaborationView()
        case .storyboard:
            StoryboardCollaborationView()
        case .imaging:
            ImagingCollaborationView()
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
        case .image:
            return .imaging
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

struct ImagingCollaborationView: View {
    @EnvironmentObject private var imagingStore: ImagingStore

    private var showingVideoPlaceholder: Bool {
        imagingStore.selectedSegment == .video
    }

    var body: some View {
        AIChatSidebarView(moduleOverride: .imaging)
            .overlay(alignment: .center) {
                if showingVideoPlaceholder {
                    ModuleCollaborationHint(
                        icon: "video.badge.exclamationmark",
                        title: "视频工作流暂未开放",
                        message: "当前影像助手提供风格/人物/场景/合成的图像生成功能，视频功能力保留为未来迭代。"
                    )
                    .padding()
                    .allowsHitTesting(false)
                }
            }
    }
}
