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

    /// CSV row with the same columns as `markdownRow`, plus a
    /// hardware label and timestamp so per-machine results from
    /// different contributors collate cleanly into one table.
    public func csvRow(hardware: String, timestamp: String = isoNow()) -> String {
        let medTTFT = median(ttftMs)
        let medTotal = median(totalMs)
        let medChars = Double(median(outputChars))
        let charsPerSec = medTotal > 0 ? (medChars / (medTotal / 1000.0)) : 0
        // Quote fields that may contain commas / spaces. The label and
        // hardware tag are the only realistic offenders.
        let quotedLabel = "\"\(label.replacingOccurrences(of: "\"", with: "\"\""))\""
        let quotedHW = "\"\(hardware.replacingOccurrences(of: "\"", with: "\"\""))\""
        return String(
            format: "%@,%@,%@,%.0f,%.0f,%.0f,%.0f,%.1f",
            timestamp, quotedHW, quotedLabel,
            loadMs, medTTFT, medTotal, medChars, charsPerSec
        )
    }

    public static let csvHeader =
        "timestamp,hardware,backend,load_ms,ttft_ms,total_ms,output_chars,chars_per_sec"
}

/// Convenience for stamping CSV rows.
public func isoNow() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: Date())
}

/// Auto-detect a human-readable hardware label via sysctl
/// (`machdep.cpu.brand_string` returns "Apple M4 Max" etc.). Falls
/// back to "unknown-mac" when sysctl is unavailable.
public func autoHardwareLabel() -> String {
    var size: size_t = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    guard size > 0 else { return "unknown-mac" }
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
    return String(cString: buffer)
}

/// Common CLI output handler. Reads `--csv` and `--csv-append`,
/// `--hardware <label>` (defaults to autoHardwareLabel()) from the
/// process args and emits each row in the requested format(s):
///
/// - Default (no flags): pretty summaries + markdown rows on stdout.
/// - `--csv`:             one CSV row per BenchRow on stdout, with
///                        header on the first line.
/// - `--csv-append PATH`: append rows to PATH; writes header line
///                        if PATH doesn't exist yet. Pretty stdout
///                        output is still emitted alongside.
public func emitBenchOutput(_ rows: [BenchRow]) {
    let args = CommandLine.arguments.dropFirst()
    let csvStdout = args.contains("--csv")
    var csvPath: String?
    var hardware = autoHardwareLabel()
    var it = args.makeIterator()
    while let arg = it.next() {
        if arg == "--csv-append", let p = it.next() { csvPath = p }
        if arg == "--hardware", let h = it.next() { hardware = h }
    }
    let timestamp = isoNow()

    if csvStdout {
        print(BenchRow.csvHeader)
        for row in rows { print(row.csvRow(hardware: hardware, timestamp: timestamp)) }
        return  // CSV-only mode — pretty output suppressed for clean piping
    }

    for row in rows { print(row.summary()) }
    print()
    print("Markdown:")
    for row in rows { print(row.markdownRow()) }

    if let csvPath {
        print()
        print("Appending CSV rows to \(csvPath) (hw=\"\(hardware)\")…")
        for row in rows {
            do {
                try appendCSV(row.csvRow(hardware: hardware, timestamp: timestamp), to: csvPath)
            } catch {
                FileHandle.standardError.write(Data("CSV append failed: \(error)\n".utf8))
            }
        }
    }
}

/// Append a row to a CSV file, writing the header line if the file
/// doesn't exist yet. Used by the `--csv-append <path>` flag so a
/// shared `docs/BENCHMARKS.csv` can grow with contributions from
/// other machines without manual editing.
public func appendCSV(_ row: String, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let exists = FileManager.default.fileExists(atPath: url.path)
    let payload: String
    if exists {
        payload = row + "\n"
    } else {
        payload = BenchRow.csvHeader + "\n" + row + "\n"
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(payload.utf8))
    try handle.close()
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
