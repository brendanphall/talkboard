# Talkboard

A small, offline-first picture communication app for iPad, built with SwiftUI.
Tap a tile to speak. Caregivers can add photos, choose the displayed label and
spoken words independently, and expand the board without moving existing tiles.

**Status:** early development. This repository contains a generic demonstration
board and source code for building the app yourself. There is no App Store
release yet. Export/restore and several physical-device acceptance checks remain
unfinished. Software tests do not establish communication or clinical outcomes.

## What works

- A fixed landscape grid with spare cells, large tap targets and VoiceOver labels.
- Immediate speech using installed Apple voices. A new tap interrupts the previous
  output rather than joining a queue.
- Caregiver editing protected by device-owner authentication. Editing locks again
  on backgrounding or when Guided Access starts; speaking stays accessible.
- Photo selection through the system picker, orientation correction, downsampling
  and local storage. Labels and spoken phrases remain separate.
- Atomic board saves with a previous generation retained and visible recovery
  notices when storage cannot be opened normally.
- Optional local recording playback with saved-text fallback if the file cannot
  be opened or playback cannot start. A recording import/capture UI is not yet built.

The demonstration uses invented labels and placeholder images. Add your own
pictures through **Caregiver → Edit board**. No symbol library, stock photos or
recorded clips are bundled. Imported media keeps its own source/license metadata.

## Build and run

You need macOS, Xcode with Swift 6 support, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The deployment target is iPadOS 17 or later; development is tested with Xcode 27.2.

```sh
brew install xcodegen
git clone https://github.com/brendanphall/talkboard.git
cd talkboard
xcodegen generate
open Talkboard.xcodeproj
```

Choose an iPad simulator and run the `Talkboard` scheme. To use a physical iPad,
select your own development team under Signing & Capabilities, choose a unique
bundle identifier, and enable Developer Mode on the device. The repository does
not contain signing credentials or profiles. The default identifier is
`com.brendanphall.talkboard.public`.

On a physical device, caregiver editing requires a configured device passcode.
Try local photos and deliberate tile taps at a comfortable volume. Offline speech
requires an available installed voice. Device signing and distribution expire
according to your Apple account and provisioning profile.

## Tests

Run the platform-independent logic tests:

```sh
swift test --package-path Packages/TalkboardCore
```

Run the native and UI suites with an available iPad simulator:

```sh
xcodegen generate
xcodebuild -showdestinations -project Talkboard.xcodeproj -scheme Talkboard
xcodebuild test -project Talkboard.xcodeproj -scheme Talkboard \
  -destination 'platform=iOS Simulator,name=<your iPad simulator>' \
  -parallel-testing-enabled NO
```

UI automation uses a Debug-only silent output path and isolated demonstration
storage. Test authentication bypasses also require that silent test mode and are
excluded from Release builds. Keep automated tests silent and use invented data.
CI runs the Core package tests on macOS; native/UI acceptance is separate.

## Project layout

| Path | Purpose |
| --- | --- |
| `App/` | SwiftUI views and Apple photo, speech, recording and authentication adapters |
| `Packages/TalkboardCore/` | Board schema, validation, storage, editing and output policy |
| `Tests/` | Native adapter and state tests |
| `UITests/` | Board geometry, caregiver and editor interaction tests |
| `project.yml` | XcodeGen project definition |
| `docs/` | Design contract, privacy notes and picture-packet format |

See [design and limits](docs/DESIGN.md), [privacy](docs/PRIVACY.md),
[picture packet import](docs/PICTURE_PACKETS.md) and [contributing](CONTRIBUTING.md).

## Next steps

Validated export/restore to Files, a printable matching board, more physical-device
acceptance work, and a caregiver interface for importing or recording tile audio.

## License

The source is public for review. No open-source reuse license has been selected;
copyright is reserved. See [LICENSE](LICENSE).
