import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CharacterLibraryView: View {
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var navigationStore: NavigationStore
    @State private var selectedProjectID: UUID?
    @State private var statusMessage: String?
    @State private var viewMode: LibraryViewMode = .grid
    @State private var selectedCharacterID: UUID?

    private var projects: [ScriptProject] {
        scriptStore.projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var characters: [ProjectCharacterProfile] {
        guard let projectID = selectedProjectID else { return [] }
        return scriptStore.project(id: projectID)?.mainCharacters ?? []
    }

    var body: some View {
        Group {
            if let projectID = selectedProjectID, let selectedID = selectedCharacterID, let character = characters.first(where: { $0.id == selectedID }) {
        CharacterDetailPage(
            projectID: projectID,
            character: character,
            onBack: {
                selectedCharacterID = nil
                navigationStore.currentLibraryCharacterID = nil
            },
            onNavigate: { offset in navigateCharacter(offset: offset) },
            onSave: saveCharacter,
            onRequestPrompt: { requestPrompt(for: $0, projectID: projectID) }
        )
        .onAppear { navigationStore.currentLibraryCharacterID = selectedID }
            } else {
                listPage
                    .padding(16)
            }
        }
        .navigationTitle("角色资料库")
        .toolbar { listToolbar }
        .overlay(alignment: .bottomLeading) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                    )
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
            selectedCharacterID = navigationStore.currentLibraryCharacterID
        }
        .onChange(of: selectedProjectID) { _, _ in
            selectedCharacterID = nil
            navigationStore.currentLibraryCharacterID = nil
            navigationStore.currentScriptProjectID = selectedProjectID
        }
        .onChange(of: navigationStore.currentScriptProjectID) { _, newValue in
            selectedProjectID = newValue
        }
        .onChange(of: navigationStore.currentLibraryCharacterID) { _, newValue in
            selectedCharacterID = newValue
        }
    }

    @ViewBuilder
    private var listPage: some View {
        if characters.isEmpty {
            AssetLibraryPlaceholderView(title: "暂无角色")
        } else {
            if viewMode == .grid {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 18) {
                        ForEach(characters) { character in
                            PersonaCard(character: character) {
                                selectedCharacterID = character.id
                                navigationStore.currentLibraryCharacterID = character.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                List {
                    ForEach(characters) { character in
                        HStack {
                            Text(character.name.isEmpty ? "未命名角色" : character.name)
                                .font(.body.weight(.semibold))
                            Spacer()
                            Text(character.prompt.isEmpty ? "无提示词" : "有提示词")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCharacterID = character.id
                            navigationStore.currentLibraryCharacterID = character.id
                        }
                    }
                    .onMove { indices, newOffset in
                        if let projectID = selectedProjectID {
                            scriptStore.reorderCharacters(projectID: projectID, source: indices, destination: newOffset)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func addCharacter() {
        guard let projectID = selectedProjectID else { return }
        var new = ProjectCharacterProfile(name: "新角色")
        new.variants = [CharacterVariant()]
        scriptStore.updateProject(id: projectID) { editable in
            editable.mainCharacters.append(new)
        }
        selectedCharacterID = new.id
        navigationStore.currentLibraryCharacterID = new.id
    }

    private func saveCharacter(_ character: ProjectCharacterProfile, projectID: UUID) {
        scriptStore.updateProject(id: projectID) { editable in
            if let index = editable.mainCharacters.firstIndex(where: { $0.id == character.id }) {
                editable.mainCharacters[index] = character
            }
        }
        statusMessage = "角色已保存"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = nil }
    }

    private func requestPrompt(for character: ProjectCharacterProfile, projectID: UUID) {
        navigationStore.pendingPromptHelper = PromptHelperRequest(
            projectID: projectID,
            targetID: character.id,
            target: .character
        )
        navigationStore.currentScriptProjectID = projectID
        navigationStore.currentLibraryCharacterID = character.id
        navigationStore.sidebarMode = .ai
        statusMessage = "已提交到提示词助手，生成结果会自动写入"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusMessage = nil }
    }

    private func navigateCharacter(offset: Int) {
        guard let currentID = selectedCharacterID,
              let idx = characters.firstIndex(where: { $0.id == currentID }) else { return }
        let targetIndex = (idx + offset + characters.count) % characters.count
        selectedCharacterID = characters[targetIndex].id
        navigationStore.currentLibraryCharacterID = selectedCharacterID
    }

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        if selectedCharacterID == nil {
            ToolbarItemGroup {
                projectPicker
                Picker("视图", selection: $viewMode) {
                    Text("卡片").tag(LibraryViewMode.grid)
                    Text("列表").tag(LibraryViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Button {
                    addCharacter()
                } label: {
                    Label("新增角色", systemImage: "plus")
                }
            }
        }
    }
}

private struct CharacterDetailPage: View {
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var navigationStore: NavigationStore

    let projectID: UUID
    let character: ProjectCharacterProfile
    let onBack: () -> Void
    let onNavigate: (Int) -> Void
    let onSave: (ProjectCharacterProfile, UUID) -> Void
    let onRequestPrompt: (ProjectCharacterProfile) -> Void

    @State private var draft: ProjectCharacterProfile
    @State private var isEditing = false
    @State private var variantIndex = 0

    init(
        projectID: UUID,
        character: ProjectCharacterProfile,
        onBack: @escaping () -> Void,
        onNavigate: @escaping (Int) -> Void,
        onSave: @escaping (ProjectCharacterProfile, UUID) -> Void,
        onRequestPrompt: @escaping (ProjectCharacterProfile) -> Void
    ) {
        self.projectID = projectID
        self.character = character
        self.onBack = onBack
        self.onNavigate = onNavigate
        self.onSave = onSave
        self.onRequestPrompt = onRequestPrompt
        _draft = State(initialValue: character)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                infoSection
                variantsSection
                occurrencesSection
            }
            .padding(16)
        }
        .navigationTitle(draft.name.isEmpty ? "未命名角色" : draft.name)
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
                .help("提交到提示词助手并自动写入当前角色提示词")

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
        .onChange(of: character.id) { _, _ in
            draft = character
            isEditing = false
            variantIndex = 0
        }
        .onChange(of: character) { _, newValue in
            draft = newValue
            variantIndex = 0
        }
        .onChange(of: draft.variants.count) { _, _ in
            clampVariantIndex()
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditing {
                TextField("名称", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                TextField("描述", text: $draft.description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(draft.description.isEmpty ? "暂无描述" : draft.description)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var variantsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("形态与素材")
                .font(.headline)
            if isEditing {
                if let binding = currentVariantBinding {
                    ZStack(alignment: .topTrailing) {
                        SingleVariantEditor(variant: binding)
                        if draft.variants.count > 1 {
                            HStack(spacing: 8) {
                                Button {
                                    withAnimation { variantIndex = (variantIndex - 1 + draft.variants.count) % draft.variants.count }
                                } label: { Image(systemName: "chevron.left.circle.fill") }
                                    .buttonStyle(.plain)
                                Button {
                                    withAnimation { variantIndex = (variantIndex + 1) % draft.variants.count }
                                } label: { Image(systemName: "chevron.right.circle.fill") }
                                    .buttonStyle(.plain)
                            }
                            .padding(6)
                        }
                    }
                } else {
                    Text("暂无形态")
                        .foregroundStyle(.secondary)
                }
            } else {
                nonEditingVariants
            }
        }
    }

    private var nonEditingVariants: some View {
        Group {
            if draft.variants.isEmpty {
                Text("暂无形态")
                    .foregroundStyle(.secondary)
            } else {
                if let variant = currentVariant {
                    ZStack(alignment: .topTrailing) {
                        VariantPanelView(variant: variant)
                        if draft.variants.count > 1 {
                            HStack(spacing: 8) {
                                Button {
                                    withAnimation { variantIndex = (variantIndex - 1 + draft.variants.count) % draft.variants.count }
                                } label: {
                                    Image(systemName: "chevron.left.circle.fill")
                                }
                                .buttonStyle(.plain)
                                Button {
                                    withAnimation { variantIndex = (variantIndex + 1) % draft.variants.count }
                                } label: {
                                    Image(systemName: "chevron.right.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                        }
                    }
                }
            }
        }
    }

    private var occurrencesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("剧集匹配")
                .font(.headline)
            if occurrences.isEmpty {
                Text(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "请输入角色名称以匹配原文" : "原文中未找到角色名匹配。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(occurrences, id: \.episode.id) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.episode.displayLabel)
                                .font(.subheadline.bold())
                            Text("出现 \(entry.count) 次")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            jumpToEpisode(entry.episode)
                        } label: {
                            Label("跳转", systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                    Divider()
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var occurrences: [(episode: ScriptEpisode, count: Int)] {
        guard let project = scriptStore.projects.first(where: { $0.id == projectID }) else { return [] }
        let keyword = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else { return [] }
        let episodes = project.orderedEpisodes
        var matches: [(ScriptEpisode, Int)] = []
        for ep in episodes {
            let count = countOccurrences(of: keyword, in: ep.markdown)
            if count > 0 {
                matches.append((ep, count))
            }
        }
        return matches
    }

    private func countOccurrences(of keyword: String, in text: String) -> Int {
        guard keyword.isEmpty == false else { return 0 }
        let components = text.components(separatedBy: keyword)
        return max(0, components.count - 1)
    }

    private func jumpToEpisode(_ episode: ScriptEpisode) {
        navigationStore.currentScriptEpisodeID = episode.id
        navigationStore.currentScriptProjectID = projectID
        navigationStore.selection = .script
        navigationStore.columnVisibility = .all
    }

    private func clampVariantIndex() {
        guard draft.variants.isEmpty == false else { variantIndex = 0; return }
        if variantIndex >= draft.variants.count {
            variantIndex = draft.variants.count - 1
        }
    }

    private var currentVariant: CharacterVariant? {
        guard draft.variants.indices.contains(variantIndex) else { return nil }
        return draft.variants[variantIndex]
    }

    private var currentVariantBinding: Binding<CharacterVariant>? {
        guard draft.variants.indices.contains(variantIndex) else { return nil }
        return Binding(
            get: { draft.variants[variantIndex] },
            set: { draft.variants[variantIndex] = $0 }
        )
    }
}

private struct VariantPanelView: View {
    let variant: CharacterVariant

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
            if let coverImage {
                Image(nsImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(12)
            }
            HStack {
                Text(variant.label.isEmpty ? "未命名形态" : variant.label)
                    .font(.headline)
                Spacer()
                if variant.promptOverride.isEmpty == false {
                    Label("已生成提示词", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(variant.promptOverride.isEmpty ? "暂无提示词（形态级）" : variant.promptOverride)
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
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 4)
        )
    }
}

private struct SingleVariantEditor: View {
    @Binding var variant: CharacterVariant
    @State private var pickerIsRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("形态标签", text: $variant.label)
                .textFieldStyle(.roundedBorder)
            TextField("形态提示词", text: $variant.promptOverride, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        pickImage { data in
                            guard let data else { return }
                            var images = variant.images
                            images.insert(CharacterImage(id: UUID(), data: data, isCover: true), at: 0)
                            images = updateCoverState(images)
                            variant.images = images
                        }
                    } label: {
                        Label("上传素材", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    ForEach(Array(variant.images.enumerated()), id: \.element.id) { index, image in
                        ZStack(alignment: .topTrailing) {
                            if let data = image.data, let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(image.isCover ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.3))
                                    .frame(width: 90, height: 90)
                                    .overlay(Image(systemName: "photo"))
                            }
                            HStack(spacing: 6) {
                                Button {
                                    var images = variant.images
                                    images = updateCoverState(setCoverAt: index, in: images)
                                    variant.images = images
                                } label: {
                                    Image(systemName: image.isCover ? "star.fill" : "star")
                                        .font(.caption)
                                        .foregroundStyle(image.isCover ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    var images = variant.images
                                    images.remove(at: index)
                                    variant.images = updateCoverState(images)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(6)
                        }
                    }
                }
            }
        }
    }

    private func pickImage(_ handler: @escaping (Data?) -> Void) {
        guard pickerIsRunning == false else { return }
        pickerIsRunning = true
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            handler(data)
        }
        pickerIsRunning = false
    }

    private func updateCoverState(_ images: [CharacterImage]) -> [CharacterImage] {
        guard images.isEmpty == false else { return images }
        var updated = images
        for idx in updated.indices {
            updated[idx].isCover = idx == 0
        }
        return updated
    }

    private func updateCoverState(setCoverAt index: Int, in images: [CharacterImage]) -> [CharacterImage] {
        guard images.indices.contains(index) else { return images }
        var updated = images
        for idx in updated.indices {
            updated[idx].isCover = idx == index
        }
        return updated
    }
}
