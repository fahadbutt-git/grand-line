import BrowserKit
import Foundation
import Network

/// The loopback address the Google consent page sends its code back to
/// (http://127.0.0.1:<port>), on a port the system picks. It accepts local
/// connections only, answers the browser with a short page, and hands the
/// first redirect it sees to whoever waits for it.
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "nexus.drive.loopback")
    private let lock = NSLock()
    private var ready: CheckedContinuation<UInt16, Error>?
    private var waiting: CheckedContinuation<GoogleOAuth.Callback, Error>?
    private var received: GoogleOAuth.Callback?
    private var finished = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening and returns the port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            lock.lock()
            ready = continuation
            lock.unlock()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.resumeReady(.success(self.listener.port?.rawValue ?? 0))
                case .failed(let error):
                    self.resumeReady(.failure(error))
                case .cancelled:
                    self.resumeReady(.failure(CancellationError()))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }
    }

    /// The browser's redirect, or an error after `timeout` (the person closed
    /// the page and never came back).
    func callback(timeout: TimeInterval) async throws -> GoogleOAuth.Callback {
        let timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self?.finish(.failure(URLError(.timedOut)))
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GoogleOAuth.Callback, Error>) in
                lock.lock()
                if let received {
                    lock.unlock()
                    continuation.resume(returning: received)
                    return
                }
                if finished {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiting = continuation
                lock.unlock()
            }
        } onCancel: { [weak self] in
            self?.finish(.failure(CancellationError()))
        }
    }

    func stop() {
        listener.cancel()
    }

    private func resumeReady(_ result: Result<UInt16, Error>) {
        lock.lock()
        let continuation = ready
        ready = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func finish(_ result: Result<GoogleOAuth.Callback, Error>) {
        lock.lock()
        if case .success(let callback) = result, received == nil { received = callback }
        finished = true
        let continuation = waiting
        waiting = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            let head = String(decoding: buffer, as: UTF8.self)
            if head.contains("\r\n\r\n") || complete || error != nil || buffer.count > 16_384 {
                self.answer(connection, head: head)
            } else {
                self.read(connection, buffer: buffer)
            }
        }
    }

    private func answer(_ connection: NWConnection, head: String) {
        guard let callback = GoogleOAuth.callback(fromRequest: head) else {
            send(connection, status: "404 Not Found", body: "")
            return
        }
        let body = callback.code != nil
            ? Self.page("Google Drive is connected", "You can close this tab and return to Nexus.")
            : Self.page("Google Drive was not connected", "You can close this tab. Nexus did not get access.")
        send(connection, status: "200 OK", body: body)
        finish(.success(callback))
    }

    private func send(_ connection: NWConnection, status: String, body: String) {
        let bytes = Data(body.utf8)
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        connection.send(content: Data(response.utf8) + bytes, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func page(_ title: String, _ text: String) -> String {
        """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><title>\(title)</title>
        <style>body{font:15px -apple-system,system-ui,sans-serif;margin:15vh auto;max-width:28em;padding:0 1.5em;color:#1d1d1f}
        @media (prefers-color-scheme: dark){body{background:#1e1e1e;color:#f2f2f2}}h1{font-size:20px;font-weight:600}</style>
        </head><body><h1>\(title)</h1><p>\(text)</p></body></html>
        """
    }
}
