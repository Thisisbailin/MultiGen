import Foundation

enum AIChatModule: String, Equatable, CaseIterable {
    case general
    case script
    case storyboard
    case promptHelper
    case promptHelperStyle

    static func resolve(selection: SidebarItem, context: ChatContext) -> AIChatModule {
        switch selection {
        case .script:
            return .script
        case .storyboard:
            return .storyboard
        case .libraryStyles, .libraryCharacters, .libraryScenes, .libraryPrompts:
            return selection == .libraryStyles ? .promptHelperStyle : .promptHelper
        default:
            switch context {
            case .script, .scriptProject:
                return .script
            case .storyboard:
                return .storyboard
            case .general:
                return .general
            default:
                return .promptHelper
            }
        }
    }

    var allowsAttachments: Bool {
        switch self {
        case .general, .promptHelperStyle, .promptHelper:
            return true
        case .script, .storyboard:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .general:
            return "通用协作"
        case .script:
            return "剧本助手"
        case .storyboard:
            return "分镜助手"
        case .promptHelper:
            return "提示词助手"
        case .promptHelperStyle:
            return "风格助手"
        }
    }

    var supportsMemory: Bool {
        true
    }
}
