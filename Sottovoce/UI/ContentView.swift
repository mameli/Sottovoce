import SottovoceCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: QueueStore
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if store.items.isEmpty {
                emptyDropArea
            } else {
                queueView
            }
            Divider()
            controlsBar
        }
        .frame(minWidth: 560, minHeight: 400)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .alert(
            "Replace existing subtitle file?",
            isPresented: Binding(
                get: { store.overwritePrompt != nil },
                set: { if !$0 { store.resolveOverwrite(.skip) } }
            ),
            presenting: store.overwritePrompt
        ) { _ in
            Button("Replace") { store.resolveOverwrite(.replace) }
            Button("Replace All") { store.resolveOverwrite(.replaceAll) }
            Button("Skip", role: .cancel) { store.resolveOverwrite(.skip) }
        } message: { prompt in
            Text("\(prompt.fileName) already exists next to the media file.")
        }
    }

    private var emptyDropArea: some View {
        VStack(spacing: 14) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop video or audio files here")
                .font(.title3.weight(.medium))
            Text("Writes SRT or VTT subtitle files next to each media file.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Add Files…") {
                store.openFilePicker()
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var queueView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue (\(store.items.count))")
                    .font(.headline)
                Spacer()
                Button("Add Files…") {
                    store.openFilePicker()
                }
                .buttonStyle(.borderless)
                if store.hasCompleted {
                    Button("Clear Done") {
                        store.clearCompleted()
                    }
                    .buttonStyle(.borderless)
                }
                if !store.isRunning {
                    Button("Clear All") {
                        store.clearAll()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            List {
                ForEach(store.items) { item in
                    QueueRow(item: item, store: store)
                }
            }
            .listStyle(.inset)
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Picker("Style", selection: $store.style) {
                    Text("Classic").tag(Style.classic)
                    Text("Short").tag(Style.short)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
                .disabled(store.isRunning)

                if store.style == .short {
                    Picker("Words", selection: $store.words) {
                        Text("1 word").tag(1)
                        Text("2 words").tag(2)
                        Text("3 words").tag(3)
                    }
                    .labelsHidden()
                    .frame(width: 96)
                    .disabled(store.isRunning)
                }

                Picker("Format", selection: $store.format) {
                    Text("SRT").tag(Format.srt)
                    Text("VTT").tag(Format.vtt)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 100)
                .disabled(store.isRunning)

                Toggle("Speakers", isOn: $store.speakers)
                    .toggleStyle(.checkbox)
                    .disabled(store.isRunning)
            }

            Spacer()

            if let statusMessage = store.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if store.isRunning {
                Button("Cancel") {
                    store.cancel()
                }
            } else {
                Button("Start") {
                    store.start()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!store.hasPendingWork)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                Task { @MainActor in
                    store.addFiles([url])
                }
            }
        }
        return accepted
    }
}

private struct QueueRow: View {
    let item: QueueStore.Item
    let store: QueueStore

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusSubtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            switch item.state {
            case .completed(let result):
                if let path = result.subtitleFile {
                    Button {
                        store.reveal(path)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal subtitle file in Finder")
                }
            case .running:
                EmptyView()
            default:
                Button {
                    store.remove(item)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove from queue")
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.state {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "forward.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusSubtitle: some View {
        switch item.state {
        case .pending:
            Text("Waiting")
        case .running(let phase):
            Text(phase)
        case .completed(let result):
            let cues = result.cues.map { "\($0) cues" } ?? "Done"
            let lang = result.language.map { " · \($0)" } ?? ""
            let file = result.subtitleFile.map { URL(filePath: $0).lastPathComponent } ?? ""
            Text("\(file) · \(cues)\(lang)")
        case .failed(let error):
            Text(error)
                .foregroundStyle(.red)
        case .skipped:
            Text("Skipped (subtitle file already exists)")
        }
    }
}
