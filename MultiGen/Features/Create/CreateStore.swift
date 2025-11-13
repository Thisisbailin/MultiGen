//
//  CreateStore.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct CreateResult: Identifiable, Hashable {
    let id: UUID
    let operation: CreateOperation
    let channel: SceneJobChannel
    let model: String
    let promptPreview: String
    let createdAt: Date
    let imageData: Data?
}

@MainActor
final class CreateStore: ObservableObject {
    @Published private(set) var workspaces: [StoryboardWorkspace] = []
    @Published var selectedWorkspaceID: UUID?
    @Published private(set) var selectedWorkspace: StoryboardWorkspace?
    @Published var selectedEntryID: UUID?
    @Published private(set) var selectedEntry: StoryboardEntry?
    @Published var selectedOperation: CreateOperation?
    @Published private(set) var fieldValues: [String: String] = [:]
    @Published var characterReferenceImage: Data?
    @Published var sceneReferenceImage: Data?
    @Published private(set) var results: [CreateResult] = []
    @Published var baseImageSelection: CreateResult?
    @Published var baseImageURL: URL?
    @Published var imageScale: Double = 1.0
    @Published var guidanceStrength: Double = 0.6
    @Published private(set) var isGeneratingText = false
    @Published private(set) var isGeneratingImage = false
    @Published var errorMessage: String?

    private let storyboardStore: StoryboardStore
    private let dependencies: AppDependencies
    private var cancellables: Set<AnyCancellable> = []

    init(
        storyboardStore: StoryboardStore,
        dependencies: AppDependencies
    ) {
        self.storyboardStore = storyboardStore
        self.dependencies = dependencies
        observeWorkspaces()
        selectedOperation = CreateOperationCatalog.characterOps.first
        refreshTemplateFields()
    }

    var characterOperations: [CreateOperation] { CreateOperationCatalog.characterOps }
    var sceneOperations: [CreateOperation] { CreateOperationCatalog.sceneOps }
    var blendOperations: [CreateOperation] { CreateOperationCatalog.blendOps }

    var availableEntries: [StoryboardEntry] {
        selectedWorkspace?.orderedEntries ?? []
    }

    var canGenerate: Bool {
        selectedWorkspace != nil && selectedEntry != nil && selectedOperation != nil
    }

    var baseImageDescription: String {
        if let selection = baseImageSelection {
            return "来自结果 · \(selection.operation.title)"
        }
        if let url = baseImageURL {
            return url.lastPathComponent
        }
        return "未选择"
    }

    var promptPreview: String {
        guard let template = selectedOperation?.template else {
            return "请选择创作标签并填写字段。"
        }
        var lines: [String] = []
        if let entry = selectedEntry {
            lines.append("镜 \(entry.fields.shotNumber)：\(entry.fields.shotScale)")
            if entry.fields.dialogueOrOS.isEmpty == false {
                lines.append("台词/OS：\(entry.fields.dialogueOrOS)")
            }
        }
        lines.append(template.systemHint)
        for field in template.fields {
            guard let value = fieldValues[field.id], value.isEmpty == false else { continue }
            lines.append("\(field.title)：\(value)")
        }
        return lines.joined(separator: "\n")
    }

    var currentTextModelName: String {
        dependencies.configuration.textModel.displayName
    }

    var currentImageModelName: String {
        dependencies.configuration.imageModel.displayName
    }

    var currentRouteDescription: String {
        let config = dependencies.configuration
        if config.useMock {
            return "Mock · 本地模拟"
        }
        if config.relayEnabled {
            let provider = config.relayProviderName.isEmpty ? "中转" : config.relayProviderName
            let model = config.relaySelectedModel ?? "未选模型"
            return "\(provider) · \(model)"
        }
        return "Gemini 官方"
    }

    func selectWorkspace(id: UUID?) {
        selectedWorkspaceID = id
        selectedWorkspace = workspaces.first(where: { $0.id == id })
        selectedEntryID = selectedWorkspace?.orderedEntries.first?.id
        selectedEntry = selectedWorkspace?.orderedEntries.first
        baseImageSelection = nil
        baseImageURL = nil
    }

    func selectEntry(id: UUID?) {
        selectedEntryID = id
        selectedEntry = availableEntries.first(where: { $0.id == id })
    }

    func selectOperation(_ operation: CreateOperation) {
        selectedOperation = operation
        refreshTemplateFields()
    }

    func useResultAsBaseImage(_ resultID: UUID) {
        guard let result = results.first(where: { $0.id == resultID && $0.imageData != nil }) else { return }
        baseImageSelection = result
        baseImageURL = nil
    }

    func importBaseImageFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            baseImageURL = url
            baseImageSelection = nil
        }
    }

    func clearBaseImage() {
        baseImageSelection = nil
        baseImageURL = nil
    }

    func updateField(id: String, value: String) {
        fieldValues[id] = value
    }

    func generateText() {
        guard canGenerate, let operation = selectedOperation else { return }
        isGeneratingText = true
        Task {
            defer { isGeneratingText = false }
            do {
                let request = buildRequest(for: operation, channel: .text)
                let result = try await dependencies.textService().submit(job: request)
                appendResult(from: result, operation: operation, channel: .text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func generateImage() {
        guard canGenerate, let operation = selectedOperation else { return }
        isGeneratingImage = true
        Task {
            defer { isGeneratingImage = false }
            do {
                let request = buildRequest(for: operation, channel: .image)
                let result = try await dependencies.imageService().generateImage(for: request)
                appendResult(from: result, operation: operation, channel: .image)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func observeWorkspaces() {
        storyboardStore.$workspaces
            .receive(on: RunLoop.main)
            .sink { [weak self] workspaces in
                guard let self else { return }
                self.workspaces = workspaces
                if let currentID = self.selectedWorkspaceID,
                   workspaces.contains(where: { $0.id == currentID }) == false {
                    self.selectedWorkspaceID = nil
                    self.selectedEntryID = nil
                }
                if self.selectedWorkspaceID == nil {
                    self.selectWorkspace(id: workspaces.first?.id)
                } else {
                    self.selectedWorkspace = workspaces.first(where: { $0.id == self.selectedWorkspaceID })
                    self.selectedEntry = self.availableEntries.first(where: { $0.id == self.selectedEntryID })
                }
            }
            .store(in: &cancellables)
    }

    private func refreshTemplateFields() {
        guard let template = selectedOperation?.template else {
            fieldValues = [:]
            return
        }
        var values: [String: String] = [:]
        for field in template.fields {
            values[field.id] = field.defaultValue ?? ""
        }
        fieldValues = values
    }

    private func buildRequest(for operation: CreateOperation, channel: SceneJobChannel) -> SceneJobRequest {
        var fields = fieldValues
        if let entry = selectedEntry {
            fields["shotNumber"] = "\(entry.fields.shotNumber)"
            fields["shotScale"] = entry.fields.shotScale
            fields["cameraMovement"] = entry.fields.cameraMovement
            fields["dialogueOrOS"] = entry.fields.dialogueOrOS
        }
        if let workspace = selectedWorkspace {
            fields["episode"] = workspace.episodeTitle
        }
        fields["operation"] = operation.title
        if channel == .image {
            if let base = baseImageSelection?.imageData {
                fields["baseImage"] = base.base64EncodedString()
            } else if let url = baseImageURL {
                fields["baseImageURL"] = url.absoluteString
            }
            fields["imageScale"] = String(format: "%.2f", imageScale)
            fields["guidanceStrength"] = String(format: "%.2f", guidanceStrength)
            if selectedOperation?.group == .blend {
                if let charData = characterReferenceImage {
                    fields["characterReferenceImage"] = charData.base64EncodedString()
                }
                if let sceneData = sceneReferenceImage {
                    fields["sceneReferenceImage"] = sceneData.base64EncodedString()
                }
            } else if let charData = characterReferenceImage {
                fields["referenceImage"] = charData.base64EncodedString()
            }
        }
        return SceneJobRequest(
            action: operation.action,
            fields: fields,
            channel: channel
        )
    }

    private func appendResult(
        from jobResult: SceneJobResult,
        operation: CreateOperation,
        channel: SceneJobChannel
    ) {
        let data = jobResult.imageBase64.flatMap { Data(base64Encoded: $0) }
        let preview = jobResult.metadata.prompt
        let result = CreateResult(
            id: UUID(),
            operation: operation,
            channel: channel,
            model: jobResult.metadata.model,
            promptPreview: preview,
            createdAt: .now,
            imageData: data
        )
        results.insert(result, at: 0)
    }
}
