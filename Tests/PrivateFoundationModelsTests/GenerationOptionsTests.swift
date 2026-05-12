import Testing
@testable import PrivateFoundationModels

@Suite("GenerationOptions + SamplingMode")
struct GenerationOptionsTests {
    @Test func defaults() {
        let options = GenerationOptions()
        #expect(options.sampling == nil)
        #expect(options.temperature == nil)
        #expect(options.maximumResponseTokens == nil)
    }

    @Test func samplingGreedyEquatable() {
        #expect(SamplingMode.greedy == SamplingMode.greedy)
    }

    @Test func samplingRandomEquatable() {
        let a = SamplingMode.random(top: 40, probabilityThreshold: 0.95, seed: 42)
        let b = SamplingMode.random(top: 40, probabilityThreshold: 0.95, seed: 42)
        let c = SamplingMode.random(top: 40, probabilityThreshold: 0.95, seed: 43)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func fullInit() {
        let options = GenerationOptions(
            sampling: .random(top: 50),
            temperature: 0.7,
            maximumResponseTokens: 256
        )
        #expect(options.sampling == .random(top: 50))
        #expect(options.temperature == 0.7)
        #expect(options.maximumResponseTokens == 256)
    }
}
