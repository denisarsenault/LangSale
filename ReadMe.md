# LangSale

On-device speech translation for iPhone, for point-of-sale conversations. A shopkeeper taps Start, the
customer speaks Spanish, Portuguese, or Haitian Creole, and the app shows the English translation.

Nothing is sent to a server. Audio is processed on the phone, and the translation model runs locally with
WhisperKit (Whisper `base`, Core ML).

> **Status:** early development. The pipeline, model download, UI, and tests are in place. The model has not
> yet been validated on a device with real speech. See [Open items](docs/ARCHITECTURE.md#open-items).

## Requirements

- Xcode 16.4 or later, with the iOS 18 SDK
- iOS 18 or later on the device
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate the project (`brew install xcodegen`)
- An Apple developer team, to run on a physical device

## Getting started

```bash
git clone https://github.com/denisarsenault/LangSale.git
cd LangSale
xcodegen generate
open LangSale.xcodeproj
```

Set your development team under **Signing & Capabilities** for the `LangSale` target before running on a
device. The team ID is intentionally blank in `project.yml`.

The first launch downloads the speech model (about 149 MB) in the background. The screen shows progress
until the model is ready. Tapping Start before then shows a message instead of starting.

## Running the tests

```bash
# Core package: ring buffer, VAD, manifest, pipeline
swift test

# App unit and UI tests, on an iPhone simulator
xcodebuild test \
  -project LangSale.xcodeproj \
  -scheme LangSale \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

CI runs both on every push to `main` and on pull requests. See
[`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Project layout

| Path | Contents |
|---|---|
| `Sources/LangSaleCore/` | Swift package: audio capture, ring buffer, VAD, segmentation, pipeline, model download, peer sharing. No UI and no vendor framework. |
| `Tests/LangSaleCoreTests/` | Tests for the package |
| `LangSaleApp/` | SwiftUI app: `AppModel`, `ContentView`, WhisperKit adapter, model store, pinned model manifest |
| `LangSaleAppTests/` | App unit tests |
| `LangSaleUITests/` | UI smoke tests |
| `project.yml` | XcodeGen project definition. `LangSale.xcodeproj` is generated from it. |
| `docs/ARCHITECTURE.md` | Design, memory budget, concurrency rules, release process |

## Languages

First release: Spanish, Portuguese, and Haitian Creole, each translated to English.

## Privacy

- Audio and transcripts stay on the device. They are not uploaded anywhere.
- The only network use is downloading the speech model from Hugging Face, from fixed commits listed in
  [`LangSaleApp/Resources/whisper-base.manifest.json`](LangSaleApp/Resources/whisper-base.manifest.json).
- Microphone access is requested when the user taps Start, not at launch.
- Sharing with another device is off in this release. When it is turned on, only transcript text is sent,
  encrypted, and only after the user approves the pairing.

## Contributing

Work on a branch and open a pull request. CI must pass before merging. Changes to `project.yml` need
`xcodegen generate` run and the regenerated `LangSale.xcodeproj` committed with them.
