import Foundation
import SwiftUI
import Observation
import CryptoKit
import PoliceHQCore

/// Non-sensitive preferences (stored in UserDefaults). Scenario content is never stored here.
struct AppSettings: Codable, Equatable {
    var explanationLevel: ExplanationLevel = .plainLanguage
    var defaultCity: CitySelection = .notSelected
    var onDeviceAssistanceEnabled: Bool = false
    var retentionDays: Int = 30
    var includeScenariosInDeviceBackup: Bool = false
    var updateURL: String = ""

    static let key = "phq.settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: AppSettings.key) }
    }
}

struct Bookmark: Codable, Hashable, Identifiable {
    var id: String { provisionID }
    let provisionID: String
    let sourceID: String
    let label: String
    let sourceTitle: String
    let createdAt: Date
}

struct SavedSearch: Codable, Hashable, Identifiable {
    let id: UUID
    let query: SearchQuery
    let name: String
}

/// Encrypted local storage for bookmarks and saved searches (search text can be sensitive).
struct EncryptedJSONFile<T: Codable> {
    let url: URL
    let keyProvider: ScenarioKeyProvider

    func read() -> T? {
        guard let data = try? Data(contentsOf: url),
              let box = try? AES.GCM.SealedBox(combined: data),
              let key = try? keyProvider.key(),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: plain)
    }

    func write(_ value: T) throws {
        let plain = try JSONEncoder().encode(value)
        let sealed = try AES.GCM.seal(plain, using: try keyProvider.key())
        guard let combined = sealed.combined else { return }
        try combined.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

@MainActor
@Observable
final class AppModel {
    // Content
    private(set) var store: ContentStore?
    private(set) var manifest: PackageManifest?
    private(set) var contentMessage: String?
    private(set) var installInProgress = false

    // Local records
    private(set) var scenarios: [Scenario] = []
    private(set) var bookmarks: [Bookmark] = []
    private(set) var savedSearches: [SavedSearch] = []
    var lastError: String?

    // Settings & assistance
    var settings = AppSettings.load() {
        didSet {
            settings.save()
            if oldValue.onDeviceAssistanceEnabled != settings.onDeviceAssistanceEnabled { assistant = AssistantFactory.make(enabledByUser: settings.onDeviceAssistanceEnabled) }
            if oldValue.includeScenariosInDeviceBackup != settings.includeScenariosInDeviceBackup { scenarioStore?.excludeFromBackup = !settings.includeScenariosInDeviceBackup }
        }
    }
    private(set) var assistant: any LocalAssistant = UnavailableAssistant(reason: "Not initialized")

    let installer: ContentInstaller
    private var scenarioStore: ScenarioStore?
    private let keyProvider = KeychainKeyProvider()
    private let supportDirectory: URL

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    init() {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        supportDirectory = support
        installer = ContentInstaller(root: support.appendingPathComponent("Content", isDirectory: true))
    }

    var trustedKeys: [Curve25519.Signing.PublicKey] {
        guard let url = Bundle.main.url(forResource: "TrustedKeys", withExtension: "txt") else { return [] }
        return TrustedKeys.load(from: url)
    }

    func bootstrap() {
        installer.cleanUpStaging()
        assistant = AssistantFactory.make(enabledByUser: settings.onDeviceAssistanceEnabled)
        if !installer.hasCurrent { installBundledPackageIfPresent() }
        openContent()
        openLocalRecords()
    }

    // MARK: Content

    func openContent() {
        guard installer.hasCurrent else {
            store = nil
            manifest = nil
            contentMessage = "No content package is installed. Import a signed package from Files (Settings › Content status)."
            return
        }
        do {
            store = try ContentStore(packageDirectory: installer.currentDirectory)
            manifest = installer.installedManifest()
            contentMessage = nil
        } catch {
            store = nil
            contentMessage = "The installed content could not be opened. You can roll back to the previous package in Content status."
        }
    }

    private func installBundledPackageIfPresent() {
        guard let dir = Bundle.main.url(forResource: "BundledContent", withExtension: nil),
              let pkg = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                .first(where: { $0.pathExtension == "phqpkg" }) else { return }
        _ = try? installer.install(packageAt: pkg, trustedKeys: trustedKeys, appVersion: Self.appVersion)
    }

    /// Installs a package chosen through Files. Verification happens before anything is replaced.
    func importPackage(from url: URL) async {
        installInProgress = true
        defer { installInProgress = false }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let keys = trustedKeys
        let installer = self.installer
        let version = Self.appVersion
        do {
            // Copy first so the security-scoped file can be released, then verify and install off the main actor.
            let local = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).phqpkg")
            try FileManager.default.copyItem(at: url, to: local)
            defer { try? FileManager.default.removeItem(at: local) }
            let manifest = try await Task.detached(priority: .userInitiated) {
                try installer.install(packageAt: local, trustedKeys: keys, appVersion: version)
            }.value
            openContent()
            contentMessage = "Installed package \(manifest.packageVersion). \(VerificationMeaning.text)"
        } catch let e as PackageError {
            lastError = e.description + " The previously installed package (if any) is still in use."
        } catch {
            lastError = "Import failed: \(error.localizedDescription). The previously installed package (if any) is still in use."
        }
    }

    /// User-initiated online update: downloads a package from the configured URL, then verifies and installs it.
    func downloadUpdate() async {
        guard let url = URL(string: settings.updateURL), url.scheme == "https" else {
            lastError = "Enter an https:// update address in Settings first."
            return
        }
        do {
            let (tmp, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                lastError = "The update server did not return a package."
                return
            }
            await importPackage(from: tmp)
        } catch {
            lastError = "Download failed. No changes were made. (\(error.localizedDescription))"
        }
    }

    func rollback() {
        do {
            try installer.rollback()
            openContent()
            contentMessage = "Rolled back to the previous package. Saved situations keep the versions recorded when they were analyzed."
        } catch {
            lastError = "No previous package is available to roll back to."
        }
    }

    // MARK: Local records

    private var bookmarksFile: EncryptedJSONFile<[Bookmark]> {
        EncryptedJSONFile(url: supportDirectory.appendingPathComponent("bookmarks.enc"), keyProvider: keyProvider)
    }
    private var searchesFile: EncryptedJSONFile<[SavedSearch]> {
        EncryptedJSONFile(url: supportDirectory.appendingPathComponent("searches.enc"), keyProvider: keyProvider)
    }

    func openLocalRecords() {
        do {
            let store = try ScenarioStore(directory: supportDirectory.appendingPathComponent("Scenarios", isDirectory: true),
                                          keyProvider: keyProvider,
                                          excludeFromBackup: !settings.includeScenariosInDeviceBackup)
            scenarioStore = store
            _ = try? store.applyRetention(days: settings.retentionDays)
            scenarios = (try? store.list()) ?? []
        } catch {
            lastError = "Saved situations could not be opened. The device may be locked."
        }
        bookmarks = bookmarksFile.read() ?? []
        savedSearches = searchesFile.read() ?? []
    }

    func save(_ scenario: Scenario) {
        guard let s = scenarioStore else { return }
        do {
            try s.save(scenario)
            if let i = scenarios.firstIndex(where: { $0.id == scenario.id }) { scenarios[i] = scenario } else { scenarios.insert(scenario, at: 0) }
        } catch {
            lastError = "The situation could not be saved."
        }
    }

    func delete(_ scenario: Scenario) {
        try? scenarioStore?.delete(id: scenario.id)
        scenarios.removeAll { $0.id == scenario.id }
    }

    func importScenario(data: Data, passphrase: String?) {
        do {
            let s = try ScenarioStore.importScenario(data, passphrase: passphrase)
            save(s)
        } catch ScenarioStoreError.wrongPassphrase {
            lastError = "The passphrase is incorrect, or the file was altered."
        } catch {
            lastError = "This file could not be imported."
        }
    }

    /// Erases every local record and the scenario key. Content packages are kept.
    func eraseAllLocalRecords() {
        for s in scenarios { try? scenarioStore?.delete(id: s.id) }
        scenarios = []
        try? FileManager.default.removeItem(at: bookmarksFile.url)
        try? FileManager.default.removeItem(at: searchesFile.url)
        bookmarks = []
        savedSearches = []
        keyProvider.destroy()
        openLocalRecords()
    }

    func toggleBookmark(_ p: Provision, sourceTitle: String) {
        if let i = bookmarks.firstIndex(where: { $0.provisionID == p.id }) {
            bookmarks.remove(at: i)
        } else {
            bookmarks.insert(Bookmark(provisionID: p.id, sourceID: p.sourceID, label: p.label, sourceTitle: sourceTitle, createdAt: Date()), at: 0)
        }
        try? bookmarksFile.write(bookmarks)
    }

    func isBookmarked(_ p: Provision) -> Bool { bookmarks.contains { $0.provisionID == p.id } }

    func saveSearch(_ q: SearchQuery) {
        savedSearches.insert(SavedSearch(id: UUID(), query: q, name: q.text), at: 0)
        try? searchesFile.write(savedSearches)
    }

    func deleteSearch(_ s: SavedSearch) {
        savedSearches.removeAll { $0.id == s.id }
        try? searchesFile.write(savedSearches)
    }

    /// Records which package, guide versions and sources informed an analysis, without rewriting earlier records.
    func recordProvenance(_ analysis: ScenarioAnalysis, into scenario: inout Scenario) {
        if scenario.provenance == nil {
            scenario.provenance = analysis.provenance
        }
    }
}
