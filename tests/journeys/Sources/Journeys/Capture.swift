import AppKit
import CoreGraphics
import ImageIO

/// Window lookup in the window server, screenshots and simple pixel checks.
enum Capture {
    struct WindowInfo {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        let layer: Int
    }

    /// On-screen windows of one process, frontmost first.
    static func windows(pid: pid_t) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, owner == pid,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0, bounds.width > 1, bounds.height > 1 else { return nil }
            return WindowInfo(id: number, pid: owner, bounds: bounds, layer: layer)
        }
    }

    /// The window-server window closest to an accessibility frame.
    static func windowID(pid: pid_t, near frame: CGRect?) -> CGWindowID? {
        let mine = windows(pid: pid)
        guard let frame else { return mine.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }?.id }
        func distance(_ r: CGRect) -> CGFloat {
            abs(r.minX - frame.minX) + abs(r.minY - frame.minY) + abs(r.width - frame.width) + abs(r.height - frame.height)
        }
        return mine.min { distance($0.bounds) < distance($1.bounds) }?.id
    }

    static var canRecordScreen: Bool { CGPreflightScreenCaptureAccess() }

    /// A PNG of one window (or the whole screen when there is none).
    @discardableResult
    static func shot(to url: URL, window: CGWindowID?) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var args = ["-x", "-t", "png"]
        if let window { args += ["-o", "-l", String(window)] }
        args.append(url.path)
        let result = Shell.run("/usr/sbin/screencapture", args, timeout: 15)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        return result.status == 0 && size > 0
    }

    struct Colour {
        let red: Double, green: Double, blue: Double
        var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
        func distance(to other: Colour) -> Double {
            abs(red - other.red) + abs(green - other.green) + abs(blue - other.blue)
        }
    }

    /// The average colour of an image, from a 64 by 64 sample.
    static func meanColour(of url: URL) -> Colour? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 {
            r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2]); n += 1
        }
        guard n > 0 else { return nil }
        return Colour(red: r / n / 255, green: g / n / 255, blue: b / n / 255)
    }
}

/// Runs a program with a time limit and returns its exit status and output.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
    }

    static func run(_ path: String, _ args: [String], environment: [String: String]? = nil, timeout: TimeInterval = 30) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let environment { process.environment = environment }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collected = NSMutableData()
        let lock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            lock.lock(); collected.append(data); lock.unlock()
        }
        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return Result(status: -1, output: "\(error)")
        }
        let end = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < end { Input.pause(0.05) }
        if process.isRunning {
            process.terminate()
            Input.pause(0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            pipe.fileHandleForReading.readabilityHandler = nil
            return Result(status: -2, output: "timed out after \(Int(timeout)) s: \(path) \(args.joined(separator: " "))")
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        lock.lock()
        let rest = pipe.fileHandleForReading.readDataToEndOfFile()
        collected.append(rest)
        let text = String(data: collected as Data, encoding: .utf8) ?? ""
        lock.unlock()
        return Result(status: process.terminationStatus, output: text)
    }
}
