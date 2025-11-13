//
//  ScenarioOverviewView.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import SwiftUI

struct ScenarioOverviewView: View {
    let painPoints: [PainPoint]
    let actions: [SceneAction]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                Divider()
                actionSection
                Divider()
                painPointSection
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MultiGen · macOS 创作控制台")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text("围绕 AIGC 场景合成的真实流程，提供素材管理、模板化提示与 Gemini 生成的统一视图。此版本聚焦 macOS 体验，遵循 Apple Human Interface Guidelines 的内容优先原则。")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TagCloudView(tags: ["macOS 26 设计", "Gemini", "Prompt Orchestrator", "Keychain 安全", "审计日志"])
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("6 大场景动作")
                .font(.title2.bold())
            Text("每个操作都映射到结构化模板，可快速从构思跳转到生成。")
                .foregroundStyle(.secondary)

            AdaptiveGrid(columns: 3, spacing: 16, items: actions) { action in
                SceneActionCard(action: action)
            }
        }
    }

    private var painPointSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AIGC 场景创作痛点")
                .font(.title2.bold())
            Text("首启及帮助面板会展示以下内容，帮助创作者理解我们为何构建 MultiGen。")
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                ForEach(painPoints) { point in
                    PainPointRow(painPoint: point)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.2))
                        )
                }
            }
        }
    }
}
