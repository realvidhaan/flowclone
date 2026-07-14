import SwiftUI
import PersistenceKit

/// Personal-dictionary editor. Depends only on `DataStore` so it can be rendered
/// headlessly in tests. State is initialized at construction (not just on
/// appear) so snapshots show data.
public struct DictionarySettingsView: View {
    let dataStore: DataStore
    @State private var entries: [DictionaryEntry]
    @State private var newWritten = ""
    @State private var newSpoken = ""

    public init(dataStore: DataStore) {
        self.dataStore = dataStore
        _entries = State(initialValue: dataStore.dictionaryEntries())
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text("Words and names FlowClone should recognize and spell correctly.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)

            List {
                ForEach(entries, id: \.persistentModelID) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.written).fontWeight(.medium)
                            if let spoken = entry.spoken, !spoken.isEmpty {
                                Text("spoken: \(spoken)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            dataStore.deleteDictionaryEntry(entry); reload()
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                TextField("Written form (e.g. Vidhaan)", text: $newWritten)
                TextField("Spoken (optional)", text: $newSpoken)
                Button("Add") {
                    let written = newWritten.trimmingCharacters(in: .whitespaces)
                    guard !written.isEmpty else { return }
                    let spoken = newSpoken.trimmingCharacters(in: .whitespaces)
                    dataStore.addDictionaryEntry(DictionaryEntry(written: written, spoken: spoken.isEmpty ? nil : spoken))
                    newWritten = ""; newSpoken = ""; reload()
                }
                .disabled(newWritten.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .onAppear(perform: reload)
    }

    private func reload() { entries = dataStore.dictionaryEntries() }
}

/// Per-app formatting-hint editor.
public struct AppProfilesSettingsView: View {
    let dataStore: DataStore
    @State private var profiles: [AppProfileRecord]

    public init(dataStore: DataStore) {
        self.dataStore = dataStore
        _profiles = State(initialValue: dataStore.appProfiles())
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text("How dictation is formatted per app (email vs casual text vs code).")
                .font(.caption).foregroundStyle(.secondary)
                .padding([.horizontal, .top])

            List {
                ForEach(profiles, id: \.persistentModelID) { profile in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { profile.enabled },
                                set: { profile.enabled = $0; dataStore.save() }
                            )).labelsHidden()
                            Text(profile.displayName).fontWeight(.medium)
                            Spacer()
                            Text(profile.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        TextField("Formatting hint", text: Binding(
                            get: { profile.formattingHint },
                            set: { profile.formattingHint = $0; dataStore.save() }
                        ), axis: .vertical)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// Searchable dictation history.
public struct HistorySettingsView: View {
    let dataStore: DataStore
    @State private var records: [TranscriptionRecord]
    @State private var query = ""

    public init(dataStore: DataStore) {
        self.dataStore = dataStore
        _records = State(initialValue: dataStore.recentRecords())
    }

    public var body: some View {
        VStack {
            HStack {
                TextField("Search history", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: query) { _, _ in reload() }
                Button("Clear all", role: .destructive) { dataStore.clearHistory(); reload() }
            }
            .padding([.horizontal, .top])

            List {
                ForEach(records, id: \.persistentModelID) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.cleanedText)
                        HStack(spacing: 8) {
                            Text(record.date, style: .time)
                            Text(record.llmEngine)
                            Text("\(record.latencyMS)ms")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.cleanedText, forType: .string)
                        }
                        Button("Delete", role: .destructive) { dataStore.deleteRecord(record); reload() }
                    }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() { records = dataStore.recentRecords(matching: query) }
}
