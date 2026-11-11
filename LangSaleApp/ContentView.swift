import LangSaleCore
import SwiftUI

struct ContentView: View {
    @State private var model: AppModel

    /// - Parameter model: Defaults to a live model. Previews pass `AppModel.preview(...)`.
    init(model: AppModel = AppModel()) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            List {
                if model.modelState != .ready {
                    Section {
                        switch model.modelState {
                        case .preparing:
                            ProgressView("Preparing speech model…")
                        case .downloading(let fraction):
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressView(value: fraction)
                                Text("Downloading speech model \(Int(fraction * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .failed(let message):
                            Text(message).foregroundStyle(.red)
                        case .ready:
                            EmptyView()
                        }
                    }
                }

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

                    switch model.status {
                    case .loadingModel:
                        ProgressView("Loading speech model…")
                    case .listening:
                        Label("Listening for speech", systemImage: "waveform")
                            .foregroundStyle(.secondary)
                    case .idle, .starting:
                        EmptyView()
                    }
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

#Preview("Ready") {
    ContentView(model: .preview())
}

#Preview("Downloading model") {
    ContentView(model: .preview(modelState: .downloading(fraction: 0.4)))
}

#Preview("Loading model") {
    ContentView(model: .preview(status: .loadingModel))
}

#Preview("Listening with transcripts") {
    ContentView(model: .preview(status: .listening,
                                transcripts: AppModel.sampleTranscripts,
                                peers: ["Front counter iPad"]))
}

#Preview("Error") {
    ContentView(model: .preview(
        lastError: "Microphone access is off. Enable it in Settings to translate."))
}

#Preview("Model failed") {
    ContentView(model: .preview(
        modelState: .failed("Could not prepare the speech model: The Internet connection appears to be offline.")))
}
