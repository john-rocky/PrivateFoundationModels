import Testing
@testable import PrivateFoundationModels

@Suite("Instructions")
struct InstructionsTests {
    @Test func plainInit() {
        let inst = Instructions("Be brief.")
        #expect(inst.text == "Be brief.")
    }

    @Test func stringLiteralInit() {
        let inst: Instructions = "Answer in English."
        #expect(inst.text == "Answer in English.")
    }

    @Test func equatable() {
        #expect(Instructions("foo") == Instructions("foo"))
        #expect(Instructions("foo") != Instructions("bar"))
    }

    @Test func description() {
        #expect("\(Instructions("hello"))" == "hello")
    }
}
