import XCTest
import CoreGraphics
import ImageIO

private final class FixtureURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [Data]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (statusCode, chunks) = try Self.handler?(request) ?? (500, [])
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private actor ProviderTestText {
    private(set) var value = ""
    func append(_ text: String) { value += text }
}

final class AIProviderTests: XCTestCase {
    func testCloudProviderReusesInjectedSessionKey() async throws {
        var requestCount = 0
        FixtureURLProtocol.handler = { request in
            requestCount += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-session-key")
            let event = #"data: {"choices":[{"delta":{"content":"Answer"},"finish_reason":"stop"}]}"# + "\n\ndata: [DONE]\n\n"
            return (200, [Data(event.utf8)])
        }
        defer { FixtureURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let provider = OpenRouterAIProvider(client: OpenRouterClient(session: session),
            model: OpenRouterModel.suggestions[0], apiKey: "test-session-key")
        for _ in 0..<3 {
            let collector = ProviderTestText()
            _ = try await provider.respond(AIRequest(imageData: Data([1]), prompt: "Explain", history: [], extendedReasoning: false)) {
                chunk in await collector.append(chunk)
            }
            let text = await collector.value
            XCTAssertEqual(text, "Answer")
        }
        XCTAssertEqual(requestCount, 3)
    }

    func testSSECommentsAndMultilineData() throws {
        var parser = ServerSentEventParser()
        XCTAssertNil(try parser.consume(": keepalive"))
        XCTAssertNil(try parser.consume("data: first"))
        XCTAssertNil(try parser.consume("data: second"))
        XCTAssertEqual(try parser.consume(""), "first\nsecond")
        XCTAssertFalse(parser.hasIncompleteEvent)
    }

    func testSSECompletionAndIncompleteEvent() throws {
        var parser = ServerSentEventParser()
        XCTAssertNil(try parser.consume("data: [DONE]"))
        XCTAssertTrue(parser.hasIncompleteEvent)
        XCTAssertEqual(try parser.consume(""), "[DONE]")
        XCTAssertFalse(parser.hasIncompleteEvent)
    }

    func testSSERejectsOversizedEvents() {
        var parser = ServerSentEventParser()
        XCTAssertThrowsError(try parser.consume("data: " + String(repeating: "a", count: 131_073)))
    }

    func testStreamingEventDecodesContentFinishReasonAndUsage() throws {
        let data = Data(#"{"choices":[{"delta":{"content":"answer"},"finish_reason":"stop"}],"usage":{"prompt_tokens":120,"completion_tokens":30,"cost":0.0001}}"#.utf8)
        let event = try JSONDecoder().decode(OpenRouterStreamEvent.self, from: data)
        XCTAssertEqual(event.choices?.first?.delta?.content, "answer")
        XCTAssertEqual(event.choices?.first?.finish_reason, "stop")
        XCTAssertEqual(event.usage?.prompt_tokens, 120)
    }

    func testRequestUsesExplicitModelAndKeepsKeyOutOfPayload() throws {
        let input = AIRequest(imageData: Data([1, 2, 3]), prompt: "Explain", history: [], extendedReasoning: false)
        let selected = OpenRouterModel.suggestions[1]
        let request = try OpenRouterClient.makeRequest(input, model: selected, apiKey: "test-only-key")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, "openrouter.ai")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-key")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "google/gemini-3.8-flash")
        XCTAssertEqual(payload["stream"] as? Bool, true)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("test-only-key"))
    }

    func testEmptyBatchAndOversizedRequestsAreRejected() {
        let input = AIRequest(imageData: Data([1]), prompt: "Explain", history: [], extendedReasoning: false)
        XCTAssertThrowsError(try OpenRouterClient.makeRequest(input, model: OpenRouterModel.suggestions[0], apiKey: ""))
        let batch = OpenRouterModel(id: "google/example:batch", name: "Batch", inputPrice: nil, outputPrice: nil, supportedParameters: [])
        XCTAssertThrowsError(try OpenRouterClient.makeRequest(input, model: batch, apiKey: "test-only-key"))
        let huge = AIRequest(imageData: Data(repeating: 0, count: 8_388_609), prompt: "Explain", history: [], extendedReasoning: false)
        XCTAssertThrowsError(try OpenRouterClient.makeRequest(huge, model: OpenRouterModel.suggestions[0], apiKey: "test-only-key"))
    }

    func testImagePreparationPreservesAspectRatioAndBounds() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2_000, height: 1_000, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = try ScanImageProcessing.pngData(for: image, maximumDimension: 1_000)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let scaled = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(scaled.width, 1_000)
        XCTAssertEqual(scaled.height, 500)
    }

    func testHTTPFailuresHaveActionableMessagesWithoutFallback() {
        XCTAssertTrue(OpenRouterClient.httpError(401).localizedDescription.contains("API key"))
        XCTAssertTrue(OpenRouterClient.httpError(402).localizedDescription.contains("credits"))
        XCTAssertTrue(OpenRouterClient.httpError(429).localizedDescription.contains("rate-limited"))
        XCTAssertTrue(OpenRouterClient.httpError(503).localizedDescription.contains("No automatic retry"))
    }

    func testStreamingTransportHandlesNetworkChunksAndUsage() async throws {
        let stream = #"data: {"choices":[{"delta":{"content":"Hello "}}]}"# + "\n\n"
            + #"data: {"choices":[{"delta":{"content":"world"},"finish_reason":"stop"}],"usage":{"prompt_tokens":12,"completion_tokens":2}}"# + "\n\n"
            + "data: [DONE]\n\n"
        let bytes = Data(stream.utf8)
        FixtureURLProtocol.handler = { _ in (200, [bytes.prefix(17), bytes.subdata(in: 17..<80), bytes.suffix(from: 80)]) }
        defer { FixtureURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let collector = ProviderTestText()
        let result = try await OpenRouterClient(session: session).respond(
            AIRequest(imageData: Data([1]), prompt: "Explain", history: [], extendedReasoning: false),
            model: OpenRouterModel.suggestions[0], apiKey: "test-only-key") { chunk in await collector.append(chunk) }
        let text = await collector.value
        XCTAssertEqual(text, "Hello world")
        XCTAssertEqual(result.inputTokens, 12)
        XCTAssertEqual(result.outputTokens, 2)
    }

    func testStreamingDisconnectDoesNotMasqueradeAsCompleteAnswer() async throws {
        FixtureURLProtocol.handler = { _ in (200, [Data((#"data: {"choices":[{"delta":{"content":"partial"}}]}"# + "\n\n").utf8)]) }
        defer { FixtureURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await OpenRouterClient(session: session).respond(
                AIRequest(imageData: Data([1]), prompt: "Explain", history: [], extendedReasoning: false),
                model: OpenRouterModel.suggestions[0], apiKey: "test-only-key", onChunk: { _ in })
            XCTFail("An interrupted stream must fail.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("connection ended"))
        }
    }

    func testAuthenticationFailureIsNotAutomaticallyRetried() async throws {
        var requestCount = 0
        FixtureURLProtocol.handler = { _ in requestCount += 1; return (401, []) }
        defer { FixtureURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await OpenRouterClient(session: session).respond(
                AIRequest(imageData: Data([1]), prompt: "Explain", history: [], extendedReasoning: false),
                model: OpenRouterModel.suggestions[0], apiKey: "test-only-key", onChunk: { _ in })
            XCTFail("Authentication must fail.")
        } catch { XCTAssertTrue(error.localizedDescription.contains("API key")) }
        XCTAssertEqual(requestCount, 1)
    }
}