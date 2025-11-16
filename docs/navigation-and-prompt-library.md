# Navigation & Prompt Library Update — 2025-02-14

## Objectives
- 将所有系统提示词集中暴露给用户，支持「分镜助手」「智能协作」模块自由定制。
- 优化侧边栏结构，使「项目 / 智能协作」切换符合 macOS 26 设计语言。

## 智能协同设计原则（节选）
1. **单一入口**：智能协同被视为侧边栏的一种模式，而非各模块内的局部功能；所有 AI 对话均在该模式下进行。
2. **Prompt Library 优先**：系统提示词完全来源于 `PromptLibraryStore`，默认空白，由用户自行定义；设置页与智能协同代码不再内置任何提示词。
3. **上下文抽象**：聊天逻辑仅关心「当前上下文」与「目标模块」两个维度。上下文由对应模块提供（如剧本选中剧集、分镜选中集/镜头），并可手动附加/剥离。
4. **macOS 26 视觉一致性**：侧边栏模式切换使用原生 segmented 样式，聊天面板与项目列表共用一块背景，无额外分隔线或工具栏开关。
5. **隐私与可回溯**：对话历史只保存在内存，系统提示词写入 `prompt-library.json`，满足 AGENTS.md 的证据化和可追溯要求。

### Prompt & Context Routing Matrix
| 当前页面 | Prompt 模块 | 上下文载荷 | 备注 |
| --- | --- | --- | --- |
| 主页 / 其它 | 主页聊天 (`.aiConsole`) | 无 | 默认空提示词，可在资料库中自定义。 |
| 剧本 | 剧本助手 (`.script`) | 选中剧集的 Markdown（最多 6000 字）+ 项目元数据 | `ScriptView` 将当前剧集 ID 写入 `NavigationStore.currentScriptEpisodeID`。 |
| 分镜 | 分镜助手 (`.storyboard`) | 剧本文本 + 当前场景正文（`sceneContext`）+ 现有分镜（前 12 镜） | `StoryboardView` 同步 episode/scene ID；若无分镜，仅携带剧本+场景上下文。 |

> `sceneContext` 包含“场景标题/序号/摘要/正文”，正文会在 3000 字截断，确保 Gemini 按场景理解而非整集平均。AI 必须复用剧本里已有的场景名称，分镜不会生成新的场景层级。
> 智能协作一次只处理当前选中的场景；当用户切换场景时，Sidebar 会自动刷新上下文并要求 AI 仅输出该场景的镜头数组（不返回额外的 sceneTitle）。

> 当页面未绑定自定义提示词时，系统会回退到主页聊天提示词，确保不会出现空引用。

### 状态同步
- `NavigationStore` 新增 `currentScriptEpisodeID` / `currentStoryboardEpisodeID`，分别由 `ScriptView` 与 `StoryboardView` 在切换剧集时更新，用于让智能协同无侵入地获取上下文。
- `NavigationStore` 现额外记录 `currentStoryboardSceneID` 与 `currentStoryboardSceneSnapshot`，`StoryboardView` 在切换场景或离开模块时同步；AI 面板借此拼装 `sceneContext`（只有来自剧本的场景会被纳入快照，避免出现 AI 私自新增场景）。
- Storyboard 模块的自动化仅在存在合法场景时生效；若剧本尚未添加场景，Sidebar 会提示用户先回到剧本模块拆分场景。
- `AIChatSidebarView` 根据上述 ID 动态选择 Prompt 模块、构造 `scriptContext` / `storyboardContext` 字段，并在界面上显示当前上下文状态（如“剧本 · 第2集”）。
- 为防止用户误改提示词导致结果异常，指令资料库提供「恢复默认」按钮，可针对单个模块回退到内置模板。
- 分镜上下文下的聊天窗会额外显示“分镜操作 · AI 结果会写入分镜表”的模式提示，明确这是自动落地的操作型请求；剧本/主页保持“文本建议/自由聊天”描述。
- `StoryboardView` 在出现时向 `NavigationStore` 注册自动化处理器：侧边栏的指令一旦返回 JSON，就会直接调用 `StoryboardDialogueStore.applySidebarAIResponse`，解析并写入分镜脚本。聊天流展示“写入成功/失败”摘要，并可折叠查看原始 JSON 以便调试解析问题。

## 实施内容
1. **提示词资料库**
   - 新增 `PromptLibraryStore` 持久化提示词。
   - 指令入口（侧边栏 → 资料库 → 指令）可查看/编辑提示词，保存后写入 `prompt-library.json`。
   - 分镜 / 智能协作在调用 Gemini 前读取各自提示词（为空则不附加 system prompt）。
   - 分镜模块的默认 system prompt 现参考 `docs/Script_to_Storyboard_Advanced_Principles.md`，强调视觉母题、色彩脚本、空间语法、摄影机/光影/剪辑等专业原则，确保 AI 输出接近导演级分镜。

2. **侧边栏与导航**
   - 侧栏顶部加入分段控制器，切换「项目」与「智能协作」模式；智能协作模式下嵌入聊天面板。
   - `NavigationStore` 统一管理选择状态与弹窗开关，减轻 `ContentView` 负担。

3. **附加修正**
   - `SceneAction` 新增 `.aiConsole`，主页仅展示 workflow actions。
   - SettingsView 的 `.onChange` 更新为 macOS 14 推荐 API。

## 后续计划
- 将 Create 模块的 PromptTemplate 也接入资料库。
- 在智能协作面板中加入“推送当前项目/剧集”的上下文按钮。
- 若需要多窗口或 Spotlight 支持，可在 NavigationStore 扩展最近访问记录。
