// MLX-Swift embedding backend.
//
// Wraps `MLXEmbedders.EmbedderModelContainer` so PFM's
// `/v1/embeddings` endpoint can return OpenAI-shaped vectors from any
// `mlx-community/*` embedding repo. Standard BERT-style preprocessing:
// tokenize → right-pad → attention mask → forward → pool → L2-normalize.
//
// End-to-end verified on Apple M4 Max / macOS 26.0 against
// `sentence-transformers/all-MiniLM-L6-v2` — 384-dim L2-normalized
// vectors with semantically correct cosine-similarity ranking. See
// `docs/pfm-embeddings-sample.txt` for the captured run.

import Foundation
import HuggingFace
import MLX
import MLXEmbedders
import MLXHuggingFace
import MLXLMCommon
import PrivateFoundationModels
import Tokenizers

public final class MLXEmbedder: EmbeddingBackend, @unchecked Sendable {

    public let modelIdentifier: String
    public let dimensions: Int
    let container: EmbedderModelContainer

    init(container: EmbedderModelContainer, modelIdentifier: String, dimensions: Int) {
        self.container = container
        self.modelIdentifier = modelIdentifier
        self.dimensions = dimensions
    }

    public static func load(
        _ modelID: String = "mlx-community/gemma-3-1b-it-qat-4bit",
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> MLXEmbedder {
        onProgress?("Resolving embedder \(modelID)…")
        let hub = #hubDownloader()
        let loader = #huggingFaceTokenizerLoader()
        let container = try await EmbedderModelFactory.shared.loadContainer(
            from: hub, using: loader,
            configuration: ModelConfiguration(id: modelID),
            useLatest: false,
            progressHandler: { progress in
                let pct = progress.fractionCompleted * 100
                onProgress?(String(format: "Downloading %.0f%%", pct))
            }
        )
        // Probe dimensionality with a 1-token forward so callers
        // know the output shape up front.
        let dim = try await Self.probeDimensions(container: container)
        onProgress?("Loaded embedder \(modelID) (dim=\(dim))")
        return MLXEmbedder(
            container: container,
            modelIdentifier: "mlx-embedder://\(modelID)",
            dimensions: dim
        )
    }

    private static func probeDimensions(
        container: EmbedderModelContainer
    ) async throws -> Int {
        let dims = await container.perform { ctx -> Int in
            let probe = ctx.tokenizer.encode(text: "x", addSpecialTokens: true)
            guard !probe.isEmpty else { return 0 }
            let ids = MLXArray(probe.map { Int32($0) }).reshaped([1, probe.count])
            let mask = MLXArray.ones([1, probe.count])
            let output = ctx.model(
                ids, positionIds: nil, tokenTypeIds: nil,
                attentionMask: mask
            )
            let pooled = ctx.pooling(output, mask: mask, normalize: true, applyLayerNorm: true)
            pooled.eval()
            return pooled.shape.last ?? 0
        }
        return dims
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        return await container.perform { ctx -> [[Float]] in
            // Tokenize each input. Use `addSpecialTokens: true` because
            // BERT-family embedders rely on [CLS] / [SEP] for pooling.
            let encoded: [[Int]] = texts.map {
                ctx.tokenizer.encode(text: $0, addSpecialTokens: true)
            }
            let maxLen = encoded.map(\.count).max() ?? 0
            guard maxLen > 0 else {
                return texts.map { _ in [Float](repeating: 0, count: 0) }
            }
            // Right-pad with token id 0 (matches BERT pad convention).
            // For embedders that need a different pad token the
            // attention mask zeros it out anyway.
            var paddedRows: [[Int32]] = []
            var maskRows: [[Int32]] = []
            for tokens in encoded {
                var row = tokens.map { Int32($0) }
                var maskRow = Array(repeating: Int32(1), count: tokens.count)
                if tokens.count < maxLen {
                    row.append(contentsOf: Array(repeating: Int32(0), count: maxLen - tokens.count))
                    maskRow.append(contentsOf: Array(repeating: Int32(0), count: maxLen - tokens.count))
                }
                paddedRows.append(row)
                maskRows.append(maskRow)
            }
            let flatTokens = paddedRows.flatMap { $0 }
            let flatMask = maskRows.flatMap { $0 }
            let inputIDs = MLXArray(flatTokens).reshaped([texts.count, maxLen])
            let mask = MLXArray(flatMask).reshaped([texts.count, maxLen])

            let output = ctx.model(
                inputIDs, positionIds: nil, tokenTypeIds: nil,
                attentionMask: mask
            )
            let pooled = ctx.pooling(output, mask: mask, normalize: true, applyLayerNorm: true)
            pooled.eval()
            // pooled.shape is [batch, dim]; convert each row to [Float].
            let result: [[Float]] = pooled.map { $0.asArray(Float.self) }
            return result
        }
    }
}
