import CoreImage
import Foundation
import IcebergKit
import Vision

/// Removes an image's background on this Mac (Vision's foreground
/// instance mask, macOS 14 and later) and writes the subject as a PNG with
/// a transparent background beside the original ("photo-cutout.png"). The
/// original is only read. The new file is written only if its name is
/// still free, so nothing is ever overwritten.
enum BackgroundRemover {
    static func run(source: URL, completion: @escaping @Sendable (Result<URL, ToolError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = autoreleasepool { make(source) }
            completion(result)
        }
    }

    static func make(_ source: URL) -> Result<URL, ToolError> {
        guard let out = QuickAction.removeBackground.destination(
            for: source, isDirectory: false, exists: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return .failure(.noFreeName)
        }
        guard let image = CIImage(contentsOf: source, options: [.applyOrientationProperty: true]) else {
            return .failure(.unsupported("the image could not be read"))
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                return .failure(.unsupported("no subject was found in the image"))
            }
            let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler,
                                                             croppedToInstancesExtent: false)
            let cutout = CIImage(cvPixelBuffer: buffer)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let png = CIContext(options: [.cacheIntermediates: false])
                    .pngRepresentation(of: cutout, format: .RGBA8, colorSpace: space, options: [:]) else {
                return .failure(.unsupported("the PNG could not be made"))
            }
            // .withoutOverwriting: if the name was taken meanwhile, nothing is written.
            try png.write(to: out, options: .withoutOverwriting)
            return .success(out)
        } catch {
            return .failure(.failed(status: 0, message: error.localizedDescription))
        }
    }
}
