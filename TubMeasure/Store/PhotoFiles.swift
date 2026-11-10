import UIKit

/// Saving, loading and stamping checklist photos. Files live in the job's folder.
enum PhotoFiles {
    /// Longest side of a saved photo, in pixels. Keeps PDFs a sensible size.
    static let maxDimension: CGFloat = 2000

    static func jpeg(_ image: UIImage) -> Data? {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let scale = min(1, maxDimension / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }

    static func write(_ data: Data, jobID: UUID, photoID: String) -> String? {
        let name = "\(photoID)-\(UUID().uuidString.prefix(8)).jpg"
        do {
            try data.write(to: url(jobID: jobID, fileName: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func save(_ image: UIImage, jobID: UUID, photoID: String) -> String? {
        jpeg(image).flatMap { write($0, jobID: jobID, photoID: photoID) }
    }

    static func url(jobID: UUID, fileName: String) -> URL {
        ScanStore.folder(for: jobID).appendingPathComponent(fileName)
    }

    static func image(jobID: UUID, fileName: String) -> UIImage? {
        UIImage(contentsOfFile: url(jobID: jobID, fileName: fileName).path)
    }

    static func delete(jobID: UUID, fileName: String) {
        try? FileManager.default.removeItem(at: url(jobID: jobID, fileName: fileName))
    }

    /// Draws measurement lines in a dark banner along the bottom of the photo.
    static func stamp(_ image: UIImage, lines: [String]) -> UIImage {
        guard !lines.isEmpty else { return image }
        let size = image.size
        let fontSize = max(size.width / 26, 14)
        let pad = fontSize * 0.6
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        let text = lines.joined(separator: "\n") as NSString
        let textWidth = size.width - 2 * pad
        let bounds = text.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        let bannerHeight = ceil(bounds.height) + 2 * pad
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            image.draw(at: .zero)
            UIColor.black.withAlphaComponent(0.65).setFill()
            ctx.fill(CGRect(x: 0, y: size.height - bannerHeight, width: size.width, height: bannerHeight))
            text.draw(with: CGRect(x: pad, y: size.height - bannerHeight + pad, width: textWidth, height: ceil(bounds.height)),
                      options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        }
    }
}
