import AppKit
import BrowserKit
import QuickLookThumbnailing
import SwiftUI

/// A file's Quick Look thumbnail for the icon and gallery views (R13), or its
/// SF Symbol for folders, archive entries and files without one.
struct Thumbnail: View {
    let item: FileItem
    let size: CGFloat
    let palette: Palette
    @Local private var image: NSImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: FileSymbol.name(for: item))
                    .font(.system(size: size * 0.42, weight: .light))
                    .foregroundStyle(item.isFolder ? palette.accent : palette.dim)
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(item.id)-\(Int(size))") {
            image = nil
            guard !item.isFolder, !item.isInArchive else { return }
            image = await ThumbnailCache.shared.image(for: item.url, size: size)
        }
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    /// At most 600 thumbnails or about 48 MB of pixels; macOS also empties
    /// it under memory pressure. A folder of thousands of images scrolls
    /// through it rather than piling up.
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    func image(for url: URL, size: CGFloat) async -> NSImage? {
        let key = "\(url.path)#\(Int(size))" as NSString
        if let known = cache.object(forKey: key) { return known }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: scale, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = representation.nsImage
        // The cost is the pixels drawn: side x side x scale squared x 4 bytes.
        let cost = Int(size * size * scale * scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
