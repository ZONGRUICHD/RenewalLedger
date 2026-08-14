import Combine
import Foundation
import ImageIO
import UIKit

enum BackgroundImageError: LocalizedError {
    case invalidImage
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "无法读取这张图片，请换一张再试。"
        case .storageUnavailable:
            "无法访问应用的背景图片存储位置。"
        }
    }
}

private enum BackgroundImageStorage {
    static let maximumPixelSize = 2_560
    static let folderName = "RenewalLedger"
    static let fileName = "custom-background.jpg"
}

@MainActor
final class BackgroundImageStore: ObservableObject {
    @Published private(set) var image: UIImage?

    init() {
        image = Self.loadStoredImage()
    }

    var hasImage: Bool { image != nil }

    func importImage(from data: Data) async throws {
        let encoded = try await Task.detached(priority: .userInitiated) {
            try Self.processedJPEGData(from: data)
        }.value
        try Task.checkCancellation()

        guard let fileURL = Self.fileURL(createDirectory: true) else {
            throw BackgroundImageError.storageUnavailable
        }

        try encoded.write(to: fileURL, options: .atomic)
        try Task.checkCancellation()
        guard let importedImage = UIImage(data: encoded) else {
            throw BackgroundImageError.invalidImage
        }
        image = importedImage
    }

    func removeImage() throws {
        guard let fileURL = Self.fileURL(createDirectory: false) else {
            throw BackgroundImageError.storageUnavailable
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        image = nil
    }

    private static func loadStoredImage() -> UIImage? {
        guard let fileURL = fileURL(createDirectory: false),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: data)
    }

    nonisolated private static func processedJPEGData(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw BackgroundImageError.invalidImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: BackgroundImageStorage.maximumPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw BackgroundImageError.invalidImage
        }
        let decodedImage = UIImage(cgImage: cgImage)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: decodedImage.size, format: format)
        let flattenedImage = renderer.image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: decodedImage.size))
            decodedImage.draw(in: CGRect(origin: .zero, size: decodedImage.size))
        }
        guard let encoded = flattenedImage.jpegData(compressionQuality: 0.86) else {
            throw BackgroundImageError.invalidImage
        }
        return encoded
    }

    nonisolated private static func fileURL(createDirectory: Bool) -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let folderURL = applicationSupport.appendingPathComponent(
            BackgroundImageStorage.folderName,
            isDirectory: true
        )
        if createDirectory {
            do {
                try FileManager.default.createDirectory(
                    at: folderURL,
                    withIntermediateDirectories: true
                )
            } catch {
                return nil
            }
        }
        return folderURL.appendingPathComponent(
            BackgroundImageStorage.fileName,
            isDirectory: false
        )
    }
}
