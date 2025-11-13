# Plan — SceneComposer
Architecture Intent Block：
- 仅面向 macOS，但仍保持 Domain → Data → Features → UI 分层，便于未来演进。
- UI 不采用固定三栏，而是“内容区 + 浮动素材抽屉 + Inspector 面板”模式，利用 Toolbar 与 Sidebar 的原生交互。
- Feature 层通过协议依赖 `GeminiServiceProtocol`、`CredentialsStoreProtocol`、`AuditRepositoryProtocol`；Platform 层提供 macOS 实现与 Mock。
- 所有生成/审计行为都可溯源，应用首启展示“痛点说明”视图（Feature 状态控制显示）。

Work Breakdown（≤1 天）：
1. Domain 模型与痛点文案：定义 `Asset`、`PromptTemplate`、`SceneJob`、`AuditLogEntry` 及“痛点说明”数据结构；准备 AIGC 场景创作难点列表供 UI 显示。回滚：保留模型草稿 + TODO。
2. Data/Platform 服务：实现 SwiftData 存储、模板配置加载、Keychain 凭证和 Gemini/Mock 客户端。回滚：仅保留 Mock 客户端与内存 Key。
3. Feature 状态机：集中管理素材抽屉、选项 Inspector、结果历史、痛点说明显示逻辑。回滚：保持静态示例数据。
4. macOS UI 框架：搭建主窗口（Toolbar、Sidebar/Inspector 切换、内容画布），实现素材导入/编辑/结果显示的基础交互。回滚：线框预览 + 截图。
5. 设置视图与 API Key 流程：实现 `⌘,` 打开设置、Key 输入校验、Mock 切换；无 Key 时禁用生成按钮。回滚：以占位提示阻断生成。
6. 审计/日志：将生成请求写入 SwiftData，提供历史面板和导出；在 `docs/Testing/` 记录验证输出。回滚：控制台日志 + TODO。

Verification Plan（按 AC 对应）：
- AC1：UI Snapshot/交互清单，确认素材抽屉、Inspector、结果区域能互通；编译 macOS target。
- AC2：Prompt Template 单测覆盖六类选项；Feature 状态改变测试。
- AC3：设置流程集成测试，模拟 Keychain 读写；无 Key 时自动阻断。
- AC4：对 Gemini 请求进行 Mock 验证，记录日志文件。
- AC5：痛点说明显示测试（状态驱动）、审计日志持久化与导出脚本输出，存入 `docs/Testing/scene-job-log.md`。

Rollback Points：
- Gemini 不可用：切换 Mock 客户端、UI 显示离线提示。
- Keychain 权限失败：启用内存级凭证并提醒用户修复。
- UI 性能不足：可关闭 Inspector/素材抽屉，改为分步流程但保留数据结构。
