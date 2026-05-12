// pfm-deep — exercises every Generable / Tool shape against a real model.
//
// Stub-backed unit tests prove the dispatch logic deterministically; this
// driver proves the same logic survives contact with an actual on-device
// model on the Apple Neural Engine. Scenario outcomes are reported
// honestly: small models may fail content-level checks even when the API
// surface works. The goal is a complete map of "what works end-to-end vs.
// what is model-quality limited."
//
//   swift run -c release pfm-deep [--model lfm2.5-350m]

import Foundation
import PrivateFoundationModels
import PrivateFoundationModelsCoreML

@main
struct DeepMain {
    static func main() async {
        let modelID = readArg(after: "--model") ?? "lfm2.5-350m"

        banner("PrivateFoundationModels deep verification")
        print("  model:          \(modelID)")
        print("  date:           \(Date())")

        let catalog: CoreMLLanguageModel.Catalog = {
            switch modelID.lowercased() {
            case "lfm2.5-350m": return .lfm2_5_350M
            case "gemma4-e2b":  return .gemma4E2B
            case "gemma4-e4b":  return .gemma4E4B
            default:            return .custom(modelID)
            }
        }()

        do {
            let backend = try await CoreMLLanguageModel.load(catalog) { @Sendable stage in
                print("  • \(stage)")
            }
            SystemLanguageModel.default = SystemLanguageModel(backend: backend)
        } catch {
            fail("failed to load backend: \(error)")
            exit(1)
        }

        var report = Report()

        await report.runGenerableScenarios()
        await report.runToolScenarios()

        report.summarize()
    }
}

// MARK: - Argument parsing

private func readArg(after flag: String) -> String? {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        if arg == flag { return it.next() }
    }
    return nil
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
func warn(_ message: String) { print("  ⚠ \(message)") }
func fail(_ message: String) { print("  ✗ \(message)") }

// MARK: - Generable shapes

struct Address: Generable, Equatable, CustomStringConvertible {
    let city: String
    let country: String
    static var generationSchema: GenerationSchema {
        GenerationSchema(
            type: "object",
            properties: [
                "city":    .init(type: "string"),
                "country": .init(type: "string"),
            ],
            required: ["city", "country"]
        )
    }
    var description: String { "\(city), \(country)" }
}

struct Profile: Generable, Equatable, CustomStringConvertible {
    let name: String
    let age: Int
    let address: Address
    static var generationSchema: GenerationSchema {
        GenerationSchema(
            type: "object",
            properties: [
                "name":    .init(type: "string"),
                "age":     .init(type: "integer"),
                "address": Address.generationSchema,
            ],
            required: ["name", "age", "address"]
        )
    }
    var description: String { "\(name), age \(age), \(address)" }
}

struct ShoppingList: Generable, Equatable, CustomStringConvertible {
    let name: String
    let items: [String]
    static var generationSchema: GenerationSchema {
        GenerationSchema(
            type: "object",
            properties: [
                "name":  .init(type: "string"),
                "items": GenerationSchema(type: "array", items: .init(type: "string")),
            ],
            required: ["name", "items"]
        )
    }
    var description: String { "\(name): [\(items.joined(separator: ", "))]" }
}

struct Reading: Generable, Equatable, CustomStringConvertible {
    let name: String
    let value: Double
    let active: Bool
    static var generationSchema: GenerationSchema {
        GenerationSchema(
            type: "object",
            properties: [
                "name":   .init(type: "string"),
                "value":  .init(type: "number"),
                "active": .init(type: "boolean"),
            ],
            required: ["name", "value", "active"]
        )
    }
    var description: String { "\(name)=\(value) (active=\(active))" }
}

struct Article: Generable, Equatable, CustomStringConvertible {
    let title: String
    let summary: String?
    static var generationSchema: GenerationSchema {
        GenerationSchema(
            type: "object",
            properties: [
                "title":   .init(type: "string"),
                "summary": .init(type: "string"),
            ],
            required: ["title"]
        )
    }
    var description: String { "title=\"\(title)\" summary=\(summary.map { "\"\($0)\"" } ?? "<absent>")" }
}

// MARK: - Tools

struct AddTool: Tool {
    struct Arguments: Generable {
        let a: Int
        let b: Int
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: ["a": .init(type: "integer"), "b": .init(type: "integer")],
                required: ["a", "b"]
            )
        }
    }
    let name = "add"
    let description = "Returns a + b."
    func call(arguments: Arguments) async throws -> String { "\(arguments.a + arguments.b)" }
}

struct MultiplyTool: Tool {
    struct Arguments: Generable {
        let a: Int
        let b: Int
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: ["a": .init(type: "integer"), "b": .init(type: "integer")],
                required: ["a", "b"]
            )
        }
    }
    let name = "multiply"
    let description = "Returns a * b."
    func call(arguments: Arguments) async throws -> String { "\(arguments.a * arguments.b)" }
}

struct LookupTool: Tool {
    struct Arguments: Generable {
        let topic: String
        let limit: Int
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: [
                    "topic": .init(type: "string"),
                    "limit": .init(type: "integer"),
                ],
                required: ["topic", "limit"]
            )
        }
    }
    let name = "lookup"
    let description = "Look up up-to-N facts on a topic."
    func call(arguments: Arguments) async throws -> String {
        "[stub:\(arguments.limit) facts on \(arguments.topic)]"
    }
}

struct AlwaysFailsTool: Tool {
    struct Arguments: Generable {
        let key: String
        static var generationSchema: GenerationSchema {
            GenerationSchema(type: "object",
                              properties: ["key": .init(type: "string")],
                              required: ["key"])
        }
    }
    struct Boom: Error { let message: String }
    let name = "boom"
    let description = "Always throws."
    func call(arguments: Arguments) async throws -> String {
        throw Boom(message: "no \(arguments.key) for you")
    }
}

// MARK: - Report

struct Report {
    var rows: [(label: String, status: String, detail: String)] = []

    mutating func record(_ label: String, _ status: String, _ detail: String) {
        rows.append((label, status, detail))
    }

    func summarize() {
        banner("Summary")
        let passCount = rows.filter { $0.status == "PASS" }.count
        let modelCount = rows.filter { $0.status == "MODEL" }.count
        let failCount = rows.filter { $0.status == "FAIL" }.count
        print("  PASS  (API works + content correct):       \(passCount)")
        print("  MODEL (API works, content model-limited): \(modelCount)")
        print("  FAIL  (framework / backend regression):    \(failCount)")
        print()
        for row in rows {
            print("  \(row.status.padding(toLength: 6, withPad: " ", startingAt: 0)) \(row.label)")
            if !row.detail.isEmpty {
                print("        \(row.detail)")
            }
        }
        if failCount > 0 { exit(1) }
    }

    // MARK: Generable

    mutating func runGenerableScenarios() async {
        banner("Generable scenarios (structured output)")

        // 1. Simple object (3 string fields). Should pass on any model.
        await runGenerable("G1. simple-object (3 strings)",
                            session: LanguageModelSession {
                                "You return only valid JSON. No prose."
                            },
                            prompt: "Pick one famous landmark and return its city and country.",
                            type: Address.self) { value in
            "city=\(value.city) country=\(value.country)"
        }

        // 2. Mixed primitives. Has Double + Int + Bool — small models often
        //    coerce numbers as strings; record as MODEL when so.
        await runGenerable("G2. mixed-primitives (string + int? no — number + bool)",
                            session: LanguageModelSession {
                                "Return strict JSON matching the schema. No prose."
                            },
                            prompt: "Invent a sensor reading. Pick a short name, a numeric value, and an active boolean.",
                            type: Reading.self) { value in
            "name=\(value.name) value=\(value.value) active=\(value.active)"
        }

        // 3. String array.
        await runGenerable("G3. array-of-strings (3-5 items)",
                            session: LanguageModelSession {
                                "Return strict JSON. No prose."
                            },
                            prompt: "Make a shopping list with a name and 3 items.",
                            type: ShoppingList.self) { value in
            "name=\(value.name) items=\(value.items)"
        }

        // 4. Nested object (2 levels). Harder for small models.
        await runGenerable("G4. nested-object (2 levels)",
                            session: LanguageModelSession {
                                "Return strict JSON. No prose. Use exactly the schema fields."
                            },
                            prompt: "Invent a person profile with a name, age, and address (city, country).",
                            type: Profile.self) { value in
            "\(value.description)"
        }

        // 5. Optional field absent — model returns just the required key.
        await runGenerable("G5. optional-fields (absent OK)",
                            session: LanguageModelSession {
                                "Return strict JSON. Only include the title field."
                            },
                            prompt: "Make up a one-line article. Title only, no summary.",
                            type: Article.self) { value in
            "title=\(value.title) summary=\(value.summary ?? "<absent>")"
        }

        // 6. Streaming Generable.
        await runStreamingGenerable("G6. streaming-generable (Profile)",
                                     prompt: "Invent a person profile. Name, age, city, country.",
                                     type: Profile.self) { value in
            "\(value)"
        }
    }

    mutating func runGenerable<T: Generable & CustomStringConvertible>(
        _ label: String,
        session: LanguageModelSession,
        prompt: String,
        type: T.Type,
        describe: (T) -> String
    ) async {
        info("\(label) — prompt: \(prompt)")
        let start = ContinuousClock.now
        do {
            let response = try await session.respond(
                to: prompt,
                generating: T.self,
                options: GenerationOptions(temperature: 0.0, maximumResponseTokens: 256)
            )
            let dt = ContinuousClock.now - start
            ok("\(label) → \(describe(response.content)) (\(ms(dt)))")
            record(label, "PASS", describe(response.content))
        } catch let error as GenerationError {
            if case .decodingFailure(let raw) = error {
                warn("\(label) — model emitted unparseable output (model-quality, not framework). raw=\(raw.prefix(180))")
                record(label, "MODEL", "decodingFailure on \(raw.prefix(80))")
            } else {
                fail("\(label) — \(error)")
                record(label, "FAIL", "\(error)")
            }
        } catch {
            fail("\(label) — \(error)")
            record(label, "FAIL", "\(error)")
        }
    }

    mutating func runStreamingGenerable<T: Generable & CustomStringConvertible>(
        _ label: String,
        prompt: String,
        type: T.Type,
        describe: (T) -> String
    ) async {
        info("\(label) — prompt: \(prompt)")
        let session = LanguageModelSession {
            "Return strict JSON only. No prose."
        }
        let stream = session.streamResponse(
            to: prompt,
            generating: T.self,
            options: GenerationOptions(temperature: 0.0, maximumResponseTokens: 256)
        )
        let start = ContinuousClock.now
        var snapshotCount = 0
        var lastDecoded: T?
        do {
            for try await snapshot in stream {
                snapshotCount += 1
                lastDecoded = snapshot.content
            }
            let final = try await stream.collect()
            let dt = ContinuousClock.now - start
            ok("\(label) → \(snapshotCount) parseable snapshots, final \(describe(final.content)) (\(ms(dt)))")
            record(label, "PASS", "\(snapshotCount) snapshots, final \(describe(final.content))")
        } catch let error as GenerationError {
            if case .decodingFailure = error {
                if let last = lastDecoded {
                    warn("\(label) — final did not parse but \(snapshotCount) intermediate snapshots did. last=\(describe(last))")
                    record(label, "MODEL", "snapshots=\(snapshotCount), final decode failed")
                } else {
                    warn("\(label) — model emitted no parseable snapshot (model-quality)")
                    record(label, "MODEL", "no parseable snapshot")
                }
            } else {
                fail("\(label) — \(error)")
                record(label, "FAIL", "\(error)")
            }
        } catch {
            fail("\(label) — \(error)")
            record(label, "FAIL", "\(error)")
        }
    }

    // MARK: Tools

    mutating func runToolScenarios() async {
        banner("Tool calling scenarios")

        // T1. Single tool.
        await runTools(
            "T1. single-tool (add)",
            tools: [AddTool()],
            prompt: "What is 17 plus 25? You MUST use the add tool.",
            expect: { transcript in
                let calls = transcript.entries.filter { $0.kind == .toolCall }.map(\.toolName)
                return calls == ["add"]
            }
        )

        // T2. Multi-tool, model picks the right one (add).
        await runTools(
            "T2. multi-tool, picks add",
            tools: [AddTool(), MultiplyTool()],
            prompt: "Use a tool to compute 7 + 3.",
            expect: { transcript in
                let calls = transcript.entries.filter { $0.kind == .toolCall }.map(\.toolName)
                return calls.first == "add"
            }
        )

        // T3. Multi-tool, picks multiply.
        await runTools(
            "T3. multi-tool, picks multiply",
            tools: [AddTool(), MultiplyTool()],
            prompt: "Use a tool to compute 6 times 7.",
            expect: { transcript in
                let calls = transcript.entries.filter { $0.kind == .toolCall }.map(\.toolName)
                return calls.first == "multiply"
            }
        )

        // T4. Complex argument shape (string + int).
        await runTools(
            "T4. complex-arguments (lookup topic+limit)",
            tools: [LookupTool()],
            prompt: "Use the lookup tool to get 3 facts about Swift concurrency.",
            expect: { transcript in
                let call = transcript.entries.first { $0.kind == .toolCall }
                return call?.toolName == "lookup"
            }
        )

        // T5. Throwing tool surfaces as backend error.
        await runToolsExpectingError(
            "T5. throwing-tool surfaces error",
            tools: [AlwaysFailsTool()],
            prompt: "Use the boom tool with key=foo."
        )
    }

    mutating func runTools(
        _ label: String,
        tools: [any Tool],
        prompt: String,
        expect: (Transcript) -> Bool
    ) async {
        info("\(label) — prompt: \(prompt)")
        let session = LanguageModelSession(
            tools: tools,
            instructions: Instructions("Use the provided tools when applicable.")
        )
        let start = ContinuousClock.now
        do {
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.0, maximumResponseTokens: 256)
            )
            let dt = ContinuousClock.now - start
            let transcript = session.transcript
            let kinds = transcript.entries.map(\.kind)
            let toolCalls = transcript.entries.filter { $0.kind == .toolCall }
            let toolOutputs = transcript.entries.filter { $0.kind == .toolOutput }

            if expect(transcript) {
                ok("\(label) → tool used (\(toolCalls.compactMap(\.toolName).joined(separator: " → "))) (\(ms(dt)))")
                if let last = toolOutputs.last { info("  last tool output: \(last.content)") }
                info("  final assistant: \(response.content)")
                record(label, "PASS",
                       "calls=\(toolCalls.compactMap(\.toolName).joined(separator: ",")) final=\(response.content.prefix(60))")
            } else {
                warn("\(label) — model answered without invoking the expected tool (model-quality)")
                record(label, "MODEL",
                       "kinds=\(kinds) final=\(response.content.prefix(80))")
            }
        } catch let error as GenerationError {
            fail("\(label) → \(error)")
            record(label, "FAIL", "\(error)")
        } catch {
            fail("\(label) → \(error)")
            record(label, "FAIL", "\(error)")
        }
    }

    mutating func runToolsExpectingError(
        _ label: String,
        tools: [any Tool],
        prompt: String
    ) async {
        info("\(label) — prompt: \(prompt)")
        let session = LanguageModelSession(
            tools: tools,
            instructions: Instructions("You MUST call the tool.")
        )
        do {
            _ = try await session.respond(to: prompt)
            // Tool wasn't invoked; the model answered directly. Not a fail —
            // small model may decline — but log as MODEL.
            warn("\(label) — model answered without invoking the throwing tool (model-quality)")
            record(label, "MODEL", "tool not invoked")
        } catch let error as GenerationError {
            if case .backend(let inner) = error, inner is AlwaysFailsTool.Boom {
                ok("\(label) → caught Boom from tool via GenerationError.backend")
                record(label, "PASS", "Boom surfaced")
            } else if case .refusal = error {
                warn("\(label) — refusal (model emitted malformed tool call): \(error)")
                record(label, "MODEL", "refusal")
            } else {
                fail("\(label) → unexpected error: \(error)")
                record(label, "FAIL", "\(error)")
            }
        } catch {
            fail("\(label) → \(error)")
            record(label, "FAIL", "\(error)")
        }
    }
}

// MARK: - Duration helper

func ms(_ duration: Duration) -> String {
    let (s, attoseconds) = duration.components
    let total = Double(s) + Double(attoseconds) / 1e18
    return String(format: "%.0f ms", total * 1000)
}
