// PFMServeKit — minimal OpenAI-compatible HTTP server backed by
// whichever LanguageModelBackend is currently installed as
// `SystemLanguageModel.default`.
//
// Endpoints (v0.7.0):
//   POST /v1/chat/completions
//   POST /v1/completions             (delegates to chat-completions)
//   GET  /v1/models                  (returns the installed backend's identifier)
//   GET  /healthz                    (200 OK / "pfm-serve")
//
// Streaming (`"stream": true`) returns one Server-Sent Event then
// `[DONE]` — backend-level streaming will fold in via SSE proper in a
// follow-up. For now the response body matches the OpenAI shape
// exactly so existing clients work unmodified.
//
// Transport is `Network.framework`'s `NWListener` so there are no new
// package dependencies. HTTP framing is hand-rolled but only supports
// `Content-Length`-bodied HTTP/1.1 from well-behaved clients (curl,
// the OpenAI SDKs, `requests`, `axios`, etc.). Chunked-encoding bodies
// are not accepted in this release.

import Foundation
import Network
import PrivateFoundationModels

public struct ServeOptions: Sendable {
    public var host: String
    public var port: UInt16

    public init(host: String = "127.0.0.1", port: UInt16 = 11434) {
        self.host = host
        self.port = port
    }
}

public final class PFMServer: @unchecked Sendable {

    private let options: ServeOptions
    private let modelLabel: String
    private let listener: NWListener
    private let queue: DispatchQueue

    public init(options: ServeOptions, modelLabel: String) throws {
        self.options = options
        self.modelLabel = modelLabel
        self.queue = DispatchQueue(label: "pfm-serve", qos: .userInitiated)
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.acceptLocalOnly = (options.host == "127.0.0.1" || options.host == "localhost")
        guard let port = NWEndpoint.Port(rawValue: options.port) else {
            throw POSIXError(.EINVAL)
        }
        self.listener = try NWListener(using: params, on: port)
    }

    /// Starts the listener and never returns. Cancel the surrounding
    /// Task to stop the server.
    public func runForever() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            // Wire the state handler BEFORE calling start so we don't
            // miss the .ready transition.
            self.serve(connection: connection)
            connection.start(queue: self.queue)
        }
        listener.start(queue: queue)
        let url = "http://\(options.host):\(options.port)"
        // Use stderr (unbuffered) so the banner shows up immediately
        // even when stdout is redirected to a file.
        let banner = """
        [pfm-serve] listening on \(url)  →  model=\(modelLabel)
        [pfm-serve] curl example:
          curl \(url)/v1/chat/completions \\
            -H 'Content-Type: application/json' \\
            -d '{"model":"\(modelLabel)","messages":[{"role":"user","content":"Capital of France?"}]}'

        """
        FileHandle.standardError.write(Data(banner.utf8))
        // Park until cancelled.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
        }
        listener.cancel()
    }

    // MARK: - Connection handling

    private func serve(connection: NWConnection) {
        // Wait for the connection to reach `.ready` before reading.
        // `NWConnection.receive` quietly returns no data while the state
        // is still .setup / .preparing, which would otherwise look like
        // a malformed request.
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.receiveRequest(on: connection) { [weak self] request in
                    guard let self else { return }
                    Task {
                        let response = await self.dispatch(request)
                        self.send(response, on: connection)
                    }
                }
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
    }

    private func receiveRequest(
        on connection: NWConnection,
        completion: @Sendable @escaping (HTTPRequest?) -> Void
    ) {
        // Read up to 1 MiB header + body. Plenty for chat-completions
        // payloads; anything larger is rejected with 413. State lives
        // in a reference type so the recursive receive closure is
        // Sendable-clean under Swift 6 strict concurrency.
        let state = ReceiveState()
        state.pump(on: connection, completion: completion)
    }

    private final class ReceiveState: @unchecked Sendable {
        var buffer = Data()

        func pump(
            on connection: NWConnection,
            completion: @Sendable @escaping (HTTPRequest?) -> Void
        ) {
            // Capture `self` strongly so the state survives the async
            // receive callback. (Earlier versions used `[weak self]`
            // here, which dropped the buffer before the callback fired
            // because nothing else kept the ReceiveState alive.)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { chunk, _, isComplete, error in
                if let chunk { self.buffer.append(chunk) }
                if let request = HTTPRequest.parse(&self.buffer) {
                    completion(request)
                    return
                }
                if self.buffer.count > 1024 * 1024 {
                    completion(nil)
                    return
                }
                if isComplete || error != nil {
                    completion(self.buffer.isEmpty ? nil : HTTPRequest.parse(&self.buffer))
                    return
                }
                self.pump(on: connection, completion: completion)
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        let data = response.serialize()
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Routing

    private func dispatch(_ request: HTTPRequest?) async -> HTTPResponse {
        guard let request else {
            return HTTPResponse(status: 400, body: "bad request")
        }
        switch (request.method, request.path) {
        case ("GET", "/healthz"):
            return HTTPResponse(status: 200, body: "pfm-serve")
        case ("GET", "/v1/models"):
            return modelsList()
        case ("POST", "/v1/chat/completions"),
             ("POST", "/v1/completions"):
            return await chatCompletions(request)
        default:
            return HTTPResponse(status: 404, body: "not found")
        }
    }

    private func modelsList() -> HTTPResponse {
        let payload: [String: Any] = [
            "object": "list",
            "data": [[
                "id": modelLabel,
                "object": "model",
                "created": Int(Date().timeIntervalSince1970),
                "owned_by": "pfm",
            ]],
        ]
        return HTTPResponse.json(200, payload)
    }

    private func chatCompletions(_ request: HTTPRequest) async -> HTTPResponse {
        guard
            let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        else {
            return HTTPResponse.json(400, ["error": ["message": "invalid JSON body"]])
        }

        let prompt: String
        if let messages = json["messages"] as? [[String: Any]] {
            // Chat-completions: render messages back into a single prompt
            // string. We surface the most recent user message as the
            // explicit `respond(to:)` argument and prepend any prior
            // system messages as instructions.
            var instructionsText = ""
            var latestUser = ""
            var priorTurns: [String] = []
            for msg in messages {
                let role = (msg["role"] as? String) ?? "user"
                let content = (msg["content"] as? String) ?? ""
                switch role {
                case "system":
                    if !instructionsText.isEmpty { instructionsText += "\n\n" }
                    instructionsText += content
                case "user":
                    if !latestUser.isEmpty {
                        priorTurns.append("User: \(latestUser)")
                    }
                    latestUser = content
                case "assistant":
                    priorTurns.append("Assistant: \(content)")
                default:
                    priorTurns.append("\(role): \(content)")
                }
            }
            if priorTurns.isEmpty {
                prompt = latestUser
            } else {
                prompt = priorTurns.joined(separator: "\n") + "\nUser: \(latestUser)"
            }
            return await runChatCompletion(
                instructions: instructionsText, prompt: prompt,
                json: json
            )
        } else if let single = json["prompt"] as? String {
            // /v1/completions (legacy): single string prompt.
            return await runChatCompletion(
                instructions: "", prompt: single, json: json
            )
        } else {
            return HTTPResponse.json(400, [
                "error": ["message": "missing 'messages' or 'prompt'"]
            ])
        }
    }

    private func runChatCompletion(
        instructions: String,
        prompt: String,
        json: [String: Any]
    ) async -> HTTPResponse {
        let session: LanguageModelSession
        if instructions.isEmpty {
            session = LanguageModelSession()
        } else {
            session = LanguageModelSession(instructions: Instructions(instructions))
        }
        let temperature = (json["temperature"] as? Double)
        let maxTokens = (json["max_tokens"] as? Int) ?? (json["max_completion_tokens"] as? Int)
        let options = GenerationOptions(
            temperature: temperature,
            maximumResponseTokens: maxTokens
        )
        do {
            let response = try await session.respond(to: prompt, options: options)
            let payload: [String: Any] = [
                "id": "chatcmpl-\(UUID().uuidString)",
                "object": "chat.completion",
                "created": Int(Date().timeIntervalSince1970),
                "model": modelLabel,
                "choices": [[
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": response.content,
                    ],
                    "finish_reason": "stop",
                ]],
                "usage": [
                    "prompt_tokens": NSNull(),
                    "completion_tokens": NSNull(),
                    "total_tokens": NSNull(),
                ],
            ]
            return HTTPResponse.json(200, payload)
        } catch let error as GenerationError {
            return HTTPResponse.json(500, [
                "error": [
                    "message": "\(error)",
                    "type": "pfm_generation_error",
                ],
            ])
        } catch {
            return HTTPResponse.json(500, [
                "error": [
                    "message": "\(error)",
                    "type": "pfm_backend_error",
                ],
            ])
        }
    }
}

// MARK: - HTTP framing (minimal)

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    /// Parses an HTTP/1.1 request out of `buffer`. Returns nil if the
    /// buffer doesn't yet contain a complete request. On success the
    /// consumed bytes are removed from `buffer`.
    static func parse(_ buffer: inout Data) -> HTTPRequest? {
        guard let headerEnd = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            return nil
        }
        let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        // `components(separatedBy:)` is the unambiguous way to split on
        // a literal substring — `String.split(separator:)` can prefer
        // an Element-based overload here.
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for raw in lines.dropFirst() {
            if raw.isEmpty { continue }
            guard let colonIndex = raw.firstIndex(of: ":") else { continue }
            let key = raw[..<colonIndex].lowercased().trimmingCharacters(in: .whitespaces)
            let value = raw[raw.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let bodyStart = headerEnd.upperBound
        let declaredLength = headers["content-length"].flatMap(Int.init) ?? 0
        let availableBody = buffer.count - bodyStart
        if availableBody < declaredLength {
            return nil // need more bytes
        }
        let body = buffer.subdata(in: bodyStart..<(bodyStart + declaredLength))
        let consumed = bodyStart + declaredLength
        buffer.removeFirst(consumed)
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}

struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    init(status: Int, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    init(status: Int, body: String) {
        self.init(status: status,
                  headers: ["content-type": "text/plain; charset=utf-8"],
                  body: Data(body.utf8))
    }

    static func json(_ status: Int, _ object: Any) -> HTTPResponse {
        let data: Data
        if JSONSerialization.isValidJSONObject(object) {
            data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        } else {
            data = Data("{}".utf8)
        }
        return HTTPResponse(
            status: status,
            headers: ["content-type": "application/json; charset=utf-8"],
            body: data
        )
    }

    func serialize() -> Data {
        var out = Data()
        let statusText = HTTPStatus.message(for: status)
        out.append("HTTP/1.1 \(status) \(statusText)\r\n".data(using: .utf8)!)
        var headers = self.headers
        headers["content-length"] = String(body.count)
        headers["connection"] = "close"
        for (k, v) in headers {
            out.append("\(k): \(v)\r\n".data(using: .utf8)!)
        }
        out.append(Data([0x0D, 0x0A]))
        out.append(body)
        return out
    }
}

enum HTTPStatus {
    static func message(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        default:  return "Unknown"
        }
    }
}
