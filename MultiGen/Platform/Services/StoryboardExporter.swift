//
//  StoryboardExporter.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum StoryboardExportFormat: CaseIterable, Identifiable {
    case markdown
    case json
    case pdf

    var id: String { displayName }

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .json: return "JSON"
        case .pdf: return "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        case .pdf: return "pdf"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: return .plainText
        case .json: return .json
        case .pdf: return .pdf
        }
    }
}

struct StoryboardExportDocument: Codable {
    struct Entry: Codable {
        let shotNumber: Int
        let shotScale: String
        let cameraMovement: String
        let duration: String
        let dialogueOrOS: String
        let aiPrompt: String
        let status: String
        let version: Int
    }

    struct Dialogue: Codable {
        let role: String
        let message: String
        let referencedShots: [Int]
        let timestamp: Date
    }

    let episodeNumber: Int
    let episodeTitle: String
    let generatedAt: Date
    let entryCount: Int
    let entries: [Entry]
    let dialogue: [Dialogue]
}

struct StoryboardExporter {
    func makeMarkdown(from workspace: StoryboardWorkspace) -> String {
        var lines: [String] = []
        lines.append("# 分镜脚本 — \(workspace.episodeTitle)")
        lines.append("")
        lines.append("- 剧集编号：\(workspace.episodeNumber)")
        lines.append("- 导出时间：\(Date().formatted(date: .abbreviated, time: .shortened))")
        lines.append("- 条目数量：\(workspace.entries.count)")
        lines.append("")
        lines.append("## 分镜条目")
        lines.append("")
        for entry in workspace.orderedEntries {
            lines.append("### 镜 \(entry.fields.shotNumber) · \(entry.fields.shotScale)")
            lines.append("- 运镜：\(entry.fields.cameraMovement.isEmpty ? "（未填写）" : entry.fields.cameraMovement)")
            lines.append("- 时长：\(entry.fields.duration.isEmpty ? "（未填写）" : entry.fields.duration)")
            lines.append("- 台词/OS：\(entry.fields.dialogueOrOS.isEmpty ? "（未填写）" : entry.fields.dialogueOrOS)")
            lines.append("- AIGC 提示词：\(entry.fields.aiPrompt.isEmpty ? "（未填写）" : entry.fields.aiPrompt)")
            lines.append("- 状态：\(entry.status.displayName) · v\(entry.version)")
            if entry.notes.isEmpty == false {
                lines.append("- 备注：\(entry.notes)")
            }
            lines.append("")
        }

        if workspace.dialogueTurns.isEmpty == false {
            lines.append("## 对话记录")
            lines.append("")
            for turn in workspace.dialogueTurns.sorted(by: { $0.createdAt < $1.createdAt }) {
                let role = turn.role == .assistant ? "MultiGen" : (turn.role == .user ? "用户" : "系统")
                let timestamp = turn.createdAt.formatted(date: .omitted, time: .shortened)
                lines.append("**[\(role) · \(timestamp)]**")
                lines.append(turn.message)
                if turn.referencedEntryIDs.isEmpty == false {
                    lines.append("_涉及镜号：\(turn.referencedEntryIDs.compactMap { id in workspace.entries.first(where: { $0.id == id })?.fields.shotNumber }.map(String.init).joined(separator: ", "))_")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    func makeJSONDocument(from workspace: StoryboardWorkspace) -> StoryboardExportDocument {
        let entries = workspace.orderedEntries.map { entry in
            StoryboardExportDocument.Entry(
                shotNumber: entry.fields.shotNumber,
                shotScale: entry.fields.shotScale,
                cameraMovement: entry.fields.cameraMovement,
                duration: entry.fields.duration,
                dialogueOrOS: entry.fields.dialogueOrOS,
                aiPrompt: entry.fields.aiPrompt,
                status: entry.status.displayName,
                version: entry.version
            )
        }

        let dialogue = workspace.dialogueTurns.sorted(by: { $0.createdAt < $1.createdAt }).map { turn in
            StoryboardExportDocument.Dialogue(
                role: turn.role.rawValue,
                message: turn.message,
                referencedShots: turn.referencedEntryIDs.compactMap { id in
                    workspace.entries.first(where: { $0.id == id })?.fields.shotNumber
                },
                timestamp: turn.createdAt
            )
        }

        return StoryboardExportDocument(
            episodeNumber: workspace.episodeNumber,
            episodeTitle: workspace.episodeTitle,
            generatedAt: .now,
            entryCount: workspace.entries.count,
            entries: entries,
            dialogue: dialogue
        )
    }

    func export(workspace: StoryboardWorkspace, format: StoryboardExportFormat) throws -> (Data, UTType) {
        switch format {
        case .markdown:
            let markdown = makeMarkdown(from: workspace)
            guard let data = markdown.data(using: .utf8) else {
                throw NSError(domain: "StoryboardExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法编码 Markdown"])
            }
            return (data, .plainText)
        case .json:
            let document = makeJSONDocument(from: workspace)
            let data = try JSONEncoder().encode(document)
            return (data, .json)
        case .pdf:
            let markdown = makeMarkdown(from: workspace)
            let data = try renderPDF(from: markdown)
            return (data, .pdf)
        }
    }

    private func renderPDF(from text: String) throws -> Data {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.string = text
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        return textView.dataWithPDF(inside: textView.bounds)
    }
}
