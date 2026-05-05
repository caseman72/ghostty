import AppKit
import UniformTypeIdentifiers

extension NSPasteboard {
    private static let temporaryImageFilenamePrefix = "clipboard-"
    private static let maxClipboardImageSize = 10 * 1024 * 1024

    /// True if the pasteboard advertises any image-typed payload.
    func hasImageData() -> Bool {
        let types = self.types ?? []
        if types.contains(.tiff) || types.contains(.png) { return true }
        return types.contains { type in
            guard let utType = UTType(type.rawValue) else { return false }
            return utType.conforms(to: .image)
        }
    }

    /// Find the best directly-encoded image representation on the pasteboard.
    /// Prefers PNG; otherwise the first image UTType with usable data.
    private func directImageRepresentation() -> (data: Data, fileExtension: String)? {
        if let pngData = self.data(forType: .png) {
            return (pngData, "png")
        }
        for type in self.types ?? [] {
            guard type != .png, type != .tiff,
                  let utType = UTType(type.rawValue),
                  utType.conforms(to: .image),
                  let data = self.data(forType: type),
                  let ext = utType.preferredFilenameExtension,
                  !ext.isEmpty else { continue }
            return (data, ext)
        }
        return nil
    }

    /// Materialize a clipboard image to a temp file and return the URL.
    /// Returns nil if there's no image or the image fails to decode/write,
    /// or if it exceeds the 10 MB size cap.
    func writeImageToTemporaryFile() -> URL? {
        let payload: (data: Data, fileExtension: String)
        if let direct = directImageRepresentation() {
            payload = direct
        } else if hasImageData(),
                  let image = NSImage(pasteboard: self),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) {
            payload = (png, "png")
        } else {
            return nil
        }

        guard payload.data.count <= Self.maxClipboardImageSize else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = formatter.string(from: Date())
        let filename = "\(Self.temporaryImageFilenamePrefix)\(timestamp)-\(UUID().uuidString.prefix(8)).\(payload.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try payload.data.write(to: url)
        } catch {
            return nil
        }
        return url
    }
}
