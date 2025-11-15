# Plan — scene-hierarchy
Architecture Intent Block:
- 保持现有分层（Domain → Data → Features → UI），通过 `NavigationStore` 暴露全局选择态，`StoryboardDialogueStore` 负责解析/写入分镜，`AIChatSidebarView` 仅消费配好的上下文。
- Scene 数据作为 Domain 的单一真源：`ScriptEpisode.scenes` → `StoryboardSceneViewModel` → AI context。AI 写回时根据 sceneID 归档。
- 智能协同的 prompt/context 由 `PromptLibraryStore` 与 `NavigationStore` 协作，杜绝跨模块硬编码。

Work Breakdown (≤1 day each):
1. **状态同步基础** — 新增 `NavigationStore.currentStoryboardSceneID`，`StoryboardView` / `StoryboardDialogueStore` 在切换场景时写入，离开模块时清空。
2. **AI 上下文增强** — `AIChatSidebarView` 根据 `currentStoryboardSceneID` 挂载场景正文（含标题/摘要/正文截断）到请求字段 `sceneContext`，并更新提示 copy；AI 每次仅能操作该场景。
3. **Scene ViewModel 拓展** — `StoryboardSceneViewModel` 带上 `body`，供 UI/验证/AI 调用，`rebuildScenes()` 始终覆盖剧本中的所有场景（不再生成额外场景）。
4. **文档同步** — 更新 `docs/navigation-and-prompt-library.md`，记录场景上下文和默认提示词策略；列出回退策略。

Verification Plan (by AC):
- AC1：在分镜页面切换场景，观察侧边栏 context 文案；抓取 `dependencies.textService().submit` 发送参数（打印/调试）确认包含 `sceneContext`。
- AC2：触发一次 AI 回复成功写入；再手动构造错误 JSON，确认系统提示“未解析”并保留 detail。
- AC3：检视文档更新，并通过 `rg sceneContext docs` 确认索引。

Rollback Points:
- 若 `NavigationStore` 增强导致其它模块崩溃，可快速回退到上一次稳定提交（记录 git hash）。
- `AIChatSidebarView` 改动若引发崩溃，可通过 feature flag（临时布尔）关闭场景上下文，并恢复默认 `contextStatusText`。
- 文档调整若与既有流程冲突，可回滚相应 markdown。
