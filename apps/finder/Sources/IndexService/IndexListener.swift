import Foundation
import IndexKit

/// Accepts connections from Nexus and Sight, each with its own session.
public final class IndexListenerDelegate: NSObject, NSXPCListenerDelegate {
    let core: IndexServiceCore
    /// The code requirement a client must meet; nil accepts any process of
    /// this user (an unsigned development build).
    public let clientRequirement: String?

    public init(core: IndexServiceCore, clientRequirement: String?) {
        self.core = core
        self.clientRequirement = clientRequirement
    }

    /// The requirement for clients, from how this agent is signed.
    public static func standardRequirement() -> String? {
        CodeSigning.requirement(allowing: IndexServiceName.clients, signer: CodeSigning.own)
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Another user's process is refused whatever its signature (the only
        // check left when the apps are signed ad hoc).
        guard CodeSigning.acceptsPeer(uid: connection.effectiveUserIdentifier) else { return false }
        // A client that does not meet it is cut off before any of its messages arrive.
        if let clientRequirement { connection.setCodeSigningRequirement(clientRequirement) }
        connection.exportedInterface = IndexXPC.serviceInterface()
        connection.remoteObjectInterface = IndexXPC.eventsInterface()
        let session = IndexSession(core: core, connection: connection)
        connection.exportedObject = session
        connection.resume()
        return true
    }
}

/// One client connection: its own narrowing cache, so Sight typing "conj" and
/// Nexus typing "lid" do not undo each other's.
final class IndexSession: NSObject, IndexServiceXPC, @unchecked Sendable {
    private let core: IndexServiceCore
    private weak var connection: NSXPCConnection?
    private let lock = NSLock()
    private var narrowing: SearchNarrowing?
    private var subscribed = false

    init(core: IndexServiceCore, connection: NSXPCConnection) {
        self.core = core
        self.connection = connection
    }

    func hello(_ home: String, reply: @escaping (Bool, Data) -> Void) {
        let core = self.core
        Task(priority: .userInitiated) {
            let accepted = core.serves(home: home)
            let status = accepted ? await core.status() : IndexStatus.empty
            reply(accepted, status.encoded())
        }
    }

    func search(_ text: String, limit: Int, scope: [String], reply: @escaping (Data) -> Void) {
        let core = self.core
        let previous = currentNarrowing()
        let limit = max(0, min(limit, 5_000))
        Task(priority: .userInitiated) {
            let index = await core.index()
            let found = await index.search(text, limit: limit, scope: scope.isEmpty ? nil : scope, narrowing: previous)
            self.keep(found.narrowing)
            reply(MatchCodec.encode(found.matches))
        }
    }

    func noteOpened(_ path: String) {
        let core = self.core
        Task(priority: .utility) {
            await core.index().noteOpened(path)
        }
    }

    func status(reply: @escaping (Data) -> Void) {
        let core = self.core
        Task(priority: .userInitiated) {
            reply(await core.status().encoded())
        }
    }

    func rebuild(reply: @escaping () -> Void) {
        let core = self.core
        Task(priority: .userInitiated) {
            await core.rebuild()
            reply()
        }
    }

    func subscribe() {
        lock.lock()
        let first = !subscribed
        subscribed = true
        lock.unlock()
        if first { core.register(self) }
    }

    func notifyChanged(_ files: Int) {
        guard let connection else { return }
        (connection.remoteObjectProxy as? IndexEventsXPC)?.indexChanged(files)
    }

    private func currentNarrowing() -> SearchNarrowing? {
        lock.lock()
        defer { lock.unlock() }
        return narrowing
    }

    private func keep(_ next: SearchNarrowing?) {
        lock.lock()
        narrowing = next
        lock.unlock()
    }
}
