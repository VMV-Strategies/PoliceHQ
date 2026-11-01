import Foundation
import CryptoKit
import CommonCrypto
#if canImport(Security)
import Security
#endif

/// Supplies the symmetric key used to encrypt saved scenarios.
public protocol ScenarioKeyProvider {
    func key() throws -> SymmetricKey
}

/// Keychain-backed key: 256-bit, created on first use, accessible only when the device is
/// unlocked and never migrated to another device or included in backups.
public final class KeychainKeyProvider: ScenarioKeyProvider {
    private let service: String
    private let account = "scenario-encryption-key-v1"

    public init(service: String = "ca.example.policehq.scenarios") {
        self.service = service
    }

    public func key() throws -> SymmetricKey {
        if let existing = try read() { return SymmetricKey(data: existing) }
        let new = SymmetricKey(size: .bits256)
        let data = new.withUnsafeBytes { Data($0) }
        try write(data)
        return new
    }

    private func read() throws -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ScenarioStoreError.keychain(status) }
        return out as? Data
    }

    private func write(_ data: Data) throws {
        let attrs: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw ScenarioStoreError.keychain(status) }
    }

    /// Deleting the key makes every saved scenario unreadable (used by "Erase all local data").
    public func destroy() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

/// Fixed key for tests only.
public struct StaticKeyProvider: ScenarioKeyProvider {
    let k: SymmetricKey
    public init(_ k: SymmetricKey = SymmetricKey(size: .bits256)) { self.k = k }
    public func key() throws -> SymmetricKey { k }
}

public enum ScenarioStoreError: Error, Equatable {
    case keychain(OSStatus)
    case corrupt
    case unsupportedVersion(Int)
    case wrongPassphrase
    case weakPassphrase
}

/// Encrypted, local-only scenario storage. Each scenario is a separate AES-GCM sealed file.
/// Nothing here logs scenario content.
public final class ScenarioStore {
    public let directory: URL
    private let keyProvider: ScenarioKeyProvider
    private let fm = FileManager.default
    public var excludeFromBackup: Bool

    public init(directory: URL, keyProvider: ScenarioKeyProvider, excludeFromBackup: Bool = true) throws {
        self.directory = directory
        self.keyProvider = keyProvider
        self.excludeFromBackup = excludeFromBackup
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try protect(directory)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // Exact round-trip of timestamps (ISO 8601 would drop sub-second precision).
        e.dateEncodingStrategy = .deferredToDate
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return d
    }()

    private func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).phqs") }

    public func save(_ scenario: Scenario) throws {
        let plain = try Self.encoder.encode(scenario)
        let sealed = try AES.GCM.seal(plain, using: try keyProvider.key())
        guard let combined = sealed.combined else { throw ScenarioStoreError.corrupt }
        let target = url(for: scenario.id)
        #if os(iOS)
        try combined.write(to: target, options: [.atomic, .completeFileProtection])
        #else
        try combined.write(to: target, options: [.atomic])
        #endif
        try protect(target)
    }

    public func load(id: UUID) throws -> Scenario {
        let data = try Data(contentsOf: url(for: id))
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: try keyProvider.key())
        let s = try Self.decoder.decode(Scenario.self, from: plain)
        guard s.schemaVersion <= Scenario.currentSchemaVersion else { throw ScenarioStoreError.unsupportedVersion(s.schemaVersion) }
        return s
    }

    public func list() throws -> [Scenario] {
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "phqs" }
        return files.compactMap { f in UUID(uuidString: f.deletingPathExtension().lastPathComponent).flatMap { try? load(id: $0) } }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Deletes the encrypted file. Limits: the OS may retain copies in backups made before deletion
    /// (if backups were enabled) and flash storage does not guarantee physical erasure; encryption
    /// with a device-only key is the main protection.
    public func delete(id: UUID) throws {
        let u = url(for: id)
        if fm.fileExists(atPath: u.path) { try fm.removeItem(at: u) }
    }

    /// Deletes scenarios not updated within `days`.
    @discardableResult
    public func applyRetention(days: Int, now: Date = Date()) throws -> Int {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var removed = 0
        for s in try list() where s.updatedAt < cutoff {
            try delete(id: s.id)
            removed += 1
        }
        return removed
    }

    private func protect(_ url: URL) throws {
        #if os(iOS)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = excludeFromBackup
        var u = url
        try u.setResourceValues(values)
    }

    // MARK: Export / import

    public struct ExportEnvelope: Codable {
        public let format: String
        public let version: Int
        public let encrypted: Bool
        public let salt: String?
        public let iterations: Int?
        public let payload: String      // base64: AES-GCM combined box (encrypted) or JSON (plain)
        public let exportedAt: Date
        public let warning: String
    }

    public static let exportWarning = "This file contains scenario information. Once exported it is outside the app's protection: anyone with the file (and passphrase, if one was set) can read it. Store and delete it according to your service's rules."

    /// Exports one scenario. With a passphrase the payload is encrypted (PBKDF2-SHA256 + AES-GCM);
    /// without one it is readable JSON. Provenance and source versions are preserved either way.
    public static func export(_ scenario: Scenario, passphrase: String?) throws -> Data {
        let plain = try encoder.encode(scenario)
        if let pass = passphrase {
            guard pass.count >= 12 else { throw ScenarioStoreError.weakPassphrase }
            var saltBytes = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
            let salt = Data(saltBytes)
            let iterations = 600_000
            let key = try deriveKey(pass, salt: salt, iterations: iterations)
            let box = try AES.GCM.seal(plain, using: key)
            guard let combined = box.combined else { throw ScenarioStoreError.corrupt }
            let env = ExportEnvelope(format: "phq-scenario-export", version: 1, encrypted: true, salt: salt.base64EncodedString(),
                                     iterations: iterations, payload: combined.base64EncodedString(), exportedAt: Date(), warning: exportWarning)
            return try encoder.encode(env)
        }
        let env = ExportEnvelope(format: "phq-scenario-export", version: 1, encrypted: false, salt: nil, iterations: nil,
                                 payload: plain.base64EncodedString(), exportedAt: Date(), warning: exportWarning)
        return try encoder.encode(env)
    }

    /// Re-imports an exported scenario, preserving its id, provenance, facts and audit trail.
    public static func importScenario(_ data: Data, passphrase: String?) throws -> Scenario {
        let env = try decoder.decode(ExportEnvelope.self, from: data)
        guard env.format == "phq-scenario-export", env.version == 1, let payload = Data(base64Encoded: env.payload) else {
            throw ScenarioStoreError.corrupt
        }
        let plain: Data
        if env.encrypted {
            guard let pass = passphrase, let saltB64 = env.salt, let salt = Data(base64Encoded: saltB64), let it = env.iterations else {
                throw ScenarioStoreError.wrongPassphrase
            }
            let key = try deriveKey(pass, salt: salt, iterations: it)
            do {
                plain = try AES.GCM.open(try AES.GCM.SealedBox(combined: payload), using: key)
            } catch {
                throw ScenarioStoreError.wrongPassphrase
            }
        } else {
            plain = payload
        }
        var s = try decoder.decode(Scenario.self, from: plain)
        guard s.schemaVersion <= Scenario.currentSchemaVersion else { throw ScenarioStoreError.unsupportedVersion(s.schemaVersion) }
        s.audit.append(AuditEntry(at: Date(), action: "imported from export file"))
        return s
    }

    static func deriveKey(_ passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        guard !passphrase.isEmpty else { throw ScenarioStoreError.wrongPassphrase }
        var derived = [UInt8](repeating: 0, count: 32)
        let pw = Array(passphrase.utf8)
        let status = salt.withUnsafeBytes { saltPtr -> Int32 in
            pw.withUnsafeBufferPointer { pwPtr -> Int32 in
                pwPtr.baseAddress!.withMemoryRebound(to: Int8.self, capacity: pw.count) { pwBase in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pwBase, pw.count,
                                         saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                         &derived, derived.count)
                }
            }
        }
        guard status == Int32(kCCSuccess) else { throw ScenarioStoreError.corrupt }
        return SymmetricKey(data: Data(derived))
    }
}
