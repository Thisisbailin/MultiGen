# Mission Brief — IntelligentCollaboration
Objective:
- 统一侧边栏「智能协同」体验，提供一个可在所有模块调用的 AI 协作入口，遵循 macOS 26 的纯聊天布局与极简交互。
- 通过 Prompt Library 将各模块的系统提示词暴露给用户，并在聊天时按上下文自动附加，实现「设置 / 指令 / 剧本 / 分镜 / 通用聊天」五类需求的差异化输出。
- 让当前页面（项目、剧集、镜头等）的关键信息在不复制 UI 的前提下被推送给 AI，减少重复输入。

Out-of-scope:
- 影像（AIGC 渲染）工作流的提示词与上下文透传。
- 多模型/多线路动态切换 UI（保留设置模块作为唯一入口）。
- 智能协同直接触发写入操作（目前只提供建议/草稿，不落地到文件）。

Inputs / Outputs (contracts):
- 输入：用户纯文本消息；可选附带当前模块上下文（剧集文本、分镜表、设置参数预览等）以及 Prompt Library 中该模块的系统提示词。
- 输出：中转模型响应文本；若模块定义了结构化返回（如分镜表格），在智能协同中只展示摘要文本，并由对应模块处理结构化结果。
- Prompt Library 通过 `prompt-library.json` 存储键值：`{moduleKey: PromptEntry}`，供智能协同/模块 Store 拉取。

Acceptance Criteria (AC):
1. 侧边栏顶部的模式控制在「项目 / 智能协同」间切换，并且智能协同聊天面板完全嵌入侧边栏区域。
2. 智能协同默认不附加系统提示词，用户可在指令库（模块=GeneralChat）中新增后即时生效。
3. 当用户在剧本/分镜模块中打开某项目或剧集时，智能协同可以一键引用当前上下文并附加对应模块提示词（若存在）。
4. 所有与模型请求相关的提示词均通过 Prompt Library 定义；设置和智能协同内部不再硬编码任何 system prompt。
5. 设计文档同步描述以上交互、数据流与约束，方便后续 PEV 循环追踪。

Constraints (perf/i18n/a11y/privacy):
- 仅 macOS 目标；遵守 macOS 26 设计语言，侧边栏与主区域之间不使用额外分隔线。
- 不持久化用户与模型的对话记录（避免隐私风险）；本地仅保存提示词。
- 无网络代理/证书回退逻辑，依赖用户系统设置；需要优雅处理 TLS/网络错误。
- UI 需支持中文/英文提示词与输出；遵循 VoiceOver 可访问性（ariaLabel/label）。

Dependencies & Risks:
- 依赖 Settings 模块提供的中转 API Key、模型配置；如果配置缺失，智能协同需提示用户前往设置。
- Prompt Library 的 JSON 结构变化会影响所有模块，需在 Schema 更新时写迁移脚本。
- 上下文推送的性能风险：大篇幅剧本文本可能导致请求过大，需要在设计中定义截断/摘要策略。
- 若 Prompt Library 条目被删除，模块需回退到「无系统提示词」而不是崩溃。

Platform Differences via Platform Layer:
- 当前仅支持 macOS；若未来拓展至 iPadOS/iOS，需将智能协同重构为可折叠面板或独立窗口，通过 Platform 层暴露统一接口。
