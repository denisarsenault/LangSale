# LangSale Architecture

On-device speech translation for iPhone. First release: Spanish, Portuguese, and Haitian Creole → English.
Audio and transcripts stay on the device. The only network traffic is the speech model download from
Hugging Face, pinned to fixed commits.

## Pipeline

```
AVAudioEngine tap ──► AudioRingBuffer (16 kHz mono Float32, SPSC)
                              │
                       SpeechSession (actor)
                         EnergyVAD → segment (0.5 s–30 s, with pre-roll)
                              │
                       TranslationPipeline (actor)
                         SpeechRecognizing (WhisperKit, translate task → English)
                         [optional Translating — not used in the first release]
                              │
                       Transcript events ──► UI, PeerTranscriptShare
```

Whisper's translate task returns English directly from speech in any supported source language, so the
first release runs one model. The `translator` parameter is optional; when it is nil, the recognized
English text is used as the translation.

| Layer | Type | Isolation |
|---|---|---|
| Capture | `AudioCapture`, `TapProcessor` | Audio render thread (no allocation, no locks) |
| Buffer | `AudioRingBuffer` | Lock-free SPSC via `Synchronization.Atomic` |
| Segmentation | `SpeechSession`, `EnergyVAD` | Actor; consumer polls the ring at 10 ms when empty |
| Inference | `TranslationPipeline`, `WhisperKitRecognizer` | Actor; one segment at a time |
| Delivery | `ModelDownloader`, `ManifestStore`, `SpeechModelStore` | Actor; background `URLSession` |
| Sharing | `PeerTranscriptShare` | Delegate callbacks bridged to `AsyncStream` |
| UI | `AppModel` (main actor, `@Observable`), `ContentView` | SwiftUI |

`LangSaleCore` (the Swift package) holds everything that does not depend on a vendor framework and is
tested without any model. The app target adds WhisperKit and the UI.

## Real-time audio rules

- The tap closure does no allocation beyond what `AVAudioConverter` does internally. The output buffer is preallocated.
- No locks, `await`, logging, or Swift `Array` growth on the render thread.
- Samples cross to the consumer only through `AudioRingBuffer`. When the consumer falls behind, samples are dropped and `overflowCount` records it.
- VAD and segmentation run on the consumer side, never on the render thread.
- `EnergyVAD` tracks the room's noise floor. It calibrates for the first 10 chunks (about 320 ms) and reports no speech during that time, so the detector must start before the customer speaks.
- `SpeechSession` keeps 8 chunks of pre-roll so the detector's onset delay does not clip the first word.

## Speech model

- **Model:** WhisperKit `whisper-base` (Core ML), from `argmaxinc/whisperkit-coreml` at commit `0f63a780`, plus the Whisper tokenizer from `openai/whisper-base` at commit `e37978b9`. Both are listed in `LangSaleApp/Resources/whisper-base.manifest.json`.
- **Package:** `argmax-oss-swift` pinned to exactly 1.1.1 (product `WhisperKit`).
- **Loading:** `WhisperKitRecognizer` loads from a local folder with `download: false`. The app never fetches model files from Hugging Face at runtime, and the tokenizer must be in the folder (WhisperKit would otherwise download it).
- **Task and language:** `DecodingOptions(task: .translate, language:)` with the source language from the selected `LanguagePair`. Haitian Creole maps to `ht`.
- **Known limit:** Because the output is English, the source-language text is not kept. `Transcript.original` and `Transcript.translated` hold the same English text.
- **Footprint:** declared as 300 MB for budgeting. Confirm on a device with Instruments.
- **Load state:** the pipeline's `prepare()` loads the model before audio capture starts, so the first utterance is not delayed.

## Memory budget (6 GB devices)

- `TranslationPipeline` checks `MemoryProbe.availableBytes()` before each load. A load needs the model's footprint plus 256 MB of headroom.
- `SystemMemoryProbe` uses `os_proc_available_memory` on iOS. When that returns 0 (Simulator, or no jetsam limit) it falls back to physical memory minus the process footprint from Mach.
- Call `shedMemory()` from the app's memory-warning handler. The next segment reloads what it needs. `AppModel` does this.
- Segments are capped at 30 s so inference buffers stay bounded.
- Profile with Instruments (Allocations and the memory gauge) on a 6 GB device before every release. Confirm no growth across 30 minutes of speech.

## Model delivery

- A release is a `ModelManifest`: a version string plus files with URLs and expected sizes. Model files are stored under `Application Support/LangSale/Models/<version>/`.
- The bundled manifest is the release definition. The persisted copy in Application Support keeps progress across launches and is replaced when the bundled version changes.
- `ModelDownloader` uses a background `URLSession` (`com.langsale.models`). Cellular is off by default.
- Interrupted transfers keep their resume data in the manifest. The manifest is written atomically on every state change, and each change is published on `ModelDownloader.updates` for the UI.
- `NWPathMonitor` retries incomplete files when the network returns. `AppModel` also retries every 30 seconds until the model is complete. `start()` reattaches to tasks the system kept running after relaunch.
- The app delegate must forward `application(_:handleEventsForBackgroundURLSession:completionHandler:)` to the downloader, or the system will not get its completion handler back. **Not yet implemented.**
- Finished files are moved into place inside the delegate callback, because URLSession deletes the temp file when the callback returns. Nested file names (for example `model.mlmodelc/weights/weight.bin`) get their parent directories created first.

## Peer sharing

- `MCSession` with `encryptionPreference: .required`. Only `Transcript` JSON is sent, capped at 64 KB per message.
- Peers see the device name "LangSale device". No personal name is exposed.
- Invitations go through an `approve` closure. The first release denies every invitation, so sharing is effectively off until a confirmation prompt is built. The closure must never auto-accept.
- Info.plist has `NSLocalNetworkUsageDescription`, `NSBonjourServices` = `_langsale-tx._tcp`, `_langsale-tx._udp`, and `NSMicrophoneUsageDescription`.

## Concurrency

- Actors own mutable state: `SpeechSession`, `TranslationPipeline`, `ModelDownloader`, `WhisperKitRecognizer`.
- `AppModel` is `@MainActor` and `@Observable`. It owns the UI state and never runs inference itself.
- Cross-boundary values are `Sendable` value types (`Transcript`, `ModelManifest`, `LanguagePair`).
- `AudioRingBuffer` and `TapProcessor` are the only `@unchecked Sendable` types in the core and app. Each documents its single-producer, single-consumer rule.
- The Swift package and the app build in Swift 6 language mode with complete strict concurrency.

## Testing

| Layer | Command | What it covers |
|---|---|---|
| Core package | `swift test` | Ring buffer, VAD, manifest persistence, pipeline (with fakes) |
| App unit tests | `LangSaleTests` (Swift Testing, hosted) | `AppModel` state rules, `SpeechModelStore` paths and pinning, `WhisperKitRecognizer` errors without a model |
| UI tests | `LangSaleUITests` (XCUITest) | Main screen smoke tests, launched with `-uiTesting` so the app uses preview state and skips the download |

The UI test launch argument is honored only in Debug builds. Release builds always use the live model.

## Continuous integration

`.github/workflows/ci.yml` runs on pushes to `main` and on pull requests:

1. `swift test` for the core package.
2. XcodeGen regeneration, then a check that `LangSale.xcodeproj` and `project.yml` match the committed files.
3. `xcodebuild test` for the app, unit and UI tests, on an iPhone simulator.

The workflow has not run on GitHub yet. It targets `macos-15` with Xcode 16.4 and needs that version confirmed on the runner.

## Production releases

- Build number: `CURRENT_PROJECT_VERSION` bumps on every commit that ships.
- Gates before a release candidate: CI green, Thread Sanitizer clean, Address Sanitizer clean, Instruments memory run on a 6 GB device, and a manual pass on each language pair with real speech.
- Staged rollout through TestFlight, then phased App Store release.
- Model releases ship separately from app releases. Each one is a new manifest with a new version, pinned commits, and sizes, so the app can roll back to the previous model.

## Open items

- Run the model on a device or simulator: confirm the download completes, that WhisperKit loads from the folder, and that Spanish, Portuguese, and Haitian Creole sample audio translates correctly.
- Measure real memory use of whisper-base and set `estimatedFootprintBytes` from the measurement.
- Calibrate `EnergyVAD` on device, in a noisy shop and a quiet room.
- Add the background URLSession handler in the app delegate.
- Build the peer-sharing confirmation prompt. Until then, sharing is off.
- Keep the source-language text, so the transcript can show both the original and the English translation.
- Text-to-speech output is not implemented.
- Background audio capture is not enabled. The app listens only while it is in the foreground.
- Confirm the CI runner's Xcode version.
