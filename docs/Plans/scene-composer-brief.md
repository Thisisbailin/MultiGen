# Mission Brief — SceneComposer
目标（Objective）：
- 交付仅面向 macOS 的 AIGC 场景编排工具，聚焦本地素材管理、模板化提示配置与 Gemini 生成链路。
- 在应用内通过原生弹窗/首启引导解释项目针对的创作痛点，帮助用户快速理解价值。
- 采用 Apple 原生设计语言（Large Title + Toolbar + Inspector 模式）完成基础架构搭建，为后续 UI 精细化迭代奠定基础。

不在范围内（Out-of-scope）：
- iOS/iPadOS 版本及跨平台适配；不引入第三方 UI 套件。
- 复杂图像编辑、3D 建模或多模型切换（仅支持 Gemini）。

输入 / 输出（数据契约）：
- 输入：本地图片引用（URL/ID）、六类场景选项对应的模板字段、用户自定义描述、Gemini API Key（Keychain 持久化）、生成命令。
- 输出：结构化 prompt（JSON + 文本），Gemini 任务状态、生成结果图像元数据、审计日志以及应用内“痛点说明”内容。

验收准则（AC）：
1. 提供素材区、编辑选项区、结果区的基本交互（可通过分段视图/Inspector 而非三栏固定布局实现）。
2. 六类场景相关选项具备预设模板，并支持用户调整字段。
3. 设置页面允许输入/更新/清除 Gemini API Key（Keychain 存储），Key 缺失时禁用生成操作。
4. 架设 Prompt Orchestrator，可在 Key 有效时向 Gemini 发送请求，另含 Mock 模式。
5. 在应用内提供“痛点与场景”说明（例如首启弹窗或帮助面板），列出 AIGC 场景创作的主要难点，并可在文档中复述；生成操作必须写入审计记录。

约束（性能/隐私/可访问性）：
- 仅支持 macOS 14+，SwiftUI + SwiftData + 并发；主要交互需 <150ms，长任务显示异步状态。
- API Key 仅存 Keychain；上传本地图像需用户确认。
- 文案支持本地化，占位文本默认中文；主要控件配置 VoiceOver label。

依赖与风险：
- Gemini API 可用性与速率限制；需退避与 Mock。
- Keychain 权限可能受限；需兜底方案。
- 大图上传或多素材解析导致性能问题；需要缩略图缓存与后台处理。

平台差异（Platform Layer）：
- 当前仅实现 macOS 适配：文件导入（`NSOpenPanel`）、Toolbar/Inspector、菜单 & 快捷键。
- 抽象 `GeminiServiceProtocol`、`SecureCredentialsStoreProtocol` 以便未来扩展，但本迭代无需实现其它平台版本。
