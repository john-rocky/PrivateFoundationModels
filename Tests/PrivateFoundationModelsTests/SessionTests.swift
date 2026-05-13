import Foundation
import Testing
@testable import PrivateFoundationModels

@Suite("LanguageModelSession")
struct SessionTests {
    // MARK: - Basic respond

    @Test func respondAppendsPromptAndResponse() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: "Hello!"))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model, instructions: "Be brief.")

        let reply = try await session.respond(to: "Hi")
        #expect(reply.content == "Hello!")

        let transcript = session.transcript
        #expect(transcript.entries.count == 3) // instructions, prompt, response
        #expect(transcript.entries[0].kind == .instructions)
        #expect(transcript.entries[1].kind == .prompt)
        #expect(transcript.entries[1].content == "Hi")
        #expect(transcript.entries[2].kind == .response)
        #expect(transcript.entries[2].content == "Hello!")
    }

    @Test func respondPassesTranscriptToBackend() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: "Sure"))
        stub.enqueue(.init(text: "Right"))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        _ = try await session.respond(to: "First")
        _ = try await session.respond(to: "Second")

        // On the second call the backend saw the running transcript: prompt
        // 1, response 1, prompt 2.
        let last = stub.lastTranscript
        #expect(last?.entries.count == 3)
        #expect(last?.entries[0].content == "First")
        #expect(last?.entries[1].content == "Sure")
        #expect(last?.entries[2].content == "Second")
    }

    @Test func respondPropagatesOptions() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: "ok"))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        let opts = GenerationOptions(temperature: 0.42, maximumResponseTokens: 7)
        _ = try await session.respond(to: "Hi", options: opts)
        #expect(stub.lastOptions?.temperature == 0.42)
        #expect(stub.lastOptions?.maximumResponseTokens == 7)
    }

    // MARK: - Generable

    struct Echo: Generable, Equatable {
        let text: String
        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: "object",
                properties: ["text": .init(type: "string")],
                required: ["text"]
            )
        }
    }

    @Test func respondGenerable() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: #"{"text":"world"}"#))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        let reply = try await session.respond(to: "Say hi", generating: Echo.self)
        #expect(reply.content == Echo(text: "world"))
        // Backend got the schema
        #expect(stub.lastSchema?.type == "object")
    }

    @Test func respondGenerableFailsOnGarbledJSON() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: "not json"))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        do {
            // maximumRetries: 0 keeps the original single-shot semantics
            // for this test; the dedicated retry behavior lives in
            // generableAutoRetriesOnDecodingFailure below.
            _ = try await session.respond(to: "Say hi", generating: Echo.self,
                                           maximumRetries: 0)
            Issue.record("expected decodingFailure to throw")
        } catch let error as GenerationError {
            if case .decodingFailure(let raw) = error {
                #expect(raw == "not json")
            } else {
                Issue.record("expected decodingFailure, got \(error)")
            }
        }
    }

    // MARK: - Streaming

    @Test func streamResponseEmitsCumulativeSnapshots() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(chunks: ["Hello ", "world", "!"]))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        let stream = session.streamResponse(to: "Hi")
        var snapshots: [String] = []
        for try await snapshot in stream {
            snapshots.append(snapshot.content)
        }
        #expect(snapshots == ["Hello ", "Hello world", "Hello world!"])

        let final = try await stream.collect()
        #expect(final.content == "Hello world!")

        let transcript = session.transcript
        #expect(transcript.entries.last?.content == "Hello world!")
    }

    // MARK: - Tools

    struct EchoTool: Tool {
        struct Arguments: Generable {
            let value: String
            static var generationSchema: GenerationSchema {
                GenerationSchema(
                    type: "object",
                    properties: ["value": .init(type: "string")],
                    required: ["value"]
                )
            }
        }
        let name = "echo"
        let description = "Echoes its argument."
        func call(arguments: Arguments) async throws -> String {
            "echoed:" + arguments.value
        }
    }

    @Test func toolCallLoopAppendsCallAndOutput() async throws {
        let stub = StubBackend()
        // Round 1: model asks for tool. Round 2: model returns final text
        // after seeing the tool output.
        stub.enqueue(.init(toolCalls: [.init(name: "echo", argumentsJSON: #"{"value":"hi"}"#)]))
        stub.enqueue(.init(text: "done"))

        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(
            model: model,
            instructions: nil,
            tools: [AnyTool(EchoTool())]
        )

        let reply = try await session.respond(to: "Use the tool.")
        #expect(reply.content == "done")

        let transcript = session.transcript
        let kinds = transcript.entries.map(\.kind)
        #expect(kinds == [.prompt, .toolCall, .toolOutput, .response])
        #expect(transcript.entries[1].toolName == "echo")
        #expect(transcript.entries[2].content == "echoed:hi")
    }

    @Test func unknownToolNameThrowsRefusal() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(toolCalls: [.init(name: "missing", argumentsJSON: "{}")]))

        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        do {
            _ = try await session.respond(to: "Hi")
            Issue.record("expected refusal")
        } catch let error as GenerationError {
            if case .refusal = error {} else { Issue.record("expected refusal, got \(error)") }
        }
    }

    // MARK: - Transcript rehydration

    @Test func restoresFromTranscript() async throws {
        let original = Transcript(entries: [
            .init(kind: .instructions, content: "Be brief."),
            .init(kind: .prompt, content: "Hi"),
            .init(kind: .response, content: "Hello"),
        ])
        let stub = StubBackend()
        stub.enqueue(.init(text: "Sure"))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model, transcript: original)

        _ = try await session.respond(to: "Again?")

        let updated = session.transcript
        #expect(updated.entries.count == 5)
        #expect(updated.entries[3].content == "Again?")
        #expect(updated.entries[4].content == "Sure")
    }

    // MARK: - Concurrent rejection

    @Test func concurrentCallsThrow() async throws {
        let stub = StubBackend()
        // 50 ms forces task A to suspend inside the backend before task B
        // can race for `beginRequest`. The race is otherwise scheduler-
        // dependent because the synchronous stub returns immediately.
        stub.artificialDelay = .milliseconds(50)
        stub.enqueue(.init(text: "first"))
        stub.enqueue(.init(text: "second"))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        let firstTask = Task<Result<Response<String>, Error>, Never> {
            do { return .success(try await session.respond(to: "one")) }
            catch { return .failure(error) }
        }
        // Give task A a chance to enter `beginRequest` before task B starts.
        try await Task.sleep(for: .milliseconds(5))
        let secondTask = Task<Result<Response<String>, Error>, Never> {
            do { return .success(try await session.respond(to: "two")) }
            catch { return .failure(error) }
        }

        let results = await [firstTask.value, secondTask.value]

        var sawConcurrent = false
        var sawSuccess = false
        for result in results {
            switch result {
            case .success:
                sawSuccess = true
            case .failure(let err as GenerationError):
                if case .concurrentRequests = err { sawConcurrent = true }
            case .failure:
                break
            }
        }
        #expect(sawSuccess)
        #expect(sawConcurrent)
    }

    // MARK: - Generable auto-retry on decoding failure

    struct RetryCity: Generable, Equatable {
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
    }

    /// When the first attempt returns garbage JSON, the session retries
    /// up to `maximumRetries` more times before throwing
    /// `decodingFailure`. Each retry pulls a fresh reply from the
    /// backend.
    @Test func generableAutoRetriesOnDecodingFailure() async throws {
        let stub = StubBackend()
        // Attempt 1: bad JSON. Attempt 2: good JSON.
        stub.enqueue(.init(text: "not json at all"))
        stub.enqueue(.init(text: #"{"city":"Paris","country":"France"}"#))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        let reply = try await session.respond(
            to: "Pick a landmark.",
            generating: RetryCity.self
        )
        #expect(reply.content == RetryCity(city: "Paris", country: "France"))
    }

    /// When every attempt fails, the final decodingFailure carries the
    /// last raw response.
    @Test func generableThrowsAfterRetriesExhausted() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: "bad-1"))
        stub.enqueue(.init(text: "bad-2"))
        stub.enqueue(.init(text: "bad-3"))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        do {
            _ = try await session.respond(
                to: "Pick a landmark.",
                generating: RetryCity.self,
                maximumRetries: 2
            )
            Issue.record("expected decodingFailure")
        } catch let error as GenerationError {
            if case .decodingFailure(let raw) = error {
                #expect(raw == "bad-3")
            } else {
                Issue.record("unexpected error: \(error)")
            }
        }
    }

    /// `maximumRetries: 0` disables auto-retry — the first decode
    /// failure throws immediately. Restores Apple-FM-strict behavior.
    @Test func generableMaximumRetriesZeroDisablesRetry() async throws {
        let stub = StubBackend()
        stub.enqueue(.init(text: "still bad"))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        do {
            _ = try await session.respond(
                to: "Pick a landmark.",
                generating: RetryCity.self,
                maximumRetries: 0
            )
            Issue.record("expected decodingFailure")
        } catch let error as GenerationError {
            if case .decodingFailure(let raw) = error {
                #expect(raw == "still bad")
            } else {
                Issue.record("unexpected error: \(error)")
            }
        }
    }

    // MARK: - Transcript delta (backends that ran the tool loop opaquely)

    /// When a backend reports `transcriptDelta` alongside the final
    /// text (e.g. Apple FM, which runs its tool loop internally), the
    /// session must append those entries to its own transcript before
    /// recording the final `.response`. This makes the audit trail
    /// match what a session would see if it had driven the tool loop
    /// turn-by-turn itself.
    @Test func transcriptDeltaIsAppendedBeforeResponse() async throws {
        let stub = StubBackend()
        let delta: [Transcript.Entry] = [
            Transcript.Entry(
                kind: .toolCall,
                content: "add({\"a\":17,\"b\":25})",
                toolName: "add",
                toolArguments: #"{"a":17,"b":25}"#
            ),
            Transcript.Entry(
                kind: .toolOutput,
                content: "42",
                toolName: "add"
            ),
        ]
        stub.enqueue(.init(text: "17 plus 25 is 42.", transcriptDelta: delta))
        let model = SystemLanguageModel(backend: stub)
        let session = LanguageModelSession(model: model)

        let reply = try await session.respond(to: "What is 17 + 25?")
        #expect(reply.content == "17 plus 25 is 42.")

        let entries = session.transcript.entries
        // prompt, toolCall, toolOutput, response — in order.
        #expect(entries.count == 4)
        #expect(entries[0].kind == .prompt)
        #expect(entries[1].kind == .toolCall)
        #expect(entries[1].toolName == "add")
        #expect(entries[1].toolArguments == #"{"a":17,"b":25}"#)
        #expect(entries[2].kind == .toolOutput)
        #expect(entries[2].toolName == "add")
        #expect(entries[2].content == "42")
        #expect(entries[3].kind == .response)
        #expect(entries[3].content == "17 plus 25 is 42.")
    }
}
