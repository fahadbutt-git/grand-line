import Foundation

/// What the Grand Line Index service answers, over XPC. Results come back as one
/// `MatchCodec` buffer; status as `IndexStatus.encoded()`.
@objc public protocol IndexServiceXPC {
    /// The first call on a connection. `accepted` is false when the service
    /// indexes another home folder than the client's (a journey run with a
    /// fixture home, say): the client then keeps to its own copy.
    func hello(_ home: String, reply: @escaping (_ accepted: Bool, _ status: Data) -> Void)
    /// `scope` empty: the whole index.
    func search(_ text: String, limit: Int, scope: [String], reply: @escaping (Data) -> Void)
    func noteOpened(_ path: String)
    func status(reply: @escaping (Data) -> Void)
    /// Replies once the walk has started.
    func rebuild(reply: @escaping () -> Void)
    /// Asks for `IndexEventsXPC.indexChanged` calls on this connection.
    func subscribe()
}

/// What the service calls back on a client that subscribed.
@objc public protocol IndexEventsXPC {
    /// At most about once a second while files change.
    func indexChanged(_ files: Int)
}

/// The Mach service name and the processes allowed on each side.
public enum IndexServiceName {
    /// The launchd label and Mach service of the installed agent.
    public static let standard = "com.grandline.index"
    /// The bundle identifier of Grand Line Index.app.
    public static let bundleID = "com.grandline.index"
    /// The apps that may ask the service.
    public static let clients = ["com.grandline.nexus", "com.grandline.sight"]
    /// Picks another service, for the journeys: they start their own agent
    /// with a fixture home under a label beginning `com.grandline.index.`.
    public static let environmentKey = "GRAND_LINE_INDEX_SERVICE"

    /// The service an app should use, or nil for none. A journey run
    /// (GRAND_LINE_JOURNEY=1) uses only the service it names, never the Mac's
    /// own, whose index is of the real home folder.
    public static func forClient(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let named = environment[environmentKey], isOurs(named) { return named }
        if environment["GRAND_LINE_JOURNEY"] == "1" { return nil }
        return standard
    }

    /// The name the service itself listens on.
    public static func forService(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let named = environment[environmentKey], isOurs(named) { return named }
        return standard
    }

    static func isOurs(_ name: String) -> Bool {
        name == standard || name.hasPrefix(standard + ".")
    }
}

enum IndexXPC {
    static func serviceInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: IndexServiceXPC.self)
        let strings = NSSet(array: [NSArray.self, NSString.self]) as! Set<AnyHashable>
        interface.setClasses(
            strings, for: #selector(IndexServiceXPC.search(_:limit:scope:reply:)), argumentIndex: 2, ofReply: false
        )
        return interface
    }

    static func eventsInterface() -> NSXPCInterface {
        NSXPCInterface(with: IndexEventsXPC.self)
    }
}

/// Resumes a continuation once: with the reply, or with nil when the
/// connection fails or the reply is late.
final class Once<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?

    init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
