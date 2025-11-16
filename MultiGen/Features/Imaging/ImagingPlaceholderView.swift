import SwiftUI

struct ImagingView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var navigationStore: NavigationStore
    @StateObject private var store = ImagingStore()

    var body: some View {
        VStack(spacing: 16) {
            header
            Picker("模块", selection: $store.selectedSegment) {
                ForEach(ImagingStore.Segment.allCases) { segment in
                    Text(segment.title).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            Divider()

            switch store.selectedSegment {
            case .style:
                stylePanel
            default:
                placeholderPanel(title: store.selectedSegment.title)
            }
        }
        .padding(.top, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("影像模块 · macOS")
                .font(.system(.title, weight: .semibold))
            Text("当前提供风格探索的测试版文生图功能。其它子模块作为占位，稍后逐步实现。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private var stylePanel: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("风格设定 · 文生图 MVP")
                    .font(.headline)
                Text("输入想要探索的风格关键字，系统会调用 Gemini 图像模型生成一张图像并写入审计日志，智能协同会收到操作通知。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            TextField("如：赛博朋克市场·霓虹灯·烟雨夜", text: $store.promptInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

            HStack {
                Button {
                    Task {
                        await store.generateImage(dependencies: dependencies, navigationStore: navigationStore)
                    }
                } label: {
                    if store.isGenerating {
                        ProgressView()
                    } else {
                        Label("生成图像", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isGenerating || store.promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("清除状态") {
                    store.clearOutput(resetPrompt: true)
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if let image = store.generatedImage {
                ScrollView {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 420)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                }
                .frame(maxHeight: 420)
            } else {
                placeholderPanel(title: "等待生成", subtitle: "生成的图像会显示在这里，并且通知智能协同侧边栏。")
                    .frame(maxHeight: 300)
            }

            if let error = store.errorMessage {
                statusBanner(text: error, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            } else if let status = store.statusMessage {
                statusBanner(text: status, systemImage: "checkmark.seal.fill", tint: .green)
            }
        }
        .padding(20)
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
