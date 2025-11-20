import SwiftUI
import AppKit

struct ImagingView: View {
    @EnvironmentObject private var store: ImagingStore

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                instructions
                resultPanel
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("影像模块 · macOS")
                .font(.system(.title, weight: .semibold))
            Text("影像模块现在通过智能协同面板触发生成，页面仅作为结果画廊与状态面板。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("如何使用", systemImage: "sparkles")
                .font(.headline)
            Text("在左侧的智能协同面板切换到影像模块，输入提示并可以附加参考图片。生成完成后，结果会自动展示在下方。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = store.errorMessage {
                statusBanner(text: error, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            } else if let status = store.statusMessage {
                statusBanner(text: status, systemImage: "checkmark.seal.fill", tint: .green)
            } else {
                statusBanner(text: "等待指令…", systemImage: "hourglass", tint: .secondary)
            }

            if let image = store.generatedImage {
                ScrollView {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .shadow(radius: 10)
                        .padding(.vertical, 8)
                }
                .frame(maxHeight: 440)
            } else {
                placeholderPanel(title: "等待生成", subtitle: "当你在智能协同内触发生图时，结果会展示在这里。")
                    .frame(maxHeight: 320)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholderPanel(title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(title) 子模块待实现")
                .font(.headline)
            Text(subtitle ?? "我们会在完成设计后陆续开放。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func statusBanner(text: String, systemImage: String, tint: Color) -> some View {
        HStack {
            Image(systemName: systemImage)
            Text(text)
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(tint)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

}
