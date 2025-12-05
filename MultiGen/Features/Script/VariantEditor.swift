import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct VariantEditor<Variant: VariantRepresentable>: View {
    @Binding var variants: [Variant]
    let isCharacter: Bool
    @State private var pickerIsRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isCharacter ? "形态" : "子版本/视角")
                    .font(.subheadline.bold())
                Spacer()
                Button("新增") { addVariant() }
            }
            ForEach($variants) { $variant in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField(isCharacter ? "形态标签" : "视角/景别/时间标签", text: $variant.label)
                            .textFieldStyle(.roundedBorder)
                        Button("设为默认") {
                            setDefault(variant.id)
                        }
                    }
                    TextField("子版本专属提示词（可选）", text: $variant.promptOverride, axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            Button {
                                pickImage { data in
                                    guard let data else { return }
                                    var images = variant.images
                                    images.insert(Variant.ImageType(id: UUID(), data: data, isCover: true), at: 0)
                                    images = updateCoverState(images)
                                    variant.images = images
                                }
                            } label: {
                                Label("上传素材", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)

                            ForEach(Array(variant.images.enumerated()), id: \.element.id) { index, image in
                                ZStack(alignment: .topTrailing) {
                                    if let data = image.data, let nsImage = NSImage(data: data) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(image.isCover ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                                            )
                                    } else {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.secondary.opacity(0.3))
                                            .frame(width: 80, height: 80)
                                            .overlay(Image(systemName: "photo"))
                                    }
                                    VStack {
                                        Button {
                                            var images = variant.images
                                            images = updateCoverState(setCoverAt: index, in: images)
                                            variant.images = images
                                        } label: {
                                            Image(systemName: image.isCover ? "star.fill" : "star")
                                                .font(.caption)
                                                .foregroundStyle(image.isCover ? Color.accentColor : Color.secondary)
                                                .padding(6)
                                                .background(Color.black.opacity(0.25))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            var images = variant.images
                                            images.remove(at: index)
                                            variant.images = updateCoverState(images)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundStyle(.white)
                                                .padding(6)
                                                .background(Color.red.opacity(0.7))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(6)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .underPageBackgroundColor))
                )
            }
        }
    }

    private func addVariant() {
        variants.append(Variant.makeDefault(isCharacter: isCharacter))
    }

    private func setDefault(_ id: UUID) {
        // move selected variant to front
        if let idx = variants.firstIndex(where: { $0.id == id }) {
            let variant = variants.remove(at: idx)
            variants.insert(variant, at: 0)
        }
    }

    private func pickImage(_ handler: @escaping (Data?) -> Void) {
        guard pickerIsRunning == false else { return }
        pickerIsRunning = true
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            handler(data)
        }
        pickerIsRunning = false
    }

    private func updateCoverState(_ images: [Variant.ImageType]) -> [Variant.ImageType] {
        guard images.isEmpty == false else { return images }
        var updated = images
        for idx in updated.indices {
            updated[idx].isCover = idx == 0
        }
        return updated
    }

    private func updateCoverState(setCoverAt index: Int, in images: [Variant.ImageType]) -> [Variant.ImageType] {
        guard images.indices.contains(index) else { return images }
        var updated = images
        for idx in updated.indices {
            updated[idx].isCover = idx == index
        }
        return updated
    }
}

protocol VariantRepresentable: Identifiable {
    associatedtype ImageType: VariantImageRepresentable
    var id: UUID { get }
    var label: String { get set }
    var promptOverride: String { get set }
    var images: [ImageType] { get set }

    static func makeDefault(isCharacter: Bool) -> Self
}

protocol VariantImageRepresentable: Identifiable {
    var id: UUID { get }
    var data: Data? { get set }
    var isCover: Bool { get set }

    init(id: UUID, data: Data?, isCover: Bool)
}

extension CharacterVariant: VariantRepresentable {
    typealias ImageType = CharacterImage

    static func makeDefault(isCharacter: Bool) -> CharacterVariant {
        CharacterVariant(label: isCharacter ? "默认形态" : "默认", promptOverride: "", images: [])
    }
}

extension SceneVariant: VariantRepresentable {
    typealias ImageType = SceneImage

    static func makeDefault(isCharacter: Bool) -> SceneVariant {
        SceneVariant(label: isCharacter ? "默认形态" : "默认视角", promptOverride: "", images: [])
    }
}

extension CharacterImage: VariantImageRepresentable {
}

extension SceneImage: VariantImageRepresentable {
}
