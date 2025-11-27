import SwiftUI

struct ProductionSummaryRow: View {
    @Binding var members: [ProductionMember]
    @Binding var assignments: [UUID: UUID?] // episodeID -> memberID
    @Binding var tasks: [ProductionTask]
    let episodes: [ScriptEpisode]

    @State private var completedEpisodes: Set<UUID> = []
    @State private var newMemberName: String = ""
    @State private var isEditing = false

    @State private var taskName: String = ""
    @State private var taskStart: Date = Date()
    @State private var taskEnd: Date = Date().addingTimeInterval(24 * 3600)

    var body: some View {
        HStack(spacing: 12) {
            productionCard
                .frame(maxWidth: .infinity)
            timelineCard
                .frame(maxWidth: .infinity)
        }
    }

    private var productionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("制作人员")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation { isEditing.toggle() }
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(members) { member in
                    AvatarCircle(initials: initials(for: member.name), color: color(from: member.colorHex))
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                        .help(member.name)
                }
                if members.isEmpty {
                    Text("暂未添加").foregroundStyle(.secondary)
                }
            }

            if isEditing {
                HStack(spacing: 8) {
                    TextField("新增人员姓名", text: $newMemberName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(addMember)
                    Button("添加") { addMember() }
                        .buttonStyle(.bordered)
                }
            }

            if episodes.isEmpty == false {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                    ForEach(episodes) { episode in
                        let assignedID = assignments[episode.id] ?? episode.producerID
                        let assigned = members.first(where: { $0.id == assignedID })
                        let tint = assigned.map { color(from: $0.colorHex) } ?? Color(nsColor: .underPageBackgroundColor)
                        let isDone = completedEpisodes.contains(episode.id)
                        Circle()
                            .fill(isDone ? tint.opacity(0.8) : tint.opacity(0.35))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Text("\(episode.episodeNumber)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                            )
                            .overlay(
                                Circle().stroke(tint.opacity(isDone ? 1.0 : 0.6), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                            .contextMenu {
                                if isEditing {
                                    Button(isDone ? "标记未完成" : "标记完成") { toggleDone(episode.id) }
                                    Button("未分配") { assignments[episode.id] = nil }
                                    ForEach(members) { member in
                                        Button(member.name) { assignments[episode.id] = member.id }
                                    }
                                }
                            }
                            .onTapGesture {
                                guard isEditing else { return }
                                toggleDone(episode.id)
                                if members.isEmpty == false {
                                    let list = members
                                    if let current = assignments[episode.id],
                                       let idx = list.firstIndex(where: { $0.id == current }) {
                                        let next = list.index(after: idx)
                                        assignments[episode.id] = next < list.endIndex ? list[next].id : nil
                                    } else {
                                        assignments[episode.id] = list.first?.id
                                    }
                                }
                            }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("制作周期")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation { isEditing.toggle() }
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                }
                .buttonStyle(.plain)
            }

            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("任务名称", text: $taskName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        DatePicker("开始", selection: $taskStart, displayedComponents: [.date])
                        DatePicker("结束", selection: $taskEnd, displayedComponents: [.date])
                    }
                    Button("添加任务") { addTask() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if tasks.isEmpty {
                Text("暂无任务").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(tasks) { task in
                        let duration = max(1, Calendar.current.dateComponents([.day], from: task.startDate, to: task.endDate).day ?? 0)
                        let tint = Color.accentColor.opacity(0.7)
                        HStack {
                            Circle().fill(tint).frame(width: 10, height: 10)
                            Text(task.name.isEmpty ? "未命名任务" : task.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(duration) 天")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(tint.opacity(0.6), lineWidth: 1)
                        )
                        .contextMenu {
                            Button(task.isDone ? "标记进行中" : "标记完成") {
                                toggleTask(task.id)
                            }
                            Button("删除", role: .destructive) {
                                tasks.removeAll { $0.id == task.id }
                            }
                        }
                        .onTapGesture {
                            toggleTask(task.id)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
    }

    private func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first)
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

    private func toggleDone(_ id: UUID) {
        if completedEpisodes.contains(id) {
            completedEpisodes.remove(id)
        } else {
            completedEpisodes.insert(id)
        }
    }

    private func addMember() {
        let trimmed = newMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let palette = ["#FF7A00", "#4A90E2", "#7ED321", "#BD10E0", "#F5A623", "#50E3C2", "#D0021B", "#417505"]
        let color = palette.randomElement() ?? "#4A90E2"
        members.append(ProductionMember(name: trimmed, colorHex: color))
        newMemberName = ""
    }

    private func addTask() {
        guard taskStart <= taskEnd else { return }
        let task = ProductionTask(
            name: taskName.isEmpty ? "未命名任务" : taskName,
            startDate: taskStart,
            endDate: taskEnd
        )
        tasks.append(task)
        taskName = ""
        taskStart = Date()
        taskEnd = Date().addingTimeInterval(24 * 3600)
    }

    private func toggleTask(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].isDone.toggle()
    }
}
