import Foundation

/// Backend that turns text into fixed-size vectors. Mirrors the shape
/// of OpenAI's `/v1/embeddings` endpoint:
///
/// - Input: an array of strings.
/// - Output: an array of float vectors, one per input, all the same
///   dimension.
///
/// PFM's chat / Generable / Tool surfaces all flow through
/// `LanguageModelBackend`. Embeddings live on a separate protocol
/// because the input / output shapes don't overlap and most backends
/// either generate text **or** embed text, not both.
///
/// Install an embedder by setting `SystemLanguageModel.defaultEmbedder`
/// once at app startup; `pfm-serve`'s `/v1/embeddings` endpoint reads
/// from this slot.
public protocol EmbeddingBackend: Sendable {
    /// Stable identifier reported in `/v1/embeddings`'s `model` field
    /// and exposed via `GET /v1/models` next to the chat models.
    var modelIdentifier: String { get }

    /// Embed each input string into a `dimensions`-sized vector.
    /// Implementations should preserve order — output element `i`
    /// corresponds to input element `i`.
    func embed(_ texts: [String]) async throws -> [[Float]]

    /// Hidden-state dimensionality. Returned in `/v1/embeddings`'s
    /// `usage` field and useful for callers that need to allocate
    /// destination buffers up front.
    var dimensions: Int { get }
}
