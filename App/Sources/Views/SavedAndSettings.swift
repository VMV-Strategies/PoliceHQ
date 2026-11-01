import SwiftUI
import UniformTypeIdentifiers
import PoliceHQCore

extension UTType {
    static let phqPackage = UTType(importedAs: "ca.example.policehq.content-package")
    static let phqScenario = UTType(importedAs: "ca.example.policehq.scenario-export")
}

struct SavedView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var importData: Data?
    @State private var passphrase = ""

    var body: some View {
        List {
            Section("Situations") {
                if model.scenarios.isEmpty { Text("No saved situations.").foregroundStyle(.secondary) }
                ForEach(model.scenarios) { s in
                    NavigationLink(value: Route.scenario(s.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(s.title).lineLimit(1)
                                if s.isTraining { Text("Training").font(.caption2.weight(.bold)).foregroundStyle(.purple) }
                            }
                            Text("Updated \(s.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in for i in idx { model.delete(model.scenarios[i]) } }
                Button("Import exported situation…", systemImage: "square.and.arrow.down") { importing = true }
            }
            .privacySensitive()
            Section("Bookmarks") {
                if model.bookmarks.isEmpty { Text("No bookmarks.").foregroundStyle(.secondary) }
                ForEach(model.bookmarks) { b in
                    NavigationLink(value: Route.provision(b.provisionID)) {
                        VStack(alignment: .leading) { Text(b.label); Text(b.sourceTitle).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section("Saved searches") {
                if model.savedSearches.isEmpty { Text("No saved searches.").foregroundStyle(.secondary) }
                ForEach(model.savedSearches) { s in
                    NavigationLink {
                        SavedSearchResultsView(search: s)
                    } label: {
                        Text("\(s.name) · \(s.query.mode.title)")
                    }
                }
                .onDelete { idx in for i in idx { model.deleteSearch(model.savedSearches[i]) } }
            }
            Section("Retention") {
                Text("Situations not updated for \(model.settings.retentionDays) days are deleted automatically when the app opens. Change this in Settings.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Saved")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.phqScenario, .json, .data]) { result in
            if case .success(let url) = result {
                let ok = url.startAccessingSecurityScopedResource()
                importData = try? Data(contentsOf: url)
                if ok { url.stopAccessingSecurityScopedResource() }
            }
        }
        .alert("Passphrase", isPresented: Binding(get: { importData != nil }, set: { if !$0 { importData = nil } })) {
            SecureField("Leave empty if none", text: $passphrase)
            Button("Import") {
                if let d = importData { model.importScenario(data: d, passphrase: passphrase.isEmpty ? nil : passphrase) }
                importData = nil
                passphrase = ""
            }
            Button("Cancel", role: .cancel) { importData = nil }
        }
    }
}

struct SavedSearchResultsView: View {
    let search: SavedSearch
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            ForEach((try? model.store?.search(search.query)) ?? []) { SearchHitRow(hit: $0) }
        }
        .navigationTitle(search.name)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmErase = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Explanation level") {
                Picker("Default level", selection: $model.settings.explanationLevel) {
                    ForEach(ExplanationLevel.allCases) { Text($0.title).tag($0) }
                }
                Text("Levels change wording only. Legal conditions, exceptions, citations, cautions, quotations and calculations never change.").font(.footnote)
            }
            Section("Location (manual)") {
                Picker("Default city", selection: $model.settings.defaultCity) {
                    Text("Not selected").tag(CitySelection.notSelected)
                    Text("Brampton").tag(CitySelection.brampton)
                    Text("Mississauga").tag(CitySelection.mississauga)
                }
                Text("No GPS or network is used. One city's by-laws are never applied to the other.").font(.footnote)
            }
            Section("On-device assistance") {
                Toggle("Use on-device language model when available", isOn: $model.settings.onDeviceAssistanceEnabled)
                switch model.assistant.availability {
                case .available(let d): Label("Available: \(d)", systemImage: "checkmark.circle")
                case .unavailable(let r): Label(r, systemImage: "xmark.circle").font(.footnote)
                }
                Text("Runs only on this iPhone. There is no cloud fallback. Proposed facts must be confirmed before use; generated explanations that cite anything outside the retrieved sources are discarded.")
                    .font(.footnote)
            }
            Section("Privacy and records") {
                Stepper("Delete situations after \(model.settings.retentionDays) days", value: $model.settings.retentionDays, in: 1...365)
                Toggle("Include situations in device backups", isOn: $model.settings.includeScenariosInDeviceBackup)
                Text("Situations are encrypted with a key kept in this device's keychain (this device only). If included in backups, the encrypted files are copied but the key is not, so they cannot be read on another device. Deleting removes the file from the app; copies in earlier backups or exported files are outside the app's control.")
                    .font(.footnote)
                Button("Erase all local records", role: .destructive) { confirmErase = true }
            }
            Section("Content") {
                NavigationLink(value: Route.contentStatus) { Label("Content status, import and rollback", systemImage: "shippingbox") }
                TextField("Optional update address (https://…)", text: $model.settings.updateURL)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
            }
            Section("About") {
                Text("Police HQ supports human judgment. It does not determine guilt, direct charges, create grounds or guarantee legal compliance.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Erase all situations, bookmarks and saved searches? This cannot be undone.", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) { model.eraseAllLocalRecords() }
        }
    }
}

struct ContentStatusView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false

    var body: some View {
        List {
            Section("Installed package") {
                if let m = model.manifest {
                    LabeledText(title: "Package version", text: m.packageVersion)
                    LabeledText(title: "Content-package publication date", text: m.createdAt)
                    LabeledText(title: "Signing key", text: m.signingKeyId)
                    if let info = try? model.store?.packageInfo() {
                        LabeledText(title: "Import date (not a currency date)", text: info.importDate)
                    }
                } else {
                    Text(model.contentMessage ?? "No package installed.")
                }
                Text(VerificationMeaning.text).font(.footnote)
            }
            Section("Dates are kept distinct") {
                Text("Import date · source consolidation date · provision effective date · last official-source verification · package publication date · editorial/legal-review date. “Imported today” never means “law current today”.")
                    .font(.footnote)
            }
            if let store = model.store, let sources = try? store.allSources() {
                Section("Coverage by jurisdiction") {
                    let groups = Dictionary(grouping: sources, by: \.jurisdictionLabel)
                    ForEach(groups.keys.sorted(), id: \.self) { k in
                        HStack { Text(k); Spacer(); Text("\(groups[k]?.count ?? 0)").monospacedDigit() }
                    }
                }
                Section("Verification and review") {
                    let unverified = sources.filter { $0.verificationStatus == "Not verified" }.count
                    HStack { Text("Not verified against publisher"); Spacer(); Text("\(unverified) of \(sources.count)") }
                    HStack { Text("Used in guided analysis"); Spacer(); Text("\(sources.filter(\.trustedForGuidance).count)") }
                    HStack { Text("Reference conversions"); Spacer(); Text("\(sources.filter(\.isReferenceConversion).count)") }
                    HStack { Text("Image-only sources"); Spacer(); Text("\(sources.filter { $0.extractionQuality == .imageOnly }.count)") }
                    Text("Historical versions available: none. Each source is installed as a single consolidation.").font(.footnote)
                }
                Section("Missing material and known gaps") {
                    ForEach((try? store.coverageGaps()) ?? []) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g.title).font(.subheadline.weight(.semibold))
                            Text(g.description).font(.footnote)
                            if let a = g.acquisition { Text("How to obtain: \(a)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section("Install or update") {
                Button("Import package from Files…", systemImage: "square.and.arrow.down") { importing = true }
                    .disabled(model.installInProgress)
                Button("Download update from configured address", systemImage: "arrow.down.circle") { Task { await model.downloadUpdate() } }
                    .disabled(model.settings.updateURL.isEmpty || model.installInProgress)
                Button("Roll back to previous package", systemImage: "arrow.uturn.backward") { model.rollback() }
                    .disabled(!model.installer.hasPrevious)
                if model.installInProgress { ProgressView("Verifying and installing…") }
                Text("Updates are only downloaded when you ask. Every package is signature- and hash-checked before it replaces the current one; a failed install keeps the last usable package.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Content status")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.phqPackage, .data]) { result in
            if case .success(let url) = result { Task { await model.importPackage(from: url) } }
        }
    }
}
