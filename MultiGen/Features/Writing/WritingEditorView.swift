import SwiftUI

struct WritingEditorView: View {
    let projectID: UUID
    @State var writing: WritingWork
    var onUpdate: (WritingWork) -> Void

    @State private var selectedChapterID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("写作 · 文本编辑")
                    .font(.headline)
                Spacer()
                Button {
                    addChapter()
                } label: {
                    Label("新增章节", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            TextField("写作标题", text: $writing.title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $writing.synopsis)
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2))
                )
                .overlay(alignment: .topLeading) {
                    if writing.synopsis.isEmpty {
                        Text("写作简介（可选）")
                            .font(.caption)
                            .padding(6)
                            .foregroundStyle(.secondary)
                    }
                }

            chapterList

            if let chapter = currentChapterBinding {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("章节标题", text: chapter.title)
                        .textFieldStyle(.roundedBorder)
                    TextField("章节概要", text: chapter.summary)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: chapter.body)
                        .frame(minHeight: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                }
            } else {
                Text("请选择章节进行编辑。")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .onChange(of: writing) { _, newValue in
            onUpdate(newValue)
        }
        .onAppear {
            if selectedChapterID == nil {
                selectedChapterID = writing.chapters.first?.id
            }
        }
    }

    private var chapterList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(writing.chapters) { chapter in
                    Button {
                        selectedChapterID = chapter.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chapter.title.isEmpty ? "未命名章节" : chapter.title)
                                .font(.subheadline.bold())
                            Text(chapter.summary.isEmpty ? "暂无概要" : chapter.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(10)
                        .frame(width: 180, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedChapterID == chapter.id ? Color.accentColor.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selectedChapterID == chapter.id ? Color.accentColor : Color.secondary.opacity(0.2))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var currentChapterBinding: Binding<WritingChapter>? {
        guard let id = selectedChapterID,
              let idx = writing.chapters.firstIndex(where: { $0.id == id }) else { return nil }
        return $writing.chapters[idx]
    }

    private func addChapter() {
        let order = (writing.chapters.map(\.order).max() ?? 0) + 1
        let chapter = WritingChapter(order: order, title: writing.type == .serialized ? "第\(order)章" : "草稿\(order)")
        writing.chapters.append(chapter)
        selectedChapterID = chapter.id
    }
}
