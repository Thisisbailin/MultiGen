//
//  PromptLibraryView.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import SwiftUI

struct PromptLibraryView: View {
    @EnvironmentObject private var store: PromptLibraryStore
    @State private var selectedModule: PromptDocument.Module = .aiConsole
    @State private var draftContent: String = ""
    @State private var showSavedToast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            editor
            if showSavedToast {
                Label("已保存自定义提示词", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Spacer()
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadDraft()
        }
        .onChange(of: selectedModule) { _, _ in
            loadDraft()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("指令资料库")
                .font(.largeTitle.bold())
            Text("维护各模块所使用的系统提示词模版，可依据团队风格做定制。")
                .foregroundStyle(.secondary)
            Picker("模块", selection: $selectedModule) {
                ForEach(PromptDocument.Module.allCases) { module in
                    Text(module.displayName).tag(module)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            let document = store.document(for: selectedModule)
            Text(document.module.moduleDescription)
                .font(.subheadline)
            TextEditor(text: $draftContent)
                .font(.body.monospaced())
                .padding(12)
                .frame(minHeight: 320)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2))
                )
            HStack {
                Spacer()
                Button {
                    store.updateDocument(module: selectedModule, content: draftContent)
                    showSavedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showSavedToast = false
                    }
                } label: {
                    Label("保存自定义提示词", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive) {
                    store.resetDocument(module: selectedModule)
                    loadDraft()
                } label: {
                    Label("恢复默认", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func loadDraft() {
        let doc = store.document(for: selectedModule)
        draftContent = doc.content
    }
}
