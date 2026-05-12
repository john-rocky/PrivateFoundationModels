// Tiny driver that exercises the Apple-FM-shaped sample code in
// `AppleFMCode.swift`. The single line that differs from an Apple FM-only
// app is the `SystemLanguageModel.default = ...` install — Apple FM uses
// its own implicit `.default`.
//
//   swift run -c release pfm-portability [--no-runtime]
//
// `--no-runtime` skips actually invoking the model (useful when you want a
// pure compile-time portability check). Even with `--no-runtime` the
// AppleFMCode.swift file must build successfully — that's the real proof.

import Foundation
import PrivateFoundationModels
import PrivateFoundationModelsCoreML

@main
struct PortabilityMain {
    static func main() async {
        let runtime = !CommandLine.arguments.contains("--no-runtime")

        let line = String(repeating: "─", count: 78)
        print("\n" + line)
        print(" Apple FoundationModels portability test")
        print(line)
        print("  • AppleFMCode.swift compiled — source compatibility holds")
        print("  • runtime invocation: \(runtime ? "ENABLED" : "skipped (--no-runtime)")")

        guard runtime else { return }

        // The one line that an Apple FM app doesn't need. Wires our CoreML
        // backend in so the same `LanguageModelSession(...)` calls succeed.
        do {
            let backend = try await CoreMLLanguageModel.load(.lfm2_5_350M)
            SystemLanguageModel.default = SystemLanguageModel(backend: backend)
        } catch {
            print("  ✗ failed to load CoreML backend: \(error)")
            print("    (run `huggingface-cli download mlboydaisuke/lfm2.5-350m-coreml --local-dir ~/Documents/Models/lfm2.5-350m` first)")
            exit(1)
        }

        var passed = 0
        var failed = 0
        func record(_ label: String, _ block: () async throws -> Void) async {
            do {
                try await block()
                print("  ✓ \(label)")
                passed += 1
            } catch {
                print("  ✗ \(label): \(error)")
                failed += 1
            }
        }

        print("\n" + line)
        print(" Running Apple FM-style call sites")
        print(line)

        await record("1. firstAnswer (basic single-turn)") {
            _ = try await firstAnswer()
        }
        await record("2. miniChat (closure-form instructions + multi-turn)") {
            _ = try await miniChat()
        }
        await record("3. streamSky (streamResponse, cumulative snapshots)") {
            _ = try await streamSky()
        }
        await record("4. deterministic (GenerationOptions)") {
            _ = try await deterministic()
        }
        await record("5. famousLandmark (Generable with includeSchemaInPrompt)") {
            _ = try await famousLandmark()
        }
        await record("6. researchAssistant (Tool call loop)") {
            _ = try await researchAssistant(question: "Look up Swift Concurrency.")
        }
        await record("7. saveAndRestoreSession (Transcript Codable round-trip)") {
            _ = try await saveAndRestoreSession()
        }
        await record("8. warmupAndCheck (prewarm + sync property access)") {
            _ = warmupAndCheck()
        }

        print("\n" + line)
        print(" Summary")
        print(line)
        print("  passed: \(passed)")
        print("  failed: \(failed)")
        if failed > 0 { exit(1) }
        print("\n  🎉 every Apple FM-shaped call site ran green.\n")
    }
}
