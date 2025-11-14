//
//  PromptLibraryStore.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation
import Combine

struct PromptDocument: Identifiable, Codable, Hashable {
    enum Module: String, Codable, CaseIterable, Identifiable {
        case storyboard
        case aiConsole

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .storyboard:
                return "分镜助手"
            case .aiConsole:
                return "智能协作"
            }
        }

        var moduleDescription: String {
            switch self {
            case .storyboard:
                return "用于 AI 分镜助手的系统提示词模版。"
            case .aiConsole:
                return "用于智能协同聊天的系统提示词，可定义回答口吻与上下文。"
            }
        }
    }

    let id: UUID
    let module: Module
    var title: String
    var content: String
    var lastUpdated: Date

    init(
        id: UUID = UUID(),
        module: Module,
        title: String,
        content: String,
        lastUpdated: Date = .now
    ) {
        self.id = id
        self.module = module
        self.title = title
        self.content = content
        self.lastUpdated = lastUpdated
    }
}

@MainActor
final class PromptLibraryStore: ObservableObject {
    @Published private(set) var documents: [PromptDocument]
    private let storageURL: URL
    
    init() {
        storageURL = PromptLibraryStore.makeStorageURL()
        documents = PromptLibraryStore.load(from: storageURL)
        if documents.isEmpty {
            documents = PromptLibraryStore.defaultDocuments()
            persist()
        }
    }
    
    func document(for module: PromptDocument.Module) -> PromptDocument {
        if let doc = documents.first(where: { $0.module == module }) {
            return doc
        }
        let fallback = PromptLibraryStore.defaultDocument(for: module)
        documents.append(fallback)
        persist()
        return fallback
    }
    
    func updateDocument(module: PromptDocument.Module, content: String) {
        guard let index = documents.firstIndex(where: { $0.module == module }) else { return }
        documents[index].content = content
        documents[index].lastUpdated = .now
        persist()
    }
    
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(documents)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("PromptLibraryStore persist error: \(error)")
        }
    }
    
    private static func load(from url: URL) -> [PromptDocument] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([PromptDocument].self, from: data)) ?? []
    }
    
    private static func makeStorageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("MultiGen", isDirectory: true)
            .appendingPathComponent("prompt-library.json")
    }
    
    private static func defaultDocuments() -> [PromptDocument] {
        PromptDocument.Module.allCases.map { defaultDocument(for: $0) }
    }
    
    private static func defaultDocument(for module: PromptDocument.Module) -> PromptDocument {
        switch module {
        case .storyboard:
            return PromptDocument(
                module: .storyboard,
                title: "分镜助手系统提示词",
                content: ""
            )
        case .aiConsole:
            return PromptDocument(
                module: .aiConsole,
                title: "智能协作系统提示词",
                content: ""
            )
        }
    }
}
