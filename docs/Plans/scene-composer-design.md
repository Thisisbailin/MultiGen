# SceneComposer 设计方案（macOS 专用）

## AIGC 场景创作现状与痛点
1. **提示链条割裂**：场景搭建、细节补充、视角切换、角色塑造通常散落在不同对话或文档中，难以复用与回溯。
2. **素材-提示脱节**：创作者需要频繁参考本地图片/角色设定，但当前主流网页工具缺少原生拖放、版本管理与引用追踪。
3. **协作与审计困难**：团队难以知道一张图对应的提示、素材、模型参数，导致复现成本高。
4. **Key 管理混乱**：Gemini API Key 多以纯文本方式共享，存在泄露与过期风险，也阻碍企业级使用。
5. **场景视角/角色变体成本高**：每次变换都需重写大段提示，且缺少可视化方式理解改动。

> 应用要求在首启/帮助面板中展示上述痛点说明，并解释 SceneComposer 的解决策略，帮助用户快速定位价值。

## 产品定位与场景
- 面向需要快速进行多版本场景合成的视觉创作者、导演、广告/品牌团队。
- 典型流程：导入参考素材 → 选择模板（如“场景细节”或“人物与场景融合”）→ 调整提示字段 → 触发生成 → 查看/复用结果，同时可在帮助面板查看痛点说明与流程指引。

## UI 设计原则（遵循 Apple 原生案例）
- **主窗口 + 工具栏**：采用 Large Title + Toolbar（含素材抽屉、Inspector、生成按钮、帮助按钮）。
- **内容画布优先**：中央为“创作画布”，显示当前参考图、提示摘要与预览。
- **素材抽屉（Drawer Panel）**：通过 Toolbar 按钮或快捷键展开，从窗口底部或侧面滑出，列出图片素材网格，可拖拽到画布或模板字段。
- **Inspector 面板**：位于窗口右侧，可显示/隐藏，内含六类编辑选项（以折叠面板或分段控制呈现），每个选项展示对应字段。避免固定三栏布局，而是让 Inspector 作为可收起的原生侧面板。
- **结果侧滑区**：生成后在画布下方以“结果堆栈”形式呈现卡片，支持展开查看详情、复制提示、导出。
- **帮助/痛点说明面板**：Toolbar 中的 “Pain Points” 图标打开模态或 Popover，解释 AIGC 难点与应用如何缓解，可随时访问。

## 信息架构与交互
为承接“剧本 → 分镜脚本 → AIGC 视觉输出”链路，引入四个侧边栏分区：
1. **主页（Home）**：延续痛点说明与平台自检组件，展示当前模式、API Key 状态、近期生成记录。
2. **剧本（Script）**：提供剧本文本蓝本区域，左侧章节/场次列表，右侧正文编辑/预览；支持导入、粘贴、段落标记（角色、场景、情绪），并可将段落指派给分镜条目。
3. **分镜脚本（Storyboard）**：作为剧本与视觉之间的中介，记录镜头编号、引用的剧本段落、镜头描述、视觉意图、角色需求、素材参考等；采用列表 + Inspector 布局，可直接跳转到 AIGC 创作或触发预设模板。
4. **AIGC 创作（Create）**：整合素材抽屉、编辑选项、结果堆栈；根据选中的分镜条目自动预填提示字段，用户可切换“文本生成”与“图像生成”按钮（分别调用 `generateContent` / `generateImages`），生成结果回写到分镜条目并写入审计日志。

**设置视图** 仍通过菜单/toolbar 打开，包含 API Key 输入（Keychain）、文本/图像模型选择、Mock 切换、日志导出入口。

## 交互流程
1. **首启体验**：用户在 Home 查看痛点与自检状态，按提示进入设置页输入 API Key；若跳过则进入 Mock 模式。
2. **剧本导入/编辑**：在 Script 视图导入剧本文本或粘贴原稿，按章节浏览和标注，为分镜创建“待视觉化”任务。
3. **分镜脚本创建**：在 Storyboard 创建镜头条目，引用剧本段落、填写镜头语言/视觉意图并附加素材参考，可直接触发 Create 视图。
4. **AIGC 创作**：Create 视图读取分镜上下文并填充模板字段，用户可根据需要分别触发文本生成或图像生成；结果卡片记录模型、耗时，并回写分镜条目。
5. **审计与导出**：按分镜/剧本段落查看历史记录，导出日志或复制提示；设置视图可切换模型、导出日志、切换 Mock。

## 数据与提示模型
- `PainPoint`：`id`, `title`, `detail`, `solution`
- `ScriptSection`：`id`, `title`, `text`, `order`, `tags`, `characters`
- `StoryboardItem`：`id`, `scriptSectionID`, `sequence`, `cameraNotes`, `visualIntent`, `linkedAssets`, `status`, `lastGeneratedJobID`
- `Asset`：`id`, `fileURL`, `thumbnail`, `tags`, `usageRole`, `createdAt`
- `PromptTemplate`：`id`, `category`, `fields[]`（字段名、类型、默认值、枚举、权重）
- `PromptInstance`：模板 + 用户输入 + `assetRefs`
- `SceneJob`：`id`, `channel`（text/image）, `actionType`, `promptInstance`, `status`, `resultMedia`, `error`, `timestamps`
- `AuditLogEntry`：`jobId`, `promptHash`, `assetRefs`, `modelVersion`, `duration`, `channel`, `createdAt`

## 技术架构
```
App (macOS)
└─ Packages
   ├─ Domain        // 模型、模板、剧本/分镜结构、痛点文案、校验
   ├─ Data          // SwiftData 仓储、剧本/分镜/模板配置、审计仓储
   ├─ Platform      // Gemini 文本/图像客户端、Keychain、文件导入
   ├─ Features
   │   ├─ HomeFeature（痛点说明、自检）
   │   ├─ ScriptFeature（剧本导入/编辑、注释）
   │   ├─ StoryboardFeature（分镜条目、镜头 Inspector、与 AIGC 绑定）
   │   ├─ CreateFeature（AIGC 工作区、文本/图像双通道、结果堆栈）
   │   └─ SettingsFeature
   └─ UIComponents  // 侧边栏布局、脚本/分镜卡片、素材抽屉、结果卡、痛点面板
```
- Feature 层借助 `@Observable` store + reducers，使用 `Task` 运行 Gemini 调用。
- Prompt Orchestrator 在 Domain 层实现，确保模板→payload 可单测。

## Gemini 集成
- 双通道架构：文本生成使用 `models/gemini-2.5-flash:generateContent`，图像生成使用 `models/gemini-2.5-flash-image-preview:generateImages`；用户可在设置页分别选择默认模型。
- 请求封装：文本通道拼接剧本/分镜上下文，使用单 `user` 消息描述结构化字段；图像通道直接提交自然语言 prompt，并接收 base64/URL。
- Mock 模式：在无 Key 或开发阶段以静态响应替代，并在 UI 中提示“Mock”状态。
- 错误处理：401/403（Key 失效）提示用户前往设置，429/5xx 采用指数退避并记录审计日志；所有请求在控制台输出状态码和错误 payload，便于排查。

## API Key 管理
- 设置窗口通过 `Form + SecureField` 输入 Key，保存前做格式校验；写入 Keychain，成功后展示“已验证”状态。
- 提供“测试连接”“清除 Key”“切换 Mock”操作；Keychain 读取失败时提供修复指引。

## 审计 & 观测
- SwiftData 存 AuditLogEntry，生成完成后写入 prompt hash、资源引用、耗时。
- Toolbar 中提供“导出日志”入口；`docs/Testing/` 存放构建/测试记录和示例日志。

## 无障碍 & 视觉
- 支持深浅色自动切换；采用系统材料（Sidebar/Inspector 样式）。
- 所有按钮和模板字段配置 VoiceOver label；结果卡支持键盘导航。
- 快捷键：`⌘O` 素材、`⌘G` 生成、`⌘,` 设置、`⌘0` 打开痛点说明。

## 风险与缓解
| 风险 | 影响 | 对策 |
| --- | --- | --- |
| Gemini 限流/变更 | 无法生成 | Mock 模式 + 模型选择 + 重试策略 |
| Keychain 受限 | Key 不可用 | 会话级临时存储 + 引导用户授权 |
| 大量素材导致 UI 卡顿 | 体验差 | 缩略图缓存、分页加载 |
| 痛点说明内容与实际体验脱节 | 用户困惑 | 定期回访创作者，迭代文案并在 app 中支持远程配置 |

## 里程碑
1. **M1**：扩展 Domain/Data（ScriptSection、StoryboardItem、SceneJobChannel、文本/图像模型配置）并更新模板、痛点文案。
2. **M2**：Platform 层实现文本/图像双客户端、Keychain、模型切换与 Mock 适配，完善日志输出与错误诊断。
3. **M3**：实现 Home/Script/Storyboard/Create 四个侧边栏骨架，打通剧本导入、分镜管理与 AIGC 工作区联动。
4. **M4**：设置与审计、痛点说明优化、图像结果回写、测试与文档沉淀。
