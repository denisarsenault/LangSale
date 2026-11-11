import LangSaleCore
import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Translate", selection: $model.pair) {
                        ForEach(LanguagePair.firstRelease, id: \.self) { pair in
                            Text("\(pair.source.displayName) → \(pair.target.displayName)").tag(pair)
                        }
                    }
                    .disabled(model.isRunning)

                    Button {
                        Task { await model.toggle() }
                    } label: {
                        Label(model.isRunning ? "Stop" : "Start listening",
                              systemImage: model.isRunning ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.headline)
                    }
                    .disabled(model.status == .starting)
                }

                if let error = model.lastError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section("Transcripts") {
                    if model.transcripts.isEmpty {
                        Text("Nothing translated yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.transcripts) { transcript in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transcript.original)
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Text(transcript.translated)
                                .font(.headline)
                            Text(transcript.date, style: .time)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if !model.peers.isEmpty {
                    Section("Paired devices") {
                        ForEach(model.peers, id: \.self) { peer in
                            Label(peer, systemImage: "iphone")
                        }
                    }
                }
            }
            .navigationTitle("LangSale")
        }
    }
}
