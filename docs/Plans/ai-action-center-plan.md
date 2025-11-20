# Plan — ai-action-center
Architecture Intent Block:
- 仅面向 macOS，维持 Domain → Platform Services → Features → UI 的依赖方向；新的 AI 中枢（AIActionCenter）位于 Feature 层，由 `AppDependencies` 注入各视图/Store。
- 所有 Gemini 请求（文本/图像、官网/中转）都经由 AIActionCenter 统一构造 `SceneJobRequest`，并在此处记录审计、路由、上下文，Sidebar 负责展示结果。
- 各业务模块（智能协同 Sidebar、剧本项目总结、分镜自动写入、影像 MVP、设置诊断）通过传入来源/上下文描述来声明需求，AIActionCenter 负责路由到文本或图像服务并把结果回传模块。

Work Breakdown (≤1 day each):
1. **AIActionCenter 基础** — 在 `MultiGen/Features/Sidebar` 下实现 `AIActionKind`, `AIActionRequest`, `AIActionResult`, `AIActionCenter`，支持文本/图像通道、Prompt Library 读取、上下文描述、审计写入，并暴露环境对象给所有视图。回滚点：保留旧的直接 `textService/imageService` 调用路径，并以编译 Flag 切换。
2. **Sidebar & Script/Storyboard 接入** — 重写 `AIChatSidebarView` 的发送流程、项目总结流程，让其仅通过 ActionCenter 触发请求；Storyboard 自动化回调由 ActionCenter 调用 handler 并推送系统消息。更新 UI 显示“模型 · 路线”。回滚点：保留旧 `requestAIResponse` 函数方便即时切换。
3. **Imaging / Settings 诊断迁移** — 影像 MVP 改为向 ActionCenter 发起结构化请求，结果通过回调写入 Store；Settings 中的连接测试与文本测试也通过 ActionCenter 以便统一日志。回滚点：在 Store 中保留 Legacy 调用以 `#warning` 或注释记录，必要时可 `return` 旧逻辑。

Verification Plan (by AC):
- AC1（中心化路由）：运行 `xcodebuild -scheme MultiGen -destination "platform=macOS"` 确认 ActionCenter 编译无误；通过单步调试或日志验证 `AIActionCenter.perform` 收到 Sidebar 及其它模块的请求。
- AC2（Sidebar/剧本/分镜）：在模拟数据下发送普通对话与项目总结，检查 Sidebar 系统消息包含“模型 · 路线”，Storyboard Handler 正常获得 JSON 并追加系统提示。
- AC3（影像/设置）：触发 Imaging 生成与设置测试请求，确保状态提示与审计记录（可通过控制台日志或临时断点）均来自 ActionCenter。

Rollback Points:
- 若 ActionCenter 引入后导致 UI 崩溃，可将 `ContentView` 中的 `.environmentObject(actionCenter)` 移除，并恢复原有 `requestAIResponse` 流程。
- 如果 Imaging 的生成响应被 ActionCenter 拒绝，可通过 Feature Flag 切换回 `dependencies.textService()/imageService()` 直接调用，待排查日志后再开启。
- Settings 测试若受 ActionCenter 影响出现延迟或异常，可暂时保留独立路径，并在文档中标记“诊断功能未接入中枢”。
