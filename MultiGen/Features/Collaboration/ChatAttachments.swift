import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class ChatAttachmentController: ObservableObject {
    let maxCount: Int
    @Published private(set) var attachments: [ImageAttachment] = []

    init(maxCount: Int = 3) {
        self.maxCount = maxCount
    }

    var remainingCapacity: Int {
        max(0, maxCount - attachments.count)
    }

    func presentAttachmentPicker(onError: (String) -> Void) {
        guard remainingCapacity > 0 else {
            onError("最多只能附加 \(maxCount) 张图片。")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ChatAttachmentController.supportedTypes
        panel.prompt = "添加"

        if panel.runModal() == .OK {
            let urls = Array(panel.urls.prefix(remainingCapacity))
            for url in urls {
                do {
                    let rawData = try Data(contentsOf: url)
                    guard let image = NSImage(data: rawData) else {
                        onError("无法读取图片：\(url.lastPathComponent)")
                        continue
                    }
                    let data = compress(image: image, fallback: rawData)
                    let attachment = ImageAttachment(
                        data: data,
                        preview: image,
                        fileName: url.lastPathComponent
                    )
                    attachments.append(attachment)
                } catch {
                    onError("无法加载文件：\(url.lastPathComponent)")
                }
            }
        }
    }

    func remove(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    func reset() {
        attachments.removeAll()
    }

    private static var supportedTypes: [UTType] {
        [
            .jpeg,
            .png,
            .tiff,
            .bmp,
            .gif,
            .heic
        ].compactMap { $0 }
    }

    private func compress(image: NSImage, fallback: Data, maxDimension: CGFloat = 512, quality: CGFloat = 0.7) -> Data {
        let targetSize: NSSize
        if image.size.width > image.size.height {
            let ratio = maxDimension / max(image.size.width, 1)
            targetSize = NSSize(width: maxDimension, height: max(1, image.size.height * ratio))
        } else {
            let ratio = maxDimension / max(image.size.height, 1)
            targetSize = NSSize(width: max(1, image.size.width * ratio), height: maxDimension)
        }
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        guard let tiff = newImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            return fallback
        }
        return data.count < fallback.count ? data : fallback
    }
}

struct ImageAttachment: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let preview: NSImage
    let fileName: String

    var base64String: String { data.base64EncodedString() }
}
