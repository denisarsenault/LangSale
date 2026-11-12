# LangSale Architecture

On-device speech translation for iPhone. First release: Spanish, Portuguese, and Haitian Creole → English.
Audio, transcripts, and models stay on the device. The only data that leaves it is model downloads from our CDN.

## Pipeline

```
AVAudioEngine tap ──► AudioRingBuffer (16 kHz mono Float32, SPSC)
                              │
                       SpeechSession (actor)
                         EnergyVAD → segment (0.5 s–30 s)
                              │
                       TranslationPipeline (actor)
                         SpeechRecognizing → Translating
                              │
                       Transcript events ──► UI, TTS, PeerTranscriptShare
```

| Layer | Type | Isolation |
|---|---|---|
| Capture | `AudioCapture`, `TapProcessor` | Audio render thread (no allocation, no locks) |
| Buffer | `AudioRingBuffer` | Lock-free SPSC via `Synchronization.Atomic` |
| Segmentation | `SpeechSession`, `EnergyVAD` | Actor; consumer polls the ring at 10 ms when empty |
| Inference | `TranslationPipeline`, `ManagedModel` adapters | Actor; one segment at a time |
| Delivery | `ModelDownloader`, `ManifestStore` | Actor; background `URLSession` |
| Sharing | `PeerTranscriptShare` | Delegate callbacks bridged to `AsyncStream` |

Vendor adapters (WhisperKit, Core ML, ONNX Runtime) live in the app target, not in `LangSaleCore`.
Core depends only on protocols, so it can be tested without any model.

## Real-time audio rules

- The tap closure does no allocation beyond what `AVAudioConverter` does internally. The output buffer is preallocated.
- No locks, `await`, logging, or Swift `Array` growth on the render thread.
- Samples cross to the consumer only through `AudioRingBuffer`. When the consumer falls behind, samples are dropped and `overflowCount` records it.
- VAD and segmentation run on the consumer side, never on the render thread.

## Memory budget (6 GB devices)

- `TranslationPipeline` checks `MemoryProbe.availableBytes()` (`os_proc_available_memory` on iOS) before each load. A load needs the model's footprint plus 256 MB of headroom.
- Only the models needed for the current direction stay resident.
- Call `shedMemory()` from the app's memory-warning handler. The next segment reloads what it needs.
- Segments are capped at 30 s so inference buffers stay bounded.
- Profile with Instruments (Allocations and the memory gauge) on a 6 GB device before every release. Confirm no growth across 30 minutes of speech.

## Model delivery

- A release is a `ModelManifest`: version, plus files with URLs and expected sizes.
- `ModelDownloader` uses a background `URLSession` (`com.langsale.models`). Cellular is off by default.
- Interrupted transfers keep their resume data in the manifest. The manifest is written atomically on every state change.
- `NWPathMonitor` retries incomplete files when the network returns. `start()` reattaches to tasks the system kept running after relaunch.
- The app delegate must forward `application(_:handleEventsForBackgroundURLSession:completionHandler:)` to the downloader, or the system will not get its completion handler back.
- Finished files are moved into place inside the delegate callback, because URLSession deletes the temp file when the callback returns.

## Peer sharing

- `MCSession` with `encryptionPreference: .required`. Only `Transcript` JSON is sent, capped at 64 KB per message.
- Invitations go through an `approve` closure. The app must show a confirmation prompt there and must not auto-accept.
- Info.plist needs `NSLocalNetworkUsageDescription`, `NSBonjourServices` = `_langsale-tx._tcp`, `_langsale-tx._udp`, and `NSMicrophoneUsageDescription`.

## Concurrency

- Actors own mutable state: `SpeechSession`, `TranslationPipeline`, `ModelDownloader`.
- Cross-boundary values are `Sendable` value types (`Transcript`, `ModelManifest`, `LanguagePair`).
- Models are actors or `Sendable` types. Their `load`/`unload` are async, so they never block the caller's thread.
- `AudioRingBuffer` and `TapProcessor` are the only `@unchecked Sendable` types. Each documents its single-producer, single-consumer rule.
- Build with Swift 6 language mode, so data-race diagnostics are errors.

## Production releases

- Build number: `CURRENT_PROJECT_VERSION` bumps on every commit that ships.
- Gates before a release candidate: unit tests pass, Thread Sanitizer clean, Address Sanitizer clean, Instruments memory run on a 6 GB device, and a manual pass on each language pair with real speech.
- Staged rollout through TestFlight, then phased App Store release.
- Model releases ship separately from app releases. Each one carries a version, checksums, and a manifest, so the app can roll back to the previous model.

## Open items

- Choose and integrate the speech and translation vendor models. Confirm sizes to set `estimatedFootprintBytes`.
- Calibrate `EnergyVAD` thresholds on device, or replace it with the recognizer vendor's VAD.
- Confirm translation direction. The package defaults to English as the target.
- Text-to-speech output is not yet implemented; it will be a `SpeechSynthesizing` adapter.
