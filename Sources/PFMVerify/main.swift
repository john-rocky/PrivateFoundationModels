import Foundation
import PrivateFoundationModels
import PrivateFoundationModelsCoreML

// MARK: - CLI

struct CLI {
    var modelID: String = "qwen3.5-0.8B"
    var skipDownload: Bool = false
    var only: String?

    static func parse() -> CLI {
        var cli = CLI()
        var args = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = args.next() {
            switch arg {
            case "--model":
                if let v = args.next() { cli.modelID = v }
            case "--only":
                if let v = args.next() { cli.only = v }
            case "--skip-download":
                cli.skipDownload = true
            case "-h", "--help":
                printHelp(); exit(0)
            default:
                FileHandle.standardError.write(Data("Unknown argument: \(arg)\n".utf8))
                printHelp(); exit(64)
            }
        }
        return cli
    }

    static func printHelp() {
        print("""
        pfm-verify — end-to-end verification harness

        USAGE:
            swift run -c release pfm-verify [OPTIONS]

        OPTIONS:
            --model <id>   Model catalog ID (default: qwen3.5-0.8B).
                           Recognized: qwen3.5-0.8B, qwen3.5-2B,
                           gemma4-e2b, gemma4-e4b, lfm2.5-350m,
                           or any HuggingFace repo path.
            --only <name>  Run only the named scenario:
                           load, generate, stream, generable, tools, transcript.
            -h, --help     Print this help.
        """)
    }

    func catalog() -> CoreMLLanguageModel.Catalog {
        switch modelID.lowercased() {
        case "qwen3.5-0.8b":   return .qwen3_5_0_8B
        case "qwen3.5-2b":     return .qwen3_5_2B
        case "gemma4-e2b":     return .gemma4E2B
        case "gemma4-e4b":     return .gemma4E4B
        case "lfm2.5-350m":    return .lfm2_5_350M
        case "qwen3-vl-2b":    return .qwen3VL2BStateful
        default:               return .custom(modelID)
        }
    }
}

// MARK: - Pretty printing

func banner(_ title: String) {
    let line = String(repeating: "─", count: 78)
    print("\n" + line)
    print(" \(title)")
    print(line)
}

func ok(_ message: String)   { print("  ✓ \(message)") }
func info(_ message: String) { print("  • \(message)") }
func fail(_ message: String) { print("  ✗ \(message)") }

func ms(_ duration: Duration) -> String {
    let (s, attoseconds) = duration.components
    let total = Double(s) + Double(attoseconds) / 1e18
    return String(format: "%.0f ms", total * 1000)
}

// MARK: - Scenarios

@main
struct Verify {
    static func main() async throws {
        let cli = CLI.parse()
        let runner = Verifier(cli: cli)
        try await runner.run()
    }
}

actor Counter {
    private(set) var passed = 0
    private(set) var failed = 0
    func pass() { passed += 1 }
    func failOne() { failed += 1 }
}

final class Verifier {
    let cli: CLI
    let counter = Counter()

    init(cli: CLI) { self.cli = cli }

    func run() async throws {
        banner("PrivateFoundationModels verification")
        print("  Model:           \(cli.modelID)")
        print("  Date:            \(Date())")
        print("  Working dir:     \(FileManager.default.currentDirectoryPath)")
        if let only = cli.only { print("  Scenarios:       only=\(only)") }

        // ------- 1. Load -----------------------------------------------------
        let backend = try await runLoad()

        SystemLanguageModel.default = SystemLanguageModel(backend: backend)
        guard SystemLanguageModel.default.isAvailable else {
            await counter.failOne()
            fail("SystemLanguageModel.default reports unavailable")
            await summarize()
            return
        }
        await counter.pass()
        ok("SystemLanguageModel.default is available")

        // ------- 2. generate (String) ----------------------------------------
        if cli.shouldRun("generate") {
            await runGenerate()
        }

        // ------- 3. streamResponse (String) ----------------------------------
        if cli.shouldRun("stream") {
            await runStream()
        }

        // ------- 4. Generable (structured output) ----------------------------
        if cli.shouldRun("generable") {
            await runGenerable()
        }

        // ------- 5. Tool calling --------------------------------------------
        if cli.shouldRun("tools") {
            await runTools()
        }

        // ------- 6. Transcript serialization ---------------------------------
        if cli.shouldRun("transcript") {
            await runTranscript()
        }

        await summarize()
    }

    // MARK: 1. Load

    func runLoad() async throws -> CoreMLBackendImpl {
        banner("1. Load model")
        info("Loading \(cli.modelID) via CoreML-LLM…")
        let start = ContinuousClock.now
        let backend: CoreMLBackendImpl
        do {
            backend = try await CoreMLLanguageModel.load(cli.catalog()) { stage in
                info(stage)
            }
        } catch {
            await counter.failOne()
            fail("load failed: \(error)")
            throw error
        }
        let duration = ContinuousClock.now - start
        await counter.pass()
        ok("loaded \(backend.modelIdentifier) in \(ms(duration))")
        info("context length: \(backend.underlying.contextLength)")
        info("vision supported: \(backend.underlying.supportsVision)")
        info("audio supported:  \(backend.underlying.supportsAudio)")
        return backend
    }

    // MARK: 2. generate

    func runGenerate() async {
        banner("2. respond(to:) — non-streaming")
        let session = LanguageModelSession(
            instructions: Instructions("Answer in exactly one short sentence. No preamble.")
        )
        let prompts = [
            "Name a primary color.",
            "Say hello in Japanese.",
        ]
        for prompt in prompts {
            info("prompt: \(prompt)")
            let start = ContinuousClock.now
            do {
                let response = try await session.respond(
                    to: prompt,
                    options: GenerationOptions(temperature: 0.0, maximumResponseTokens: 64)
                )
                let dt = ContinuousClock.now - start
                await counter.pass()
                ok("response (\(ms(dt))): \(quoted(response.content))")
            } catch {
                await counter.failOne()
                fail("respond threw: \(error)")
            }
        }

        let transcript = session.transcript
        if transcript.entries.count >= 1 + prompts.count * 2 {
            await counter.pass()
            ok("transcript contains instructions + \(prompts.count) prompts + \(prompts.count) responses (\(transcript.entries.count) entries)")
        } else {
            await counter.failOne()
            fail("transcript shape wrong: \(transcript.entries.map(\.kind))")
        }
    }

    // MARK: 3. streamResponse

    func runStream() async {
        banner("3. streamResponse(to:) — cumulative snapshots")
        let session = LanguageModelSession(
            instructions: Instructions("You write very short replies. Two sentences maximum.")
        )
        let prompt = "Why is the sky blue? Two sentences."
        info("prompt: \(prompt)")
        let stream = session.streamResponse(
            to: prompt,
            options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 96)
        )
        var snapshots: [String] = []
        let start = ContinuousClock.now
        do {
            for try await snapshot in stream {
                snapshots.append(snapshot.content)
            }
        } catch {
            await counter.failOne()
            fail("stream threw: \(error)")
            return
        }
        let dt = ContinuousClock.now - start

        guard !snapshots.isEmpty else {
            await counter.failOne()
            fail("no snapshots received")
            return
        }
        let final = snapshots.last ?? ""
        let monotonic = snapshots.indices.allSatisfy { i in
            i == 0 || snapshots[i].hasPrefix(snapshots[i - 1]) || snapshots[i] == snapshots[i - 1]
        }
        let prefixOK = monotonic
        if prefixOK {
            await counter.pass()
            ok("\(snapshots.count) snapshots, cumulative-prefix invariant holds")
        } else {
            await counter.failOne()
            fail("snapshots are not cumulative — backend regression")
        }

        do {
            let collected = try await stream.collect()
            if collected.content == final {
                await counter.pass()
                ok("collect() == last snapshot ✓")
            } else {
                await counter.failOne()
                fail("collect() returned different content from last snapshot")
            }
            ok("final (\(ms(dt))): \(quoted(collected.content))")
        } catch {
            await counter.failOne()
            fail("collect() threw: \(error)")
        }
    }

    // MARK: 4. Generable

    struct CityFact: Generable, CustomStringConvertible {
        let city: String
        let country: String
        let famousFor: String

        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: [
                    "city":      .init(type: "string"),
                    "country":   .init(type: "string"),
                    "famousFor": .init(type: "string"),
                ],
                required: ["city", "country", "famousFor"]
            )
        }

        var description: String { "\(city), \(country) — \(famousFor)" }
    }

    func runGenerable() async {
        banner("4. respond(to:generating:) — structured output")
        let session = LanguageModelSession(
            instructions: Instructions("You return only valid JSON. No prose.")
        )
        let prompt = "Pick a famous city and describe it briefly."
        info("prompt: \(prompt)")
        info("schema: \(CityFact.generationSchema.type) with required \(CityFact.generationSchema.required ?? [])")
        let start = ContinuousClock.now
        do {
            let response = try await session.respond(
                to: prompt,
                generating: CityFact.self,
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 192)
            )
            let dt = ContinuousClock.now - start
            await counter.pass()
            ok("parsed (\(ms(dt))): \(response.content)")
        } catch let error as GenerationError {
            if case .decodingFailure(let raw) = error {
                await counter.failOne()
                fail("decodingFailure — model emitted unparseable JSON:")
                print("    raw output prefix: \(raw.prefix(240))")
            } else {
                await counter.failOne()
                fail("respond threw: \(error)")
            }
        } catch {
            await counter.failOne()
            fail("respond threw: \(error)")
        }
    }

    // MARK: 5. Tools

    struct AddTool: Tool {
        struct Arguments: Generable {
            let a: Int
            let b: Int
            static var generationSchema: GenerationSchema {
                GenerationSchema(
                    type: "object",
                    properties: [
                        "a": .init(type: "integer"),
                        "b": .init(type: "integer"),
                    ],
                    required: ["a", "b"]
                )
            }
        }
        let name = "add"
        let description = "Returns the sum of two integers a and b."
        func call(arguments: Arguments) async throws -> String {
            "\(arguments.a + arguments.b)"
        }
    }

    func runTools() async {
        banner("5. Tool calling")
        let session = LanguageModelSession(
            tools: [AddTool()],
            instructions: Instructions("When the user asks an arithmetic question, you MUST call the add tool. Otherwise answer directly.")
        )
        let prompt = "What is 17 plus 25? Use the add tool."
        info("prompt: \(prompt)")
        let start = ContinuousClock.now
        do {
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.0, maximumResponseTokens: 192)
            )
            let dt = ContinuousClock.now - start
            ok("final (\(ms(dt))): \(quoted(response.content))")

            let transcript = session.transcript
            let kinds = transcript.entries.map(\.kind)
            let invokedTool = kinds.contains(.toolCall) && kinds.contains(.toolOutput)
            if invokedTool {
                await counter.pass()
                ok("transcript shows toolCall + toolOutput: \(kinds)")
                if let toolOut = transcript.entries.first(where: { $0.kind == .toolOutput }) {
                    info("tool output value: \(toolOut.content)")
                }
            } else {
                await counter.failOne()
                fail("tool was NOT invoked. Transcript kinds: \(kinds)")
                info("model probably answered without using the tool — this can happen with small models. Not a code bug, but worth noting.")
            }
        } catch {
            await counter.failOne()
            fail("respond threw: \(error)")
        }
    }

    // MARK: 6. Transcript serialization

    func runTranscript() async {
        banner("6. Transcript serialization round-trip")
        let session = LanguageModelSession(
            instructions: Instructions("Be brief.")
        )
        do {
            _ = try await session.respond(to: "Hi.", options: GenerationOptions(temperature: 0.0, maximumResponseTokens: 24))
        } catch {
            await counter.failOne()
            fail("seeding the transcript failed: \(error)")
            return
        }

        let original = session.transcript
        do {
            let data = try original.serialized()
            info("serialized: \(data.count) bytes")
            let restored = try Transcript(serialized: data)
            if restored.entries.count == original.entries.count,
               zip(restored.entries, original.entries).allSatisfy({ $0.kind == $1.kind && $0.content == $1.content }) {
                await counter.pass()
                ok("round-trip preserved kinds + content (\(restored.entries.count) entries)")
            } else {
                await counter.failOne()
                fail("round-trip mismatch")
            }
        } catch {
            await counter.failOne()
            fail("serialize/restore threw: \(error)")
        }
    }

    // MARK: helpers

    func summarize() async {
        let passed = await counter.passed
        let failed = await counter.failed
        banner("Summary")
        print("  passed: \(passed)")
        print("  failed: \(failed)")
        if failed == 0 {
            print("\n  🎉 every scenario passed.\n")
        } else {
            print("\n  ⚠ \(failed) scenario(s) failed.\n")
            exit(1)
        }
    }

    func quoted(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 200 {
            return "\"\(trimmed.prefix(200))…\""
        }
        return "\"\(trimmed)\""
    }
}

extension CLI {
    func shouldRun(_ name: String) -> Bool {
        guard let only = only else { return true }
        return only == name
    }
}
