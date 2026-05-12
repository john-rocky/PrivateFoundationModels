import Foundation

/// The return value of `LanguageModelSession.streamResponse(...)`. Mirrors
/// `FoundationModels.ResponseStream`.
///
/// Iterating the stream yields `Snapshot` values — each one is the *full*
/// content emitted so far, not a delta. Apple's framework chose snapshots
/// over deltas so SwiftUI views can bind directly to the latest snapshot
/// without bookkeeping. We preserve that contract.
///
/// ```swift
/// let stream = session.streamResponse(to: "Write a haiku.")
/// for try await snapshot in stream {
///     view.text = snapshot.content   // full text so far
/// }
/// let final = try await stream.collect()
/// ```
public struct ResponseStream<Content: Sendable>: AsyncSequence, Sendable {
    public typealias Element = Snapshot

    /// One emission in the stream. `content` is cumulative.
    public struct Snapshot: Sendable {
        public let content: Content

        public init(content: Content) {
            self.content = content
        }
    }

    private let stream: AsyncThrowingStream<Snapshot, Error>
    private let finalize: @Sendable () async throws -> Response<Content>

    /// Internal: constructed by the session, not by user code.
    public init(
        stream: AsyncThrowingStream<Snapshot, Error>,
        finalize: @escaping @Sendable () async throws -> Response<Content>
    ) {
        self.stream = stream
        self.finalize = finalize
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: stream.makeAsyncIterator())
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var base: AsyncThrowingStream<Snapshot, Error>.AsyncIterator

        public mutating func next() async throws -> Snapshot? {
            try await base.next()
        }
    }

    /// Drain the stream and return the final `Response`. After this call the
    /// stream's iterator is exhausted; calling it twice rethrows the same
    /// terminal value (the `Response` is cached by the closure capture).
    public func collect() async throws -> Response<Content> {
        for try await _ in self { /* drain so the backend signals finalize */ }
        return try await finalize()
    }
}
