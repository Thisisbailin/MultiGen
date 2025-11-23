# Mission Brief — AI Collaboration Hub
Objective:
- 将“智能协同”模块重构为 AI 中枢（核心服务+模块定制层），统一接管所有 OpenAI 样式中转请求（文本/图像/视频）、历史记忆、流式输出与模块注入。
- 让每个核心模块（主页、剧本、分镜、影像）通过标准接口与中枢交互，减少 UI 层耦合，便于未来扩展（仅限 macOS 平台）。

Out-of-scope:
- 不实现 iOS / iPadOS 入口；无需跨平台适配。
- 不新增外部依赖或云端存储；暂不实现完整历史浏览/多设备同步。
- 不扩展影像模块五大子模块的业务逻辑，仅提供文生图 MVP 的接入。

Inputs / Outputs (contracts):
- 输入：Sidebar 模块发起的 `AIActionRequest`（文本/图像）、模块上下文（脚本项目、分镜场景、影像段落）、用户输入/附件。
- 输出：AI 流式文本、图像结果引用、模块注入回调（脚本总结更新、分镜镜头生成、影像结果对象）、系统通知。

Acceptance Criteria (AC):
1. AC1 — 核心 AI 中枢提供独立 ViewModel/Service API，UI 不直接操作 Store/ActionCenter。
2. AC2 — 剧本、分镜、影像三类模块可通过定制控制器注入上下文并接收结果。
3. AC3 — 流式对话/项目总结/影像请求均正常运行，且路由/模型标识与设置保持一致。
4. AC4 — 历史记录读取/切换由统一服务管理，可在记忆开启时查看全部会话。

Constraints (perf/i18n/a11y/privacy):
- 目标平台 macOS 14+；SwiftUI + Concurrency；保持 UI 响应 < 100ms（除 AI 等待）。
- 不持久化敏感数据到云端；附件仅用于当次请求；日志脱敏。
- 文字 UI 维持中文；流式输出要在主线程更新。

Dependencies & Risks:
- 依赖 `AIActionCenter`、`AppDependencies` 的路由配置；需要确保无循环引用。
- 风险：重构期间可能影响现有剧本/分镜/影像操作功能；需分阶段验证。
- 风险缓解：分层拆分、逐步迁移；保留旧逻辑的回滚分支。

Platform Differences via Platform Layer:
- 当前阶段仅支持 macOS。若未来扩展 iOS/iPadOS，需确保 ViewModel 与服务层可复用，UI 通过 Platform 层适配。
