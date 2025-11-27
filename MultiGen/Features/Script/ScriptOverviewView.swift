import SwiftUI
import UniformTypeIdentifiers

struct ScriptOverviewView: View {
    @ObservedObject var store: ScriptStore
    let projects: [ScriptProject]
    let highlightedProject: ScriptProject?
    @Binding var highlightedProjectID: UUID?
    let onOpenProject: (ScriptProject) -> Void
    let onCreateProject: () -> Void
    let onImportProject: () -> Void

    @State private var draftProductionMembers: [ProductionMember] = []
    @State private var draftProducerAssignments: [UUID: UUID?] = [:]
    @State private var draftStartDate: Date?
    @State private var draftEndDate: Date?
    @State private var draftProductionTasks: [ProductionTask] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                gallerySection
                highlightPanel
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .onAppear { syncDraftsFromHighlight() }
        .onChange(of: highlightedProject?.id) { _, _ in
            syncDraftsFromHighlight()
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
            Text("以项目为单位管理集数与元信息，便于后续分镜落地和资产生成。")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var highlightPanel: some View {
        if let project = highlightedProject {
            VStack(spacing: 16) {
                ProductionSummaryRow(
                    members: $draftProductionMembers,
                    assignments: $draftProducerAssignments,
                    tasks: $draftProductionTasks,
                    episodes: project.orderedEpisodes
                )
                ProjectInfoPanel(
                    store: store,
                    project: project,
                    accentColor: Color(nsColor: .windowBackgroundColor)
                )
            }
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

private let projectCardColor = Color(nsColor: .windowBackgroundColor)

private extension ScriptOverviewView {
    func syncDraftsFromHighlight() {
        guard let project = highlightedProject else {
            draftProductionMembers = []
            draftProducerAssignments = [:]
            draftStartDate = nil
            draftEndDate = nil
            draftProductionTasks = []
            return
        }
        draftProductionMembers = project.productionMembers
        draftProducerAssignments = Dictionary(uniqueKeysWithValues: project.episodes.map { ($0.id, $0.producerID) })
        draftStartDate = project.productionStartDate
        draftEndDate = project.productionEndDate
        draftProductionTasks = project.productionTasks
    }
}

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
                .fill(Color(nsColor: .windowBackgroundColor))
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
    @State private var draftProductionMembers: [ProductionMember] = []
    @State private var draftProducerAssignments: [UUID: UUID?] = [:]
    @State private var draftProductionTasks: [ProductionTask] = []
    @State private var newMemberName: String = ""

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
        _draftProductionMembers = State(initialValue: project.productionMembers)
        _draftProducerAssignments = State(initialValue: Dictionary(uniqueKeysWithValues: project.episodes.map { ($0.id, $0.producerID) }))
        _draftProductionTasks = State(initialValue: project.productionTasks)
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
                    .fill(Color(nsColor: .windowBackgroundColor))
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
                Text("分集大纲")
                    .font(.headline)
                if project.episodeOutlines.isEmpty {
                    Text("尚未导入分集大纲")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(project.episodeOutlines.sorted(by: { $0.episodeNumber < $1.episodeNumber })) { outline in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(outline.title.isEmpty ? "第\(outline.episodeNumber)集" : outline.title)
                                    .font(.subheadline.bold())
                                Text(outline.summary)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .underPageBackgroundColor))
                            )
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
            editable.productionMembers = draftProductionMembers
            editable.productionTasks = draftProductionTasks
            editable.episodes = editable.episodes.map { episode in
                var updated = episode
                if let override = draftProducerAssignments[episode.id] {
                    updated.producerID = override
                }
                return updated
            }
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
        draftProductionMembers = project.productionMembers
        draftProducerAssignments = Dictionary(uniqueKeysWithValues: project.episodes.map { ($0.id, $0.producerID) })
        draftProductionTasks = project.productionTasks
        newMemberName = ""
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

    // MARK: - Production Team

    private func productionTeamCard(editing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("制作人员")
                    .font(.headline)
                Spacer()
                if editing {
                    HStack(spacing: 8) {
                        TextField("姓名", text: $newMemberName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                            .onSubmit(addMember)
                        Button("添加") { addMember() }
                            .buttonStyle(.bordered)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(draftProductionMembers, id: \.id) { member in
                        HStack(spacing: 8) {
                            AvatarCircle(initials: initials(for: member.name), color: color(from: member.colorHex))
                            Text(member.name.isEmpty ? "未命名" : member.name)
                                .foregroundStyle(.primary)
                            if editing {
                                Button(role: .destructive) {
                                    draftProductionMembers.removeAll { $0.id == member.id }
                                    draftProducerAssignments = draftProducerAssignments.mapValues { $0 == member.id ? nil : $0 }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .underPageBackgroundColor)))
                    }
                }
            }

            if project.orderedEpisodes.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("分集制作分配")
                        .font(.subheadline.bold())
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(project.orderedEpisodes) { episode in
                            let assigned = assignedProducer(for: episode)
                            let tint = assigned.map { color(from: $0.colorHex) } ?? Color(nsColor: .underPageBackgroundColor)
                            episodeCard(for: episode, assigned: assigned, tint: tint)
                                .contextMenu {
                                    Button("未分配") {
                                        draftProducerAssignments[episode.id] = nil
                                    }
                                    ForEach(draftProductionMembers, id: \.id) { member in
                                        Button(member.name) {
                                            draftProducerAssignments[episode.id] = member.id
                                        }
                                    }
                                }
                                .onTapGesture {
                                    guard draftProductionMembers.isEmpty == false else { return }
                                    let members = draftProductionMembers
                                    if let current = assigned,
                                       let idx = members.firstIndex(where: { $0.id == current.id }) {
                                        let next = members.index(after: idx)
                                        draftProducerAssignments[episode.id] = next < members.endIndex ? members[next].id : nil
                                    } else {
                                        draftProducerAssignments[episode.id] = members.first?.id
                                    }
                                }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }

    private func addMember() {
        let trimmed = newMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let palette = ["#FF7A00", "#4A90E2", "#7ED321", "#BD10E0", "#F5A623", "#50E3C2", "#D0021B", "#417505"]
        let color = palette.randomElement() ?? "#4A90E2"
        draftProductionMembers.append(ProductionMember(name: trimmed, colorHex: color))
        newMemberName = ""
    }

    private func assignedProducer(for episode: ScriptEpisode) -> ProductionMember? {
        let assignedID = draftProducerAssignments[episode.id] ?? episode.producerID
        return draftProductionMembers.first(where: { $0.id == assignedID })
    }

    @ViewBuilder
    private func episodeCard(for episode: ScriptEpisode, assigned: ProductionMember?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(episode.displayLabel)
                .font(.subheadline.weight(.semibold))
            if let assigned {
                HStack(spacing: 6) {
                    AvatarCircle(initials: initials(for: assigned.name), color: color(from: assigned.colorHex))
                    Text(assigned.name)
                        .font(.caption)
                }
            } else {
                Text("未分配")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.2)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.5), lineWidth: assigned == nil ? 0.5 : 1)
        )
        .contentShape(Rectangle())
    }

    private func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }
        return String(trimmed.prefix(1))
    }

    private func color(from hex: String) -> Color {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let intVal = Int(cleaned, radix: 16) else { return Color.accentColor }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
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

struct AvatarCircle: View {
    let initials: String
    let color: Color

    var body: some View {
        Text(initials)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(color))
    }
}

struct PersonaCard: View {
    let character: ProjectCharacterProfile
    var onTap: (() -> Void)? = nil
    @State private var isExpanded = false

    private var coverImage: NSImage? {
        guard let data = character.primaryImageData else { return nil }
        return NSImage(data: data)
    }

    private var variantBadge: String {
        let variantCount = character.variants.count
        let imageCount = character.variants.flatMap { $0.images }.count
        return "\(variantCount) 形态｜\(imageCount) 图"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = coverImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 220, height: 280)
                    .clipped()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.square")
                            .font(.title)
                        Text("未上传封面")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 220, height: 280)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.5), Color.black.opacity(0.1)],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 110)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                Text(character.name.isEmpty ? "未命名角色" : character.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(variantBadge)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                if isExpanded {
                    Text(character.description.isEmpty ? "暂无简介" : character.description)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                }
            }
            .padding(14)
        }
        .frame(width: 220, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onTap {
                onTap()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
        }
    }
}


struct SceneCard: View {
    let scene: ProjectSceneProfile
    var onTap: (() -> Void)? = nil
    @State private var isExpanded = false

    private func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
    }
    
    private var coverImage: NSImage? {
        guard let data = scene.primaryImageData else { return nil }
        return NSImage(data: data)
    }
    
    private var variantBadge: String {
        let variantCount = scene.variants.count
        let imageCount = scene.variants.flatMap { $0.images }.count
        return "\(variantCount) 视角｜\(imageCount) 图"
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = coverImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 220, height: 280)
                    .clipped()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.blue.opacity(0.12))
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title)
                        Text("未上传封面")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 220, height: 280)
            }
            
            LinearGradient(
                colors: [Color.black.opacity(0.5), Color.black.opacity(0.1)],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 110)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(scene.name.isEmpty ? "未命名场景" : scene.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(variantBadge)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                if isExpanded {
                    Text(scene.description.isEmpty ? "暂无描述" : scene.description)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                    if scene.characters.isEmpty == false {
                        HStack(spacing: 6) {
                            ForEach(scene.characters) { role in
                                AvatarCircle(initials: initials(for: role.name), color: Color.white.opacity(0.3))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                                    )
                                    .help(role.name.isEmpty ? "人物" : role.name)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 220, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if let onTap {
                    onTap()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }
        }
    }
    
    struct EditablePersonaRow: View {
        @Binding var character: ProjectCharacterProfile
        let onDelete: () -> Void
        @State private var pickerIsRunning = false
        
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 64, height: 64)
                    if let data = character.imageData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: "person.crop.square")
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("角色名称", text: $character.name)
                        .textFieldStyle(.roundedBorder)
                    TextField("角色简介", text: $character.description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    TextField("生成提示词", text: $character.prompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button("上传封面") {
                            pickImage { data in
                                character.imageData = data
                                if character.variants.isEmpty {
                                    character.variants = [
                                        CharacterVariant(
                                            images: [CharacterImage(data: data, isCover: true)]
                                        )
                                    ]
                                } else {
                                    character.variants[0].images.insert(CharacterImage(data: data, isCover: true), at: 0)
                                    character.variants[0].images = updateCoverState(character.variants[0].images)
                                }
                            }
                        }
                        Button("清除封面") {
                            character.imageData = nil
                            if character.variants.isEmpty == false {
                                character.variants[0].images = []
                            }
                        }
                        .disabled(character.imageData == nil)
                    }
                    if character.variants.isEmpty {
                        Button("添加形态") {
                            character.variants.append(CharacterVariant())
                        }
                    }
                    if character.variants.isEmpty == false {
                        VariantEditor(
                            variants: $character.variants,
                            isCharacter: true
                        )
                    }
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
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
    }
    
    struct EditableSceneRow: View {
        @Binding var scene: ProjectSceneProfile
        let onDelete: () -> Void
        @State private var pickerIsRunning = false
        
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 64, height: 64)
                    if let data = scene.imageData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("场景名称", text: $scene.name)
                        .textFieldStyle(.roundedBorder)
                    TextField("场景简介", text: $scene.description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button("上传封面") {
                            pickImage { data in
                                scene.imageData = data
                                if scene.variants.isEmpty {
                                    scene.variants = [
                                        SceneVariant(
                                            images: [SceneImage(data: data, isCover: true)]
                                        )
                                    ]
                                } else {
                                    scene.variants[0].images.insert(SceneImage(data: data, isCover: true), at: 0)
                                    scene.variants[0].images = updateCoverState(scene.variants[0].images)
                                }
                            }
                        }
                        Button("清除封面") {
                            scene.imageData = nil
                            if scene.variants.isEmpty == false {
                                scene.variants[0].images = []
                            }
                        }
                        .disabled(scene.imageData == nil)
                    }
                    TextField("生成提示词", text: $scene.prompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    if scene.variants.isEmpty {
                        Button("添加视角/子版本") {
                            scene.variants.append(SceneVariant())
                        }
                    }
                    if scene.variants.isEmpty == false {
                        VariantEditor(
                            variants: $scene.variants,
                            isCharacter: false
                        )
                    }
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
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
        
        private func updateCoverState(_ images: [SceneImage]) -> [SceneImage] {
            guard images.isEmpty == false else { return images }
            var updated = images
            for idx in updated.indices {
                updated[idx].isCover = idx == 0
            }
            return updated
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
