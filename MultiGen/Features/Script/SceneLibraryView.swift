import SwiftUI
import AppKit

struct SceneLibraryView: View {
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var navigationStore: NavigationStore
    @State private var selectedProjectID: UUID?
    @State private var statusMessage: String?
    @State private var viewMode: LibraryViewMode = .grid
    @State private var selectedSceneID: UUID?

    private var projects: [ScriptProject] {
        scriptStore.projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var scenes: [ProjectSceneProfile] {
        guard let projectID = selectedProjectID else { return [] }
        return scriptStore.project(id: projectID)?.keyScenes ?? []
    }

    var body: some View {
        Group {
            if let projectID = selectedProjectID, let selectedID = selectedSceneID, let scene = scenes.first(where: { $0.id == selectedID }) {
                SceneDetailPage(
                    projectID: projectID,
                    scene: scene,
                    onBack: {
                        selectedSceneID = nil
                        navigationStore.currentLibrarySceneID = nil
                    },
                    onNavigate: { offset in navigateScene(offset: offset) },
                    onSave: saveScene,
                    onRequestPrompt: { requestPrompt(for: $0, projectID: projectID) }
                )
                .onAppear { navigationStore.currentLibrarySceneID = selectedID }
            } else {
                listPage
                    .padding(16)
            }
        }
        .navigationTitle("场景资料库")
        .toolbar { listToolbar }
        .overlay(alignment: .bottomLeading) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(12)
            }
        }
    }

    private var projectPicker: some View {
        Picker("项目", selection: $selectedProjectID) {
            ForEach(projects) { project in
                Text(project.title).tag(Optional(project.id))
            }
        }
        .frame(width: 240)
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = navigationStore.currentScriptProjectID ?? projects.first?.id
            }
            selectedSceneID = navigationStore.currentLibrarySceneID
        }
        .onChange(of: selectedProjectID) { _, _ in
            selectedSceneID = nil
            navigationStore.currentLibrarySceneID = nil
            navigationStore.currentScriptProjectID = selectedProjectID
        }
        .onChange(of: navigationStore.currentScriptProjectID) { _, newValue in
            selectedProjectID = newValue
        }
        .onChange(of: navigationStore.currentLibrarySceneID) { _, newValue in
            selectedSceneID = newValue
        }
    }

    @ViewBuilder
    private var listPage: some View {
        if scenes.isEmpty {
            AssetLibraryPlaceholderView(title: "暂无场景")
        } else {
            if viewMode == .grid {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 18) {
                        ForEach(scenes) { scene in
                            SceneCard(scene: scene) {
                                selectedSceneID = scene.id
                                navigationStore.currentLibrarySceneID = scene.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                List {
                    ForEach(scenes) { scene in
                        HStack {
                            Text(scene.name.isEmpty ? "未命名场景" : scene.name)
                                .font(.body.weight(.semibold))
                            Spacer()
                            Text(scene.prompt.isEmpty ? "无提示词" : "有提示词")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSceneID = scene.id
                            navigationStore.currentLibrarySceneID = scene.id
                        }
                    }
                    .onMove { indices, newOffset in
                        if let projectID = selectedProjectID {
                            scriptStore.reorderScenes(projectID: projectID, source: indices, destination: newOffset)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func addScene() {
        guard let projectID = selectedProjectID else { return }
        var scene = ProjectSceneProfile(name: "新场景")
        scene.variants = [SceneVariant()]
        scriptStore.updateProject(id: projectID) { editable in
            editable.keyScenes.append(scene)
        }
        selectedSceneID = scene.id
        navigationStore.currentLibrarySceneID = scene.id
    }

    private func saveScene(_ scene: ProjectSceneProfile, projectID: UUID) {
        scriptStore.updateProject(id: projectID) { editable in
            if let index = editable.keyScenes.firstIndex(where: { $0.id == scene.id }) {
                editable.keyScenes[index] = scene
            }
        }
        statusMessage = "场景已保存"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = nil }
    }

    private func requestPrompt(for scene: ProjectSceneProfile, projectID: UUID) {
        navigationStore.pendingPromptHelper = PromptHelperRequest(
            projectID: projectID,
            targetID: scene.id,
            target: .scene
        )
        navigationStore.currentScriptProjectID = projectID
        navigationStore.currentLibrarySceneID = scene.id
        navigationStore.sidebarMode = .ai
        statusMessage = "已提交到提示词助手，生成结果会自动写入"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusMessage = nil }
    }

    private func navigateScene(offset: Int) {
        guard let currentID = selectedSceneID,
              let idx = scenes.firstIndex(where: { $0.id == currentID }) else { return }
        let targetIndex = (idx + offset + scenes.count) % scenes.count
        selectedSceneID = scenes[targetIndex].id
        navigationStore.currentLibrarySceneID = selectedSceneID
    }

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        if selectedSceneID == nil {
            ToolbarItemGroup {
                projectPicker
                Picker("视图", selection: $viewMode) {
                    Text("卡片").tag(LibraryViewMode.grid)
                    Text("列表").tag(LibraryViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Button {
                    addScene()
                } label: {
                    Label("新增场景", systemImage: "plus")
                }
            }
        }
    }
}

private struct SceneDetailPage: View {
    let projectID: UUID
    let scene: ProjectSceneProfile
    let onBack: () -> Void
    let onNavigate: (Int) -> Void
    let onSave: (ProjectSceneProfile, UUID) -> Void
    let onRequestPrompt: (ProjectSceneProfile) -> Void

    @State private var draft: ProjectSceneProfile
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                infoSection
                promptSection
                variantsSection
            }
            .padding(16)
        }
        .navigationTitle(draft.name.isEmpty ? "未命名场景" : draft.name)
        .toolbar {
            ToolbarItemGroup {
                Button(action: onBack) {
                    Label("返回", systemImage: "chevron.backward")
                }
                Button {
                    onNavigate(-1)
                } label: {
                    Image(systemName: "arrow.left")
                }
                Button {
                    onNavigate(1)
                } label: {
                    Image(systemName: "arrow.right")
                }
                Spacer()
                Button {
                    onRequestPrompt(draft)
                } label: {
                    Label("生成提示词", systemImage: "sparkles")
                }
                .help("提交到提示词助手并自动写入当前场景提示词")

                Button {
                    if isEditing {
                        onSave(draft, projectID)
                    }
                    withAnimation { isEditing.toggle() }
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle" : "pencil")
                }
            }
        }
        .onChange(of: scene.id) { _, _ in
            draft = scene
            isEditing = false
        }
        .onChange(of: scene) { _, newValue in
            draft = newValue
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("基础信息")
                .font(.headline)
            if isEditing {
                TextField("名称", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                TextField("描述", text: $draft.description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(draft.name.isEmpty ? "未命名场景" : draft.name)
                    .font(.title3.bold())
                Text(draft.description.isEmpty ? "暂无描述" : draft.description)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("生成提示词")
                    .font(.headline)
                Spacer()
                if isEditing {
                    Button("AI 生成") {
                        onRequestPrompt(draft)
                    }
                }
            }
            if isEditing {
                TextEditor(text: $draft.prompt)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2))
                    )
            } else {
                Text(draft.prompt.isEmpty ? "暂无提示词" : draft.prompt)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )
            }
        }
        .padding(.horizontal, 2)
    }

    private var variantsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("视角与素材")
                .font(.headline)
            if isEditing {
                VariantEditor(variants: $draft.variants, isCharacter: false)
            } else {
                nonEditingVariants
            }
        }
    }

    private var nonEditingVariants: some View {
        Group {
            if draft.variants.isEmpty {
                Text("暂无视角")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    ForEach(draft.variants) { variant in
                        SceneVariantPanelView(variant: variant)
                    }
                }
            }
        }
    }

    init(
        projectID: UUID,
        scene: ProjectSceneProfile,
        onBack: @escaping () -> Void,
        onNavigate: @escaping (Int) -> Void,
        onSave: @escaping (ProjectSceneProfile, UUID) -> Void,
        onRequestPrompt: @escaping (ProjectSceneProfile) -> Void
    ) {
        self.projectID = projectID
        self.scene = scene
        self.onBack = onBack
        self.onNavigate = onNavigate
        self.onSave = onSave
        self.onRequestPrompt = onRequestPrompt
        _draft = State(initialValue: scene)
    }
}

private struct SceneVariantPanelView: View {
    let variant: SceneVariant

    private var coverImage: NSImage? {
        if let data = variant.images.first(where: { $0.isCover && $0.data != nil })?.data,
           let image = NSImage(data: data) {
            return image
        }
        if let data = variant.images.first(where: { $0.data != nil })?.data,
           let image = NSImage(data: data) {
            return image
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if let coverImage {
                    Image(nsImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [.black.opacity(0.05), .black.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.linearGradient(
                            colors: [.green.opacity(0.18), .teal.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(height: 160)
                        .overlay(
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(variant.label.isEmpty ? "未命名视角" : variant.label)
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        Label("\(variant.images.count) 张素材", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                        if variant.promptOverride.isEmpty == false {
                            Label("已生成提示词", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("视角提示词")
                    .font(.subheadline.weight(.semibold))
                Text(variant.promptOverride.isEmpty ? "暂无提示词" : variant.promptOverride)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if variant.images.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(variant.images) { image in
                            if let data = image.data, let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(image.isCover ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
        )
    }
}
