// PFMBenchKit — backend-agnostic single-prompt latency / throughput
// harness. Each `BenchRow` captures load_ms, time-to-first-token,
// total_ms, character count, and chars/sec across a small number of
// iterations so the per-run jitter shows up in the spread.
//
// Used by the per-backend pfm-bench-* executables. Each of those
// loads its backend, installs it as `SystemLanguageModel.default`,
// then calls `Bench.runAll(label:loadMs:)` which prints a
// machine-readable row plus the markdown summary.

import Foundation
import PrivateFoundationModels

public struct BenchOptions {
    /// Identical across all backends so the row is apples-to-apples.
    public static let prompt = "Write a single-sentence Swift fact in under 30 words."
    public static let maxTokens = 80
    public static let temperature: Double = 0.0
    public static let iterations = 3
}

public struct BenchRow {
    public var label: String
    public var loadMs: Double
    public var ttftMs: [Double]   // time-to-first-token per iteration
    public var totalMs: [Double]  // streamResponse wall time per iteration
    public var outputChars: [Int]
}

extension BenchRow {
    public func summary() -> String {
        let medTTFT = median(ttftMs)
        let medTotal = median(totalMs)
        let medChars = Double(median(outputChars))
        let charsPerSec = medTotal > 0 ? (medChars / (medTotal / 1000.0)) : 0
        return String(
            format: """
            ────────────────────────────────────────────────────────────────
             %@
            ────────────────────────────────────────────────────────────────
              load:              %.0f ms
              time-to-first-tok: %.0f ms (median, %d runs)
              total respond:     %.0f ms (median)
              output chars:      %.0f (median)
              throughput:        %.1f chars/sec
            """,
            label, loadMs,
            medTTFT, ttftMs.count,
            medTotal, medChars, charsPerSec
        )
    }

    public func markdownRow() -> String {
        let medTTFT = median(ttftMs)
        let medTotal = median(totalMs)
        let medChars = Double(median(outputChars))
        let charsPerSec = medTotal > 0 ? (medChars / (medTotal / 1000.0)) : 0
        return String(
            format: "| %@ | %.0f ms | %.0f ms | %.0f ms | %.0f | %.1f |",
            label, loadMs, medTTFT, medTotal, medChars, charsPerSec
        )
    }
}

private func median<T: Comparable & BinaryFloatingPoint>(_ xs: [T]) -> T {
    let sorted = xs.sorted()
    if sorted.isEmpty { return 0 }
    return sorted[sorted.count / 2]
}

private func median(_ xs: [Int]) -> Int {
    let sorted = xs.sorted()
    if sorted.isEmpty { return 0 }
    return sorted[sorted.count / 2]
}

public enum Bench {

    /// Run `BenchOptions.iterations` warm streaming `respond` calls
    /// against the currently-installed backend. Caller supplies the
    /// label and load time (loading is backend-specific so it stays
    /// outside this kit).
    public static func runAll(label: String, loadMs: Double) async -> BenchRow {
        var ttfts: [Double] = []
        var totals: [Double] = []
        var chars: [Int] = []

        // Warmup: one untimed pass so caches / KV state settle.
        _ = try? await runOnce(timed: false)

        for _ in 0..<BenchOptions.iterations {
            if let r = try? await runOnce(timed: true) {
                ttfts.append(r.ttft)
                totals.append(r.total)
                chars.append(r.chars)
            }
        }

        return BenchRow(
            label: label, loadMs: loadMs,
            ttftMs: ttfts, totalMs: totals, outputChars: chars
        )
    }

    private static func runOnce(timed: Bool) async throws
        -> (ttft: Double, total: Double, chars: Int)
    {
        let session = LanguageModelSession(instructions: Instructions("Be brief."))
        let options = GenerationOptions(
            temperature: BenchOptions.temperature,
            maximumResponseTokens: BenchOptions.maxTokens
        )
        let start = ContinuousClock.now
        var firstAt: ContinuousClock.Instant?
        var lastText = ""

        let stream = session.streamResponse(to: BenchOptions.prompt, options: options)
        for try await snapshot in stream {
            let text = snapshot.content
            if firstAt == nil, !text.isEmpty {
                firstAt = ContinuousClock.now
            }
            lastText = text
        }
        let end = ContinuousClock.now

        let totalMs = millis(start...end)
        let ttftMs = firstAt.map { millis(start...$0) } ?? totalMs
        return (ttftMs, totalMs, lastText.count)
    }

    private static func millis(_ range: ClosedRange<ContinuousClock.Instant>) -> Double {
        let dur = range.upperBound - range.lowerBound
        let (s, atto) = dur.components
        return (Double(s) + Double(atto) / 1e18) * 1000
    }
}
