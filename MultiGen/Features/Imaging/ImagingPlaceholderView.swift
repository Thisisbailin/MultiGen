//
//  ImagingPlaceholderView.swift
//  MultiGen
//
//  Created by Codex on 2025/02/15.
//

import SwiftUI

struct ImagingPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("影像模块正在重构")
                .font(.title.weight(.semibold))
            Text("""
我们正在基于稳定的剧本与分镜链路重新规划影像创作流程。
在此阶段，影像页面仅作为占位入口，后续会引入新的架构设计与交互方案。
""")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("如有新的创作需求或想法，欢迎先在分镜页记录。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
