# PFMChat — minimal iOS example

A 200-line SwiftUI chat app that uses `PrivateFoundationModels` exactly the way an Apple `FoundationModels`-targeted chat app would.

## Run it

1. Open Xcode 16+, create a new iOS App (iOS 18 deployment target).
2. Replace `ContentView.swift` and the `@main` struct with [`PFMChatApp.swift`](PFMChat/PFMChatApp.swift).
3. In **Package Dependencies**, add `https://github.com/john-rocky/PrivateFoundationModels`.
4. Add both library products to the target:
   - `PrivateFoundationModels`
   - `PrivateFoundationModelsCoreML`
5. Build to an iOS 18+ device (the simulator works but ANE numbers don't apply).
6. First launch downloads `mlboydaisuke/qwen3.5-0.8B-CoreML` (~1.2 GB).

## What it shows

- Installing a `SystemLanguageModel` at app startup.
- Constructing a `LanguageModelSession` with `Instructions`.
- Streaming a response (`streamResponse(to:)`) with cumulative snapshots driving SwiftUI updates.
- Persisting tool / response entries in `transcript`.

The whole "send a message" path is 9 lines — see `send()` in `PFMChatApp.swift`.
