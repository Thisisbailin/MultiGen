//
//  ScenarioUIComponents.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import SwiftUI

struct TagCloudView: View {
    let tags: [String]

    private var gridItems: [GridItem] {
        [GridItem(.adaptive(minimum: 140), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: gridItems, alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                    )
            }
        }
    }
}

struct SceneActionCard: View {
    let action: SceneAction

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: action.iconName)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(action.displayName)
                .font(.headline)
            Text(template?.summary ?? "即将上线")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.1))
        )
    }

    private var template: PromptTemplate? {
        PromptTemplateCatalog.templates.first { $0.id == action }
    }
}

struct PainPointRow: View {
    let painPoint: PainPoint

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)
                .frame(width: 32)
                .accessibilityLabel("痛点提示")

            VStack(alignment: .leading, spacing: 6) {
                Text(painPoint.title)
                    .font(.headline)
                Text(painPoint.detail)
                    .foregroundStyle(.secondary)
                Divider()
                Label(painPoint.solution, systemImage: "wand.and.stars.inverse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }
}

// MARK: - Layout Helpers

struct AdaptiveGrid<Item, Content>: View where Item: Identifiable, Content: View {
    let columns: Int
    let spacing: CGFloat
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: spacing) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}
