import Foundation
import Combine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import CoreText

struct ServerSentEventParser {
    private var dataLines: [String] = []
    private var bufferedCount = 0

    mutating func consume(_ line: String) throws -> String? {
        if line.isEmpty {
            defer { dataLines.removeAll(); bufferedCount = 0 }
            return dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
        }
        guard line.hasPrefix("data:") else { return nil }
        var data = String(line.dropFirst(5))
        if data.first == " " { data.removeFirst() }
        bufferedCount += data.utf8.count
        guard bufferedCount <= 131_072 else { throw AIError.message("The provider sent an oversized streaming event.") }
        dataLines.append(data)
        return nil
    }

    var hasIncompleteEvent: Bool { !dataLines.isEmpty }
}

struct OpenRouterStreamEvent: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta?
        let finish_reason: String?
    }
    struct Usage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let cost: Double?
    }
    struct Failure: Decodable { let message: String? }
    let choices: [Choice]?
    let usage: Usage?
    let error: Failure?
}

struct OpenRouterClient: @unchecked Sendable {
    let session: URLSession
    static let baseURL = URL(string: "https://openrouter.ai/api/v1")!

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 90
            configuration.timeoutIntervalForResource = 180
            self.session = URLSession(configuration: configuration)
        }
    }

    static func makeRequest(_ input: AIRequest, model: OpenRouterModel, apiKey: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw AIError.missingKey }
        guard !model.id.isEmpty, !model.id.contains(":batch") else { throw AIError.noCloudModel }
        guard !input.imageData.isEmpty, input.imageData.count <= 8_388_608 else {
            throw AIError.message("The selected crop is empty or exceeds the upload limit.")
        }
        var messages: [[String: Any]] = [["role": "system", "content": AIRequest.instructions]]
        messages += input.boundedHistory.map { ["role": $0.role.rawValue, "content": $0.text] }
        messages.append(["role": "user", "content": [
            ["type": "image_url", "image_url": ["url": "data:image/png;base64," + input.imageData.base64EncodedString()]],
            ["type": "text", "text": String(input.prompt.prefix(3_000))]
        ]])
        var payload: [String: Any] = ["model": model.id, "messages": messages, "stream": true, "stream_options": ["include_usage": true]]
        let tokenKey = model.supportedParameters.contains("max_completion_tokens") ? "max_completion_tokens" : "max_tokens"
        payload[tokenKey] = input.extendedReasoning ? 4_096 : 2_048
        if model.supportedParameters.contains("reasoning") {
            payload["reasoning"] = ["effort": input.extendedReasoning ? "medium" : "low", "exclude": true] as [String: Any]
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("FlowSnip", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    func respond(_ input: AIRequest, model: OpenRouterModel, apiKey: String,
                 onChunk: @escaping @Sendable (String) async -> Void) async throws -> AIResponseMetadata {
        let request = try Self.makeRequest(input, model: model, apiKey: apiKey)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.message("OpenRouter returned an invalid response.") }
        guard http.statusCode == 200 else { throw Self.httpError(http.statusCode) }
        var parser = ServerSentEventParser()
        var metadata = AIResponseMetadata()
        var receivedText = false
        var complete = false
        var outputCount = 0
        var lineBuffer = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte != 10 {
                lineBuffer.append(byte)
                guard lineBuffer.count <= 131_072 else { throw AIError.message("The provider sent an oversized streaming line.") }
                continue
            }
            if lineBuffer.last == 13 { lineBuffer.removeLast() }
            guard let line = String(data: lineBuffer, encoding: .utf8) else {
                throw AIError.message("The provider sent invalid UTF-8 streaming data.")
            }
            lineBuffer.removeAll(keepingCapacity: true)
            guard let data = try parser.consume(line) else { continue }
            if data == "[DONE]" { complete = true; break }
            let event: OpenRouterStreamEvent
            do { event = try JSONDecoder().decode(OpenRouterStreamEvent.self, from: Data(data.utf8)) }
            catch { throw AIError.message("OpenRouter sent a malformed streaming response.") }
            if let failure = event.error {
                let safeMessage = String((failure.message ?? "The provider could not finish the request.").replacingOccurrences(of: apiKey, with: "[redacted]").prefix(400))
                throw AIError.message(safeMessage)
            }
            for choice in event.choices ?? [] {
                if let chunk = choice.delta?.content, !chunk.isEmpty {
                    outputCount += chunk.count
                    guard outputCount <= 40_000 else { throw AIError.message("The answer exceeded the response limit.") }
                    receivedText = true
                    await onChunk(chunk)
                }
                if let reason = choice.finish_reason {
                    complete = true
                    metadata.truncated = reason == "length"
                }
            }
            if let usage = event.usage {
                metadata.inputTokens = usage.prompt_tokens
                metadata.outputTokens = usage.completion_tokens
                metadata.costUSD = usage.cost
            }
        }
        try Task.checkCancellation()
        guard complete, lineBuffer.isEmpty, !parser.hasIncompleteEvent else { throw AIError.message("The connection ended before the answer completed. Retry explicitly to make a new request.") }
        guard receivedText else { throw AIError.emptyResponse }
        return metadata
    }

    func verifyKey(_ apiKey: String) async throws {
        guard !apiKey.isEmpty else { throw AIError.missingKey }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("key"))
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Self.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func catalog() async throws -> [OpenRouterModel] {
        struct Response: Decodable {
            struct Model: Decodable {
                struct Architecture: Decodable { let input_modalities: [String]?; let output_modalities: [String]? }
                struct Pricing: Decodable { let prompt: String?; let completion: String? }
                let id: String
                let name: String
                let architecture: Architecture?
                let pricing: Pricing?
                let supported_parameters: [String]?
            }
            let data: [Model]
        }
        let (data, response) = try await session.data(from: Self.baseURL.appendingPathComponent("models"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AIError.message("The model catalog is unavailable. Saved choices are unchanged.") }
        return try JSONDecoder().decode(Response.self, from: data).data.compactMap { model in
            guard model.architecture?.input_modalities?.contains("image") == true,
                  model.architecture?.output_modalities == ["text"], !model.id.contains(":batch") else { return nil }
            return OpenRouterModel(id: model.id, name: model.name,
                inputPrice: model.pricing?.prompt.flatMap(Double.init), outputPrice: model.pricing?.completion.flatMap(Double.init),
                supportedParameters: model.supported_parameters ?? [])
        }.sorted { left, right in
            if left.suggested != right.suggested { return left.suggested }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    static func httpError(_ code: Int) -> AIError {
        switch code {
        case 401: return .message("OpenRouter rejected the API key. Update it in AI Settings.")
        case 402: return .message("The OpenRouter account needs credits. Add credits or choose a local model.")
        case 429: return .message("OpenRouter rate-limited this request. Wait before retrying.")
        case 400, 404: return .message("The selected model is unavailable or rejected the image request. Review the model choice.")
        case 403: return .message("The selected provider declined the request.")
        default: return .message("The provider could not complete the request (HTTP \(code)). No automatic retry was made.")
        }
    }
}

struct OpenRouterAIProvider: AIProvider {
    let client: OpenRouterClient
    let model: OpenRouterModel
    let apiKey: String
    func respond(_ request: AIRequest, onChunk: @escaping @Sendable (String) async -> Void) async throws -> AIResponseMetadata {
        return try await client.respond(request, model: model, apiKey: apiKey, onChunk: onChunk)
    }
}

@MainActor
final class OpenRouterCatalog: ObservableObject {
    @Published private(set) var models: [OpenRouterModel]
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: String?
    private let cacheURL: URL
    let client = OpenRouterClient()

    init(storageDirectory: URL) {
        cacheURL = storageDirectory.appendingPathComponent("OpenRouterModels.json")
        if let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode([OpenRouterModel].self, from: data), !cached.isEmpty {
            models = cached
        } else { models = OpenRouterModel.suggestions }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let refreshed = try await client.catalog()
            try Task.checkCancellation()
            models = refreshed
            error = nil
            try? JSONEncoder().encode(refreshed).write(to: cacheURL, options: .atomic)
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    func model(_ identifier: String) -> OpenRouterModel? { models.first { $0.id == identifier } }
}

enum ScanImageProcessing {
    static func pngData(for image: CGImage, maximumDimension: Int = 1_600) throws -> Data {
        guard maximumDimension > 0, image.width > 0, image.height > 0 else { throw AIError.message("Invalid crop dimensions.") }
        let scale = min(1, Double(maximumDimension) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw AIError.message("The crop could not be prepared for analysis.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { throw AIError.message("The crop could not be prepared.") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw AIError.message("The crop could not be encoded.")
        }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { throw AIError.message("The crop could not be encoded.") }
        return data as Data
    }

    static func extractText(from image: CGImage) async throws -> String {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            try Task.checkCancellation()
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
}

enum ScanValidationFixtures {
    struct Fixture {
        let name: String
        let image: CGImage
        let prompt: String
        let expectedTerms: [String]
    }

    static func make() throws -> [Fixture] {
        [
            Fixture(name: "Code error", image: try image(lines: ["SYNTHETIC CODE ERROR", "TypeError: Cannot read properties of undefined", "items.map(item => item.name)", "items is undefined"], chart: false),
                prompt: "What causes this error? Give one concrete fix in two sentences.", expectedTerms: ["undefined"]),
            Fixture(name: "Receipt", image: try image(lines: ["SYNTHETIC RECEIPT", "Coffee              4.00 EUR", "Notebook           12.50 EUR", "Subtotal           16.50 EUR", "Tax                 3.30 EUR", "TOTAL              19.80 EUR"], chart: false),
                prompt: "Extract the total and currency from this receipt. Answer in one sentence.", expectedTerms: ["19.8", "EUR"]),
            Fixture(name: "Chart", image: try image(lines: ["SYNTHETIC SALES CHART", "Orders per month"], chart: true),
                prompt: "Which month has the highest bar, and what is its value? Answer in one sentence.", expectedTerms: ["feb", "20"])
        ]
    }

    private static func image(lines: [String], chart: Bool) throws -> CGImage {
        guard let context = CGContext(data: nil, width: 900, height: 550, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw AIError.message("Could not create the validation image.")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 900, height: 550))
        func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 24) {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Menlo" as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.08, alpha: 1)
            ]
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
        }
        for (index, line) in lines.enumerated() { draw(line, x: 32, y: 492 - CGFloat(index) * 48) }
        if chart {
            let colors = [CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1), CGColor(red: 0.15, green: 0.65, blue: 0.4, alpha: 1), CGColor(red: 0.8, green: 0.35, blue: 0.2, alpha: 1)]
            for (index, value) in [10, 20, 15].enumerated() {
                let x = 130 + CGFloat(index) * 230
                context.setFillColor(colors[index])
                context.fill(CGRect(x: x, y: 90, width: 130, height: CGFloat(value) * 13))
                draw(String(value), x: x + 42, y: 105 + CGFloat(value) * 13)
                draw(["Jan", "Feb", "Mar"][index], x: x + 30, y: 50)
            }
        }
        guard let image = context.makeImage() else { throw AIError.message("Could not create the validation image.") }
        return image
    }
}