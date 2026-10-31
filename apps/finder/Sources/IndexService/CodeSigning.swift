import CryptoKit
import Foundation
import Security

/// Who may talk to whom. The Mach service is already limited to processes of
/// the same user in the same login session (launchd's per-user domain); on top
/// of that, each side checks the other's code signature.
public enum CodeSigning {
    /// How the running program is signed.
    public struct Signer: Equatable, Sendable {
        /// The Apple team of a Developer ID or Apple Development certificate.
        public var teamID: String?
        /// SHA-1 of the leaf certificate, for a certificate without a team (a
        /// self-signed signing identity made on this Mac).
        public var leafSHA1: String?
        /// Signed with `codesign --sign -`: no certificate at all.
        public var isAdHoc: Bool

        public init(teamID: String? = nil, leafSHA1: String? = nil, isAdHoc: Bool = false) {
            self.teamID = teamID
            self.leafSHA1 = leafSHA1
            self.isAdHoc = isAdHoc
        }
    }

    /// The requirement the other side must meet: one of `identifiers`, signed
    /// the way this program is.
    ///
    /// - Team: the same Apple team, anchored at Apple.
    /// - Own certificate: the same leaf certificate.
    /// - Ad hoc (what lib/native-apps.sh does today): the identifier only.
    ///   An ad-hoc signature proves nothing about who made the program, so any
    ///   process of the same user could sign itself with that identifier; the
    ///   per-user Mach service is the real boundary then.
    /// - Unsigned (a `swift run` during development): nil, no requirement.
    public static func requirement(allowing identifiers: [String], signer: Signer?) -> String? {
        guard let signer, !identifiers.isEmpty else { return nil }
        let names = identifiers.map { "identifier \"\($0)\"" }.joined(separator: " or ")
        let anyOf = "(" + names + ")"
        if let team = signer.teamID, !team.isEmpty {
            return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and \(anyOf)"
        }
        if let leaf = signer.leafSHA1, !leaf.isEmpty {
            return "certificate leaf = H\"\(leaf)\" and \(anyOf)"
        }
        return anyOf
    }

    /// How this program is signed, read once.
    public static let own: Signer? = current()

    /// How this program is signed, or nil when it is not.
    public static func current() -> Signer? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        // Unsigned code has no identifier.
        guard dictionary[kSecCodeInfoIdentifier as String] != nil else { return nil }
        let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        let signatureFlags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let adHocFlag: UInt32 = 0x0002 // kSecCodeSignatureAdhoc
        var leaf: String?
        if let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate], let first = certificates.first {
            let bytes = SecCertificateCopyData(first) as Data
            leaf = Insecure.SHA1.hash(data: bytes).map { String(format: "%02X", $0) }.joined()
        }
        return Signer(teamID: team, leafSHA1: leaf, isAdHoc: signatureFlags & adHocFlag != 0)
    }
}
