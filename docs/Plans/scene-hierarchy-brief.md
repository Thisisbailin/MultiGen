# Mission Brief — scene-hierarchy
Objective:
- 将剧本（Project → Episode → Scene）与分镜（Scene → Shot）层级彻底对齐，确保 AI 智能协同能识别当前场景并输出可落地的分镜表。
- 为侧边栏的智能协同模块提供场景级上下文，解决“AI 仅基于整集剧本生成、忽视场景切分”的问题。
- 同步文档，明确智能协同的设计原则，便于后续扩展到影像模块。

Out-of-scope:
- 影像模块（影像/文生图/图生图）的重新设计与实现。
- 主页（ScenarioOverview）和资料库其余资产（角色/场景卡牌）的复杂交互。
- 更换中转服务或联网能力。

Inputs / Outputs (contracts):
- 输入：ScriptsStore 中的 `ScriptProject/ScriptEpisode/ScriptScene`，StoryboardStore 中与剧集绑定的 `StoryboardWorkspace`。
- 输出：`NavigationStore` 提供 `currentStoryboardEpisodeID/currentStoryboardSceneID` 用于 AI context；StoryboardView 按场景展示镜头；AIChatSidebar 根据页面上下文填充 prompt 字段（`sceneContext`）。

Acceptance Criteria (AC):
1. 当在分镜页面切换场景时，智能协同面板显示当前场景标题并在请求体中包含 `sceneContext` 字段。
2. 智能协同触发的分镜生成成功写入对应场景，若解析失败会在聊天流展示“未解析”提示，并保留原始 JSON。
3. 文档 `docs/navigation-and-prompt-library.md` 更新，说明场景上下文与提示词默认值的设计。

Constraints (perf/i18n/a11y/privacy):
- macOS 26 视觉规范：无额外分隔线、保持系统组件风格。
- 所有提示词默认值仅存储在本地 `prompt-library.json`，不得联网。
- 不新增第三方依赖；维持 SwiftUI + Combine 栈。

Dependencies & Risks:
- 依赖 ScriptStore/StoryboardStore 的数据结构，若未来 Schema 再次变动需要迁移。
- 解析器仍需假设 AI 返回符合 JSON 模板，提示词若被用户清空，需 graceful fallback。
- 若 NavigationStore 状态不同步，则 AI 可能发送错误上下文——需双向绑定选中的 episode/scene。

Platform Differences via Platform Layer:
- macOS 专用；iOS/iPadOS 入口暂不实现。未来若扩展，需要 Platform 层包装 NavigationStore/Sidebar 行为。
