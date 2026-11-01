import Foundation
import CryptoKit

public enum PackageError: Error, Equatable, CustomStringConvertible {
    case badMagic
    case corruptIndex
    case missingEntry(String)
    case unsafePath(String)
    case signatureInvalid
    case unsupportedFormat
    case incompatibleSchema(Int)
    case appTooOld(required: String)
    case hashMismatch(String)
    case unlistedFile(String)
    case decompressionFailed(String)
    case io(String)

    public var description: String {
        switch self {
        case .badMagic: return "This file is not a Police HQ content package."
        case .corruptIndex: return "The package index is damaged."
        case .missingEntry(let p): return "The package is missing \(p)."
        case .unsafePath(let p): return "The package contains an unsafe path (\(p))."
        case .signatureInvalid: return "The package signature is not valid for any trusted key."
        case .unsupportedFormat: return "The package format is not supported by this version of the app."
        case .incompatibleSchema(let v): return "The package uses content schema \(v), which this app cannot read."
        case .appTooOld(let r): return "This package requires app version \(r) or later."
        case .hashMismatch(let p): return "A file in the package was altered or damaged (\(p))."
        case .unlistedFile(let p): return "The package contains a file not listed in its signed manifest (\(p))."
        case .decompressionFailed(let p): return "A file could not be decompressed (\(p))."
        case .io(let m): return "File error: \(m)"
        }
    }
}

public struct PackageManifest: Codable, Equatable, Sendable {
    public struct FileEntry: Codable, Equatable, Sendable {
        public let path: String
        public let size: Int
        public let sha256: String
    }
    public let format: String
    public let formatVersion: Int
    public let packageVersion: String
    public let schemaVersion: Int
    public let minAppVersion: String
    public let createdAt: String
    public let signingKeyId: String
    public let description: String?
    public let files: [FileEntry]
    public let statement: String?
}

/// What a successful verification establishes — and what it does not.
public enum VerificationMeaning {
    public static let text = "A valid signature shows that the package was produced by the holder of a trusted signing key and has not been altered since it was signed. It does not establish that the law in it is correct, current or reviewed."
}

/// Reads and verifies `.phqpkg` containers (see tools/phq_ingest/package.py for the format).
public struct ContentPackageReader {
    public static let magic = Data("PHQPKG01".utf8)
    public static let supportedFormatVersion = 1
    public static let supportedSchemaVersion = 1

    struct IndexEntry: Decodable {
        let path: String
        let offset: Int
        let length: Int
        let size: Int
        let compression: String
    }
    struct Index: Decodable { let entries: [IndexEntry] }

    public let url: URL
    public let trustedKeys: [Curve25519.Signing.PublicKey]
    public let appVersion: String

    public init(url: URL, trustedKeys: [Curve25519.Signing.PublicKey], appVersion: String) {
        self.url = url
        self.trustedKeys = trustedKeys
        self.appVersion = appVersion
    }

    /// Verifies the whole package and, when `extractTo` is given, writes verified files there.
    /// Nothing is written unless every check passes first (verification happens before extraction).
    @discardableResult
    public func verify(extractTo: URL? = nil) throws -> PackageManifest {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw PackageError.io(error.localizedDescription) }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 16), head.count == 16, head.prefix(8) == Self.magic else {
            throw PackageError.badMagic
        }
        let n = head.suffix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard n > 0, n < 50_000_000, let indexData = try? handle.read(upToCount: Int(n)), indexData.count == Int(n),
              let index = try? JSONDecoder().decode(Index.self, from: indexData) else {
            throw PackageError.corruptIndex
        }
        let base = UInt64(16) + n
        var entries: [String: IndexEntry] = [:]
        for e in index.entries {
            if e.path.hasPrefix("/") || e.path.split(separator: "/").contains("..") || e.path.isEmpty {
                throw PackageError.unsafePath(e.path)
            }
            entries[e.path] = e
        }
        func read(_ e: IndexEntry) throws -> Data {
            try handle.seek(toOffset: base + UInt64(e.offset))
            guard let blob = try handle.read(upToCount: e.length), blob.count == e.length else { throw PackageError.corruptIndex }
            let data: Data
            switch e.compression {
            case "none": data = blob
            case "deflate-raw":
                // Apple's "zlib" algorithm is raw DEFLATE (RFC 1951), matching the packager.
                guard let d = try? (blob as NSData).decompressed(using: .zlib) as Data else {
                    throw PackageError.decompressionFailed(e.path)
                }
                data = d
            default: throw PackageError.unsupportedFormat
            }
            guard data.count == e.size else { throw PackageError.hashMismatch(e.path) }
            return data
        }
        guard let mEntry = entries["manifest.json"] else { throw PackageError.missingEntry("manifest.json") }
        guard let sEntry = entries["manifest.sig"] else { throw PackageError.missingEntry("manifest.sig") }
        let manifestData = try read(mEntry)
        let sigText = String(decoding: try read(sEntry), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: sigText),
              trustedKeys.contains(where: { $0.isValidSignature(signature, for: manifestData) }) else {
            throw PackageError.signatureInvalid
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let manifest = try? decoder.decode(PackageManifest.self, from: manifestData),
              manifest.format == "phq-content-package", manifest.formatVersion == Self.supportedFormatVersion else {
            throw PackageError.unsupportedFormat
        }
        guard manifest.schemaVersion == Self.supportedSchemaVersion else { throw PackageError.incompatibleSchema(manifest.schemaVersion) }
        guard Self.compareVersions(appVersion, manifest.minAppVersion) >= 0 else { throw PackageError.appTooOld(required: manifest.minAppVersion) }
        let listed = Set(manifest.files.map(\.path))
        for p in entries.keys where !listed.contains(p) && p != "manifest.json" && p != "manifest.sig" {
            throw PackageError.unlistedFile(p)
        }
        // Pass 1: verify every file. Pass 2 (only if all valid): write.
        for f in manifest.files {
            guard let e = entries[f.path] else { throw PackageError.missingEntry(f.path) }
            let data = try read(e)
            guard data.count == f.size, Self.sha256Hex(data) == f.sha256 else { throw PackageError.hashMismatch(f.path) }
        }
        if let dest = extractTo {
            let fm = FileManager.default
            for f in manifest.files {
                let data = try read(entries[f.path]!)
                let target = dest.appendingPathComponent(f.path)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: [.atomic])
                guard Self.sha256Hex(try Data(contentsOf: target)) == f.sha256 else { throw PackageError.hashMismatch(f.path) }
            }
            try manifestData.write(to: dest.appendingPathComponent("manifest.json"), options: [.atomic])
        }
        return manifest
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Compares dotted version strings numerically ("1.10" > "1.9").
    public static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}

/// Installs verified packages atomically and keeps the previous package for rollback.
///
/// Layout under `root` (Application Support/Content):
///   current/    — active package
///   previous/   — last good package (rollback target)
///   staging-*/  — temporary extraction; removed on failure
public final class ContentInstaller {
    public let root: URL
    private let fm = FileManager.default

    public init(root: URL) {
        self.root = root
    }

    public var currentDirectory: URL { root.appendingPathComponent("current", isDirectory: true) }
    public var previousDirectory: URL { root.appendingPathComponent("previous", isDirectory: true) }

    public var hasCurrent: Bool { fm.fileExists(atPath: currentDirectory.appendingPathComponent("content.sqlite").path) }
    public var hasPrevious: Bool { fm.fileExists(atPath: previousDirectory.appendingPathComponent("content.sqlite").path) }

    public func installedManifest(at dir: URL? = nil) -> PackageManifest? {
        let url = (dir ?? currentDirectory).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try? d.decode(PackageManifest.self, from: data)
    }

    /// Verify → extract into staging → swap. On any failure the current package is untouched.
    @discardableResult
    public func install(packageAt url: URL, trustedKeys: [Curve25519.Signing.PublicKey], appVersion: String) throws -> PackageManifest {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let manifest = try ContentPackageReader(url: url, trustedKeys: trustedKeys, appVersion: appVersion).verify(extractTo: staging)
            // Smoke-test the database before activating it.
            let probe = try ContentStore(packageDirectory: staging)
            _ = try probe.packageInfo()
            try applyProtection(to: staging)
            try swapIn(staging)
            return manifest
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    private func swapIn(_ staging: URL) throws {
        if fm.fileExists(atPath: previousDirectory.path) {
            try fm.removeItem(at: previousDirectory)
        }
        if fm.fileExists(atPath: currentDirectory.path) {
            try fm.moveItem(at: currentDirectory, to: previousDirectory)
        }
        do {
            try fm.moveItem(at: staging, to: currentDirectory)
        } catch {
            // Restore the last usable package if activation fails.
            if fm.fileExists(atPath: previousDirectory.path) && !fm.fileExists(atPath: currentDirectory.path) {
                try? fm.moveItem(at: previousDirectory, to: currentDirectory)
            }
            throw error
        }
    }

    /// Re-activates the previous package. Saved analyses keep their own recorded provenance.
    public func rollback() throws {
        guard hasPrevious else { throw PackageError.missingEntry("previous package") }
        let temp = root.appendingPathComponent("rollback-\(UUID().uuidString)", isDirectory: true)
        if fm.fileExists(atPath: currentDirectory.path) { try fm.moveItem(at: currentDirectory, to: temp) }
        try fm.moveItem(at: previousDirectory, to: currentDirectory)
        if fm.fileExists(atPath: temp.path) { try fm.moveItem(at: temp, to: previousDirectory) }
    }

    /// Removes leftovers from interrupted installs.
    public func cleanUpStaging() {
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent.hasPrefix("staging-") || item.lastPathComponent.hasPrefix("rollback-") {
            try? fm.removeItem(at: item)
        }
    }

    private func applyProtection(to dir: URL) throws {
        #if os(iOS)
        // Published law is not secret, but we still protect it at rest until first unlock and keep it
        // out of device backups (it can be re-imported).
        try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: dir.path)
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var u = dir
        try u.setResourceValues(values)
    }
}

public enum TrustedKeys {
    /// Loads base64 raw Ed25519 public keys (one per line or as a JSON array) from the app bundle.
    public static func load(from url: URL) -> [Curve25519.Signing.PublicKey] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let candidates: [String]
        if let data = text.data(using: .utf8), let arr = try? JSONDecoder().decode([String].self, from: data) {
            candidates = arr
        } else {
            candidates = text.split(whereSeparator: \.isNewline).map(String.init)
        }
        return candidates.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let raw = Data(base64Encoded: trimmed) else { return nil }
            return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        }
    }
}
