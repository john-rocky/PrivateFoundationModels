import Foundation
import Testing
@testable import PrivateFoundationModels

@Suite("Transcript")
struct TranscriptTests {
    @Test func emptyInit() {
        let t = Transcript()
        #expect(t.entries.isEmpty)
    }

    @Test func entriesInit() {
        let t = Transcript(entries: [
            .init(kind: .instructions, content: "Be brief."),
            .init(kind: .prompt, content: "Hi"),
            .init(kind: .response, content: "Hello"),
        ])
        #expect(t.entries.count == 3)
        #expect(t.entries[0].kind == .instructions)
        #expect(t.entries[1].kind == .prompt)
        #expect(t.entries[2].kind == .response)
    }

    @Test func toolEntries() {
        let entry = Transcript.Entry(
            kind: .toolCall,
            content: "weather(Tokyo)",
            toolName: "weather",
            toolArguments: #"{"city":"Tokyo"}"#
        )
        #expect(entry.toolName == "weather")
        #expect(entry.toolArguments == #"{"city":"Tokyo"}"#)
    }

    @Test func serializeRoundTrip() throws {
        let original = Transcript(entries: [
            .init(kind: .instructions, content: "Be terse."),
            .init(kind: .prompt, content: "Hi"),
            .init(kind: .response, content: "Hello"),
            .init(kind: .toolCall, content: "weather(...)", toolName: "weather", toolArguments: #"{"city":"Tokyo"}"#),
            .init(kind: .toolOutput, content: "22C", toolName: "weather"),
        ])
        let data = try original.serialized()
        let restored = try Transcript(serialized: data)
        #expect(restored.entries.count == original.entries.count)
        #expect(restored.entries[0].content == "Be terse.")
        #expect(restored.entries[3].toolName == "weather")
        #expect(restored.entries[3].toolArguments == #"{"city":"Tokyo"}"#)
        #expect(restored.entries[4].kind == .toolOutput)
    }

    @Test func description() {
        let t = Transcript(entries: [
            .init(kind: .instructions, content: "be brief"),
            .init(kind: .prompt, content: "hi"),
            .init(kind: .response, content: "hello"),
        ])
        let s = String(describing: t)
        #expect(s.contains("[instructions] be brief"))
        #expect(s.contains("[user] hi"))
        #expect(s.contains("[assistant] hello"))
    }
}
