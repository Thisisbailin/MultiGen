import Foundation

enum AIChatModule: String, Equatable, CaseIterable {
    case general
    case script
    case storyboard
    case imaging

    static func resolve(selection: SidebarItem, context: ChatContext) -> AIChatModule {
        switch selection {
        case .script:
            return .script
        case .storyboard:
            return .storyboard
        case .image:
            return .imaging
        default:
            switch context {
            case .script, .scriptProject:
                return .script
            case .storyboard:
                return .storyboard
            default:
                return .general
            }
        }
    }

    var allowsAttachments: Bool {
        self == .imaging
    }

    var displayName: String {
        switch self {
        case .general:
            return "通用协作"
        case .script:
            return "剧本助手"
        case .storyboard:
            return "分镜助手"
        case .imaging:
            return "影像助手"
        }
    }

    var supportsMemory: Bool {
        true
    }
}
