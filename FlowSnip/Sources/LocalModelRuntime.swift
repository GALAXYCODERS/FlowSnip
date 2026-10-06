import Foundation
import CoreImage
import MLX
import MLXVLM
import MLXLMCommon
import HuggingFace
import Tokenizers

private struct OfflineModelDownloader: MLXLMCommon.Downloader {
    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool, progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        throw CocoaError(.fileNoSuchFile)
    }
}

private struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        LocalTokenizerAdapter(upstream: try await Tokenizers.AutoTokenizer.from(modelFolder: directory))
    }
}

private struct LocalTokenizerAdapter: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }
    func encode(text: String, addSpecialTokens: Bool) -> [Int] { upstream.encode(text: text, addSpecialTokens: addSpecialTokens) }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ identifier: Int) -> String? { upstream.convertIdToToken(identifier) }
    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?) throws -> [Int] {
        try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
    }
}

actor LocalModelRuntime {
    private var container: ModelContainer?
    private var modelID: String?
    private var isGenerating = false
    private var unloadRequested = false

    private func load(directory: URL, identifier: String) async throws {
        if modelID == identifier, container != nil { return }
        container = nil
        modelID = nil
        MLX.Memory.clearCache()
        let loaded = try await VLMModelFactory.shared.loadContainer(
            from: OfflineModelDownloader(),
            using: LocalTokenizerLoader(),
            configuration: ModelConfiguration(directory: directory)
        )
        try Task.checkCancellation()
        container = loaded
        modelID = identifier
    }

    func unload() {
        if isGenerating {
            unloadRequested = true
            return
        }
        container = nil
        modelID = nil
        MLX.Memory.clearCache()
    }

    func respond(directory: URL, identifier: String, request: AIRequest,
                 onChunk: @escaping @Sendable (String) async -> Void) async throws -> LocalInferenceMetrics {
        guard !isGenerating else { throw AIError.busy }
        isGenerating = true
        defer {
            isGenerating = false
            if unloadRequested {
                unloadRequested = false
                unload()
            }
        }
        let start = Date()
        try Task.checkCancellation()
        MLX.Memory.cacheLimit = 128 * 1_024 * 1_024
        try await load(directory: directory, identifier: identifier)
        guard let container, let image = CIImage(data: request.imageData) else { throw AIError.modelMissing }
        let history: [Chat.Message] = request.boundedHistory.map {
            $0.role == .user ? .user($0.text) : .assistant($0.text)
        }
        let parameters = GenerateParameters(maxTokens: request.extendedReasoning ? 2_048 : 768,
            maxKVSize: 8_192, temperature: 0.4, topP: 0.8, topK: 20)
        let session = ChatSession(container, instructions: AIRequest.instructions, history: history,
            generateParameters: parameters, processing: .init(),
            additionalContext: ["enable_thinking": request.extendedReasoning])
        var firstTokenTime: TimeInterval?
        var textCount = 0
        do {
            for try await chunk in session.streamResponse(to: String(request.prompt.prefix(3_000)), image: .ciImage(image)) {
                try Task.checkCancellation()
                if firstTokenTime == nil { firstTokenTime = Date().timeIntervalSince(start) }
                textCount += chunk.count
                guard textCount <= 40_000 else { throw AIError.message("The answer exceeded the response limit.") }
                await onChunk(chunk)
            }
            await session.synchronize()
            try Task.checkCancellation()
            guard textCount > 0 else { throw AIError.emptyResponse }
        } catch {
            await session.synchronize()
            throw error
        }
        return LocalInferenceMetrics(firstTokenSeconds: firstTokenTime ?? 0,
            totalSeconds: Date().timeIntervalSince(start), peakMemoryBytes: MLX.Memory.snapshot().peakMemory)
    }
}