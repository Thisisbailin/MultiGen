import SwiftUI

struct ScriptOverviewView: View {
    @ObservedObject var store: ScriptStore
    let projects: [ScriptProject]
    let highlightedProject: ScriptProject?
    @Binding var highlightedProjectID: UUID?
    let onOpenProject: (ScriptProject) -> Void
    let onCreateProject: () -> Void
    let onImportProject: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                gallerySection
                highlightPanel
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
    }

    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if projects.isEmpty {
                ProjectSelectionPlaceholder(
                    title: "暂无剧本项目",
                    description: "点击下方按钮开始创建项目，或导入现有剧本。",
                    buttonTitle: "新建项目",
                    onCreate: onCreateProject
                )
                .frame(height: 220)
            } else {
                ProjectGalleryList(
                    projects: projects,
                    highlightedProjectID: $highlightedProjectID,
                    onOpen: onOpenProject
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("剧本项目")
                .font(.system(.largeTitle, weight: .bold))
            Text("以项目为单位管理集数与元信息，便于后续分镜和影像创作。")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var highlightPanel: some View {
        if let project = highlightedProject {
            ProjectInfoPanel(
                store: store,
                project: project,
                accentColor: Color(nsColor: .controlBackgroundColor)
            )
        } else {
            ProjectSelectionPlaceholder(
                title: "暂无剧本项目",
                description: "点击下方按钮开始创建项目，或导入现有剧本。",
                buttonTitle: "新建项目",
                onCreate: onCreateProject
            )
        }
    }
}

private let projectCardColor = Color(nsColor: .controlBackgroundColor)

struct ProjectSelectionPlaceholder: View {
    let title: String
    let description: String
    let buttonTitle: String
    let onCreate: () -> Void

    init(
        title: String = "请选择项目",
        description: String = "暂无选中的剧本项目，先在上方选择或创建一个项目。",
        buttonTitle: String = "新建项目",
        onCreate: @escaping () -> Void
    ) {
        self.title = title
        self.description = description
        self.buttonTitle = buttonTitle
        self.onCreate = onCreate
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title3.bold())
            Text(description)
                .foregroundStyle(.secondary)
            Button(action: onCreate) {
                Label(buttonTitle, systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct ProjectGalleryList: View {
    let projects: [ScriptProject]
    @Binding var highlightedProjectID: UUID?
    let onOpen: (ScriptProject) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(projects) { project in
                    ProjectCard(
                        project: project,
                        color: projectCardColor,
                        isSelected: project.id == highlightedProjectID,
                        onSelect: { highlightedProjectID = project.id },
                        onOpenDetail: { onOpen(project) }
                    )
                }
            }
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }
}

struct ProjectCard: View {
    let project: ScriptProject
    let color: Color
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(project.title)
                    .font(.headline)
                Spacer()
                Button(action: onOpenDetail) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("进入 \(project.title) 详情")
            }
            Text("\(project.type.displayName) · \(project.episodes.count) 集 · 更新 \(project.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if project.tags.isEmpty == false {
                HStack(spacing: 6) {
                    ForEach(project.tags.prefix(3), id: \.self) { tag in
                        ProjectTagPill(text: tag)
                    }
                }
            } else {
                Text("暂无标签")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 240, height: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture(perform: onSelect)
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 6)
    }
}

struct ProjectInfoPanel: View {
    @ObservedObject var store: ScriptStore
    let project: ScriptProject
    let accentColor: Color

    @State private var isEditing = false
    @State private var activePanel: PanelPage = .overview
    @State private var draftSynopsis: String = ""
    @State private var draftNotes: String = ""
    @State private var draftTags: [String] = []
    @State private var draftStartDate: Date? = nil
    @State private var draftEndDate: Date? = nil
    @State private var draftCharacters: [ProjectCharacterProfile] = []
    @State private var draftScenes: [ProjectSceneProfile] = []
    @State private var newTagDraft: String = ""

    init(store: ScriptStore, project: ScriptProject, accentColor: Color) {
        self.store = store
        self.project = project
        self.accentColor = accentColor
        _draftSynopsis = State(initialValue: project.synopsis)
        _draftNotes = State(initialValue: project.notes)
        _draftTags = State(initialValue: project.tags)
        _draftStartDate = State(initialValue: project.productionStartDate)
        _draftEndDate = State(initialValue: project.productionEndDate)
        _draftCharacters = State(initialValue: project.mainCharacters)
        _draftScenes = State(initialValue: project.keyScenes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlStrip
            cardContainer {
                switch activePanel {
                case .overview:
                    if isEditing { overviewEditingContent } else { overviewDisplayContent }
                case .assets:
                    if isEditing { detailEditingContent } else { detailDisplayContent }
                }
            }
        }
        .onChange(of: project.id) { _, _ in
            syncDrafts()
        }
    }

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
    }

    private var controlStrip: some View {
        HStack(spacing: 12) {
            Text(activePanel.title)
                .font(.headline)
            Spacer()
            Button {
                if isEditing { persistDraft() } else { syncDrafts() }
                withAnimation(.spring()) { isEditing.toggle() }
            } label: {
                Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                    .font(.title3)
                    .foregroundStyle(isEditing ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    activePanel = activePanel.next()
                }
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private var overviewDisplayContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("项目简介")
                    .font(.headline)
                Text(project.synopsis.isEmpty ? "暂无简介" : project.synopsis)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("标签")
                    .font(.headline)
                if project.tags.isEmpty {
                    Text("无标签")
                        .foregroundStyle(.secondary)
                } else {
                    WrapTags(tags: project.tags, tint: accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("制作周期")
                    .font(.headline)
                Text(dateRangeText(start: project.productionStartDate, end: project.productionEndDate))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("构思白板")
                    .font(.headline)
                Text(project.notes.isEmpty ? "尚未记录想法，点击编辑填写。" : project.notes)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var overviewEditingContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("项目简介")
                    .font(.headline)
                TextEditor(text: $draftSynopsis)
                    .frame(minHeight: 80, maxHeight: 140)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("标签")
                    .font(.headline)
                WrapTags(tags: draftTags, tint: accentColor) { tag in
                    draftTags.removeAll { $0 == tag }
                }
                HStack {
                    TextField("输入标签后按回车", text: $newTagDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTagDraft)
                    Button("添加") { addTagDraft() }
                        .buttonStyle(.bordered)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("开始时间")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: bindingForDate(start: true), displayedComponents: [.date])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        Button("清除") { draftStartDate = nil }
                            .font(.caption2)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("结束时间")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: bindingForDate(start: false), displayedComponents: [.date])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        Button("清除") { draftEndDate = nil }
                            .font(.caption2)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("构思白板")
                    .font(.headline)
                TextEditor(text: $draftNotes)
                    .frame(minHeight: 100, maxHeight: 180)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var detailDisplayContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("主要角色")
                    .font(.headline)
                if project.mainCharacters.isEmpty {
                    Text("尚未添加角色")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(project.mainCharacters) { character in
                                PersonaCard(character: character)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("主要场景")
                    .font(.headline)
                if project.keyScenes.isEmpty {
                    Text("尚未添加场景")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(project.keyScenes) { scene in
                            SceneCard(scene: scene)
                        }
                    }
                }
            }
        }
    }

    private var detailEditingContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("角色")
                        .font(.headline)
                    Spacer()
                    Button("添加角色", action: addCharacter)
                }
                ForEach($draftCharacters) { $character in
                    EditablePersonaRow(character: $character) {
                        draftCharacters.removeAll { $0.id == character.id }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("场景")
                        .font(.headline)
                    Spacer()
                    Button("添加场景", action: addScene)
                }
                ForEach($draftScenes) { $scene in
                    EditableSceneRow(scene: $scene) {
                        draftScenes.removeAll { $0.id == scene.id }
                    }
                }
            }
        }
    }

    private func addTagDraft() {
        let trimmed = newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        if draftTags.contains(trimmed) == false {
            draftTags.append(trimmed)
        }
        newTagDraft = ""
    }

    private func addCharacter() {
        draftCharacters.append(ProjectCharacterProfile(name: "新角色"))
    }

    private func addScene() {
        draftScenes.append(ProjectSceneProfile(name: "新场景"))
    }

    private func bindingForDate(start: Bool) -> Binding<Date> {
        Binding(
            get: {
                if start {
                    return draftStartDate ?? Date()
                } else {
                    return draftEndDate ?? Date()
                }
            },
            set: { newValue in
                if start { draftStartDate = newValue } else { draftEndDate = newValue }
            }
        )
    }

    private func dateRangeText(start: Date?, end: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        switch (start, end) {
        case (nil, nil):
            return "未设置"
        case (let s?, nil):
            return "自 \(formatter.string(from: s))"
        case (nil, let e?):
            return "截至 \(formatter.string(from: e))"
        case (let s?, let e?):
            return "\(formatter.string(from: s)) - \(formatter.string(from: e))"
        }
    }

    private func persistDraft() {
        store.updateProject(id: project.id) { editable in
            editable.synopsis = draftSynopsis
            editable.notes = draftNotes
            editable.tags = draftTags
            editable.productionStartDate = draftStartDate
            editable.productionEndDate = draftEndDate
            editable.mainCharacters = draftCharacters
            editable.keyScenes = draftScenes
        }
    }

    private func syncDrafts() {
        draftSynopsis = project.synopsis
        draftNotes = project.notes
        draftTags = project.tags
        draftStartDate = project.productionStartDate
        draftEndDate = project.productionEndDate
        draftCharacters = project.mainCharacters
        draftScenes = project.keyScenes
    }
}

extension ProjectInfoPanel {
    enum PanelPage: CaseIterable {
        case overview
        case assets

        var title: String {
            switch self {
            case .overview: return "项目概览"
            case .assets: return "角色与场景"
            }
        }

        func next() -> PanelPage {
            let all = Self.allCases
            guard let idx = all.firstIndex(of: self) else { return .overview }
            let nextIndex = all.index(after: idx)
            return nextIndex < all.endIndex ? all[nextIndex] : all.first!
        }
    }
}

struct WrapTags: View {
    let tags: [String]
    let tint: Color
    var onRemove: ((String) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(text: tag, tint: tint) {
                        onRemove?(tag)
                    }
                }
            }
        }
    }
}

struct TagChip: View {
    let text: String
    let tint: Color
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.4))
        )
    }
}

struct PersonaCard: View {
    let character: ProjectCharacterProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(character.name.prefix(1)).uppercased())
                            .font(.headline)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(character.name.isEmpty ? "未命名角色" : character.name)
                        .font(.headline)
                    Text(character.description.isEmpty ? "暂无简介" : character.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SceneCard: View {
    let scene: ProjectSceneProfile

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(scene.name.isEmpty ? "未命名场景" : scene.name)
                    .font(.subheadline.weight(.semibold))
                Text(scene.description.isEmpty ? "暂无描述" : scene.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct EditablePersonaRow: View {
    @Binding var character: ProjectCharacterProfile
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(character.name.prefix(1)).uppercased())
                )
            VStack(alignment: .leading, spacing: 6) {
                TextField("角色名称", text: $character.name)
                    .textFieldStyle(.roundedBorder)
                TextField("角色简介", text: $character.description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }
}

struct EditableSceneRow: View {
    @Binding var scene: ProjectSceneProfile
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                .frame(width: 60, height: 44)
                .overlay(Image(systemName: "photo"))
            VStack(alignment: .leading, spacing: 6) {
                TextField("场景名称", text: $scene.name)
                    .textFieldStyle(.roundedBorder)
                TextField("场景简介", text: $scene.description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }
}

struct ProjectTagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
    }
}
