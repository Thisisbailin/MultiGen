//
//  SceneComposerStore.swift
//  MultiGen
//
//  Created by Codex on 2025/02/15.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class SceneComposerStore: ObservableObject {
    struct ComposerAsset: Identifiable, Hashable {
        enum AssetKind: String {
            case placeholder
            case imported
        }

        let id: UUID
        var name: String
        var url: URL?
        var kind: AssetKind

        init(id: UUID = UUID(), name: String, url: URL? = nil, kind: AssetKind) {
            self.id = id
            self.name = name
            self.url = url
            self.kind = kind
        }

        var displayToken: String {
            if let url {
                return url.lastPathComponent
            }
            return name
        }
    }

    struct ComposerResult: Identifiable {
        let id: UUID
        let timestamp: Date
        let action: SceneAction
        let summary: String
        let model: String
        let responseSnippet: String
        let promptText: String
        let assets: [ComposerAsset]

        init(
            id: UUID = UUID(),
            timestamp: Date = .now,
            action: SceneAction,
            summary: String,
            model: String,
            responseSnippet: String,
            promptText: String,
            assets: [ComposerAsset]
        ) {
            self.id = id
            self.timestamp = timestamp
            self.action = action
            self.summary = summary
            self.model = model
            self.responseSnippet = responseSnippet
            self.promptText = promptText
            self.assets = assets
        }
    }

    @Published private(set) var actions: [SceneAction]
    @Published private(set) var selectedAction: SceneAction
    @Published private(set) var fieldValues: [String: String]
    @Published private(set) var assets: [ComposerAsset]
    @Published private(set) var results: [ComposerResult] = []
    @Published private(set) var isGenerating: Bool = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var hasAPIKey: Bool = false

    private let templates: [SceneAction: PromptTemplate]

    init(
        actions: [SceneAction]? = nil,
        templates: [PromptTemplate]? = nil
    ) {
        let resolvedActions = actions ?? SceneAction.workflowActions
        let resolvedTemplates = templates ?? PromptTemplateCatalog.templates
        self.actions = resolvedActions
        let lookup = Dictionary(uniqueKeysWithValues: resolvedTemplates.map { ($0.id, $0) })
        self.templates = lookup
        let initialAction = resolvedActions.first ?? .generateScene
        selectedAction = initialAction
        fieldValues = SceneComposerStore.initialValues(for: lookup[initialAction])
        assets = SceneComposerStore.initialAssets()
    }

    var activeTemplate: PromptTemplate? {
        templates[selectedAction]
    }

    var inspectorFields: [PromptField] {
        activeTemplate?.fields ?? []
    }

    func select(action: SceneAction) {
        guard selectedAction != action else { return }
        selectedAction = action
        fieldValues = SceneComposerStore.initialValues(for: templates[action])
        statusMessage = nil
        errorMessage = nil
    }

    func binding(for field: PromptField) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.fieldValues[field.id] ?? field.defaultValue ?? ""
            },
            set: { [weak self] newValue in
                self?.fieldValues[field.id] = newValue
            }
        )
    }

    func attachAsset(url: URL) {
        let asset = ComposerAsset(name: url.lastPathComponent, url: url, kind: .imported)
        assets.append(asset)
    }

    func removeAsset(id: UUID) {
        assets.removeAll { $0.id == id }
    }

    func refreshKeyAvailability(credentialsStore: CredentialsStoreProtocol) {
        do {
            let key = try credentialsStore.fetchAPIKey()
            hasAPIKey = key.isEmpty == false
        } catch {
            hasAPIKey = false
        }
    }

    func performGenerate(using dependencies: AppDependencies) async {
        guard isGenerating == false else { return }
        guard let template = activeTemplate else { return }
        do {
            let key = try dependencies.credentialsStore.fetchAPIKey()
            guard key.isEmpty == false else {
                hasAPIKey = false
                errorMessage = "请先在设置中输入 Gemini API Key。"
                return
            }
            hasAPIKey = true
        } catch {
            hasAPIKey = false
            errorMessage = error.localizedDescription
            return
        }

        isGenerating = true
        errorMessage = nil
        let routeLabel = dependencies.currentTextRoute().displayName
        statusMessage = "正在生成“\(template.summary)” · \(routeLabel)"

        let request = SceneJobRequest(
            action: selectedAction,
            fields: sanitizedFields(),
            assetReferences: assets.map(\.displayToken),
            channel: .text
        )

        do {
            let result = try await dependencies.textService().submit(job: request)
            let snippet = String(result.metadata.prompt.prefix(160))
            let composerResult = ComposerResult(
                action: selectedAction,
                summary: template.summary,
                model: result.metadata.model,
                responseSnippet: snippet,
                promptText: result.metadata.prompt,
                assets: assets
            )
            results.insert(composerResult, at: 0)
            let auditEntry = AuditLogEntry(
                jobID: request.id,
                action: request.action,
                promptHash: String(result.metadata.prompt.hashValue, radix: 16),
                assetRefs: request.assetReferences,
                modelVersion: result.metadata.model,
                metadata: [
                    "source": "SceneComposer",
                    "summary": template.summary
                ]
            )
            await dependencies.auditRepository.record(auditEntry)
            statusMessage = "生成完成：\(result.metadata.model) · \(routeLabel)"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }

        isGenerating = false
    }

    func clearStatusMessages() {
        statusMessage = nil
        errorMessage = nil
    }

    private func sanitizedFields() -> [String: String] {
        var fields = fieldValues
        for field in inspectorFields where fields[field.id]?.isEmpty ?? true {
            if let defaultValue = field.defaultValue, defaultValue.isEmpty == false {
                fields[field.id] = defaultValue
            }
        }
        return fields
    }

    private static func initialValues(for template: PromptTemplate?) -> [String: String] {
        guard let template else { return [:] }
        var values: [String: String] = [:]
        template.fields.forEach { field in
            values[field.id] = field.defaultValue ?? ""
        }
        return values
    }

    private static func initialAssets() -> [ComposerAsset] {
        [
            ComposerAsset(name: "体积光 Moodboard", kind: .placeholder),
            ComposerAsset(name: "Role Ref A", kind: .placeholder)
        ]
    }
}
