# Mission Brief — ImagingModule
Objective:
- 以剧本 → 分镜输出为基础，重新规划「影像」模块，聚焦单镜头粒度的 AI 影像创作与审阅体验。
- 在 UI 层提供「选择镜头 → 配置人物/场景/融合 → 生成 → 审核/归档」的明确流程，并与分镜条目互通。
- 首期版本只面向文本/图像的 Gemini 官方线路（或 Relay），保证日志可追溯、提示词可复用。

Out-of-scope:
- 批量生成/并行队列、风格库/资产管理（后续再引入）。
- 多窗口/多项目并行操作。
- 自定义模型或多提供商切换（沿用 Settings 中的全球配置）。

Inputs / Outputs (contracts):
- 输入：选中的 `StoryboardEntry`、Prompt Template 字段（人物/场景/溶图）、参考素材（角色图/场景图/外部图片 URL）、用户自定义备注。
- 输出：`ImagingJob`（描述操作类型、模型、提示词、素材引用、状态）、生成结果（图像 URL/base64、元数据）、与分镜条目的回链（记录所用成果）。
- 与分镜关系：Imaging Job 可回填到 `StoryboardEntry` 的 `aiPrompt`/附件列表，并在分镜审阅卡片中展示。

Acceptance Criteria (AC):
1. 影像模块提供三大动作：人物、场景、溶图，并且一次只针对一个镜头生成一张图；每次生成都记录 job 与审计信息。
2. 支持从分镜列表快速切换镜头，影像面板需清楚展示当前镜头的关键信息（镜号、画面摘要、提示词草稿）。
3. 每个动作提供模板化字段（与剧本/分镜层面不同），支持插入参考图（拖放/选择）并在请求中编码。
4. 生成结果以卡片形式展示，可设为分镜附件或 Base Image，并允许回看请求详情（提示词 + 素材）。
5. 所有生成操作写入审计日志（模型、耗时、素材引用、来源镜头），并在 Settings→Log 中可导出。

Constraints (perf/i18n/a11y/privacy):
- 仅 macOS；界面需遵循 macOS 26 风格，Inspector/卡片支持深色。
- 请求时不得上传未授权素材；引用本地文件需得到用户确认并缓存至沙箱。
- VoiceOver 需可朗读每张结果卡片的标题与操作按钮。

Dependencies & Risks:
- 依赖 Settings 中的 Gemini API Key/Relay；若 Key 缺失需在影像模块内提示前往设置。
- 图像 Base64 体积可能大，需要限制尺寸或先压缩再请求。
- 模板尚未定版，需与分镜/剧本模块沟通字段命名与提示词复用策略。

Platform Differences via Platform Layer:
- 当前仅 macOS：引用 `NSOpenPanel`/Drag&Drop；未来若扩展到 iPadOS，需使用 Platform 层抽象素材导入与文件权限。
