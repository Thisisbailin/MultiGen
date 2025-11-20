# Plan — AI Collaboration Hub
Architecture Intent Block:
- 将智能协同拆成“AI 中枢核心 (Core)”与“模块定制层 (Module Controllers)”，通过 ViewModel 暴露状态，UI 只负责渲染。
- Core 负责：上下文推断、请求字段构建、流式执行、历史存储、附件管理、与 `AIActionCenter` 交互。
- Module Controllers 负责：提供上下文/提示词、处理结果注入（剧本总结、分镜镜头、影像输出）。
- 保持 macOS 单平台优化，但在 Core 中不包含任何 AppKit 依赖，以便未来复用。

Work Breakdown (≤1 day each):
1. 核心 ViewModel 与服务层基础：
   - 定义 `AIChatViewModel`（状态、动作、依赖注入）、`ChatContextProvider`、`ChatHistoryService`。
   - 将现有 UI 中的状态迁移，保留编译通过（回滚点：保留旧 `AIChatSidebarView` 分支）。
2. 模块控制器与上下文格式化：
   - 为 General/Script/Storyboard/Imaging 定义 controller 协议/实现，封装上下文、系统提示、回填逻辑。
   - 抽离 `makeProjectContext` 等长函数至 `ChatContextFormatter`；VM 通过 controller 获取字段。
3. 历史/记忆服务与 UI：
   - 把 `chatThreads` 读写、排序、命名放入 `ChatHistoryService`；History Sheet 改由服务提供数据源。
   - 验证记忆开关逻辑、线程切换恢复。
4. 模块交互验证：
   - 剧本总结按钮、分镜“生成分镜”、影像文生图确保通过 controller 调用；历史/附件/流式均正常。
   - 记录 Evidence Block，准备 Reflect（若有失败）。

Verification Plan (by AC):
- AC1：检查 `AIChatSidebarView` 仅绑定 ViewModel 状态；新增单元（或构建日志）证明编译通过。
- AC2：在剧本/分镜/影像模块触发协同操作，确认注入/通知链路日志；控制台输出中包含模块标记。
- AC3：执行文本对话 + 项目总结 + 影像生成，确认流式输出、路由/模型标注与设置一致（控制台日志）。
- AC4：开启记忆后切换多条历史记录，截图或日志证实历史列表包含所有线程并可加载。

Rollback Points:
- 每完成一个 Work Breakdown 子任务前保留分支标签；若某阶段失败，可回退至最近的稳定提交。
- 保留旧 `AIChatSidebarView` 实现文件副本（或 Git 分支）直到新 ViewModel 验证通过。
