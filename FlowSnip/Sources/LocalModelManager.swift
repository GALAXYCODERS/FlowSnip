import Foundation
import Combine
import HuggingFace

@MainActor
final class LocalModelManager: ObservableObject {
    let runtime = LocalModelRuntime()
    let hardware: MacHardwareSnapshot
    let storageDirectory: URL
    private let cache: HubCache
    private let client: HubClient
    private var downloadTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var calibrationTask: Task<Void, Never>?
    private var pressureSource: DispatchSourceMemoryPressure?
    @Published private(set) var downloadedModels: Set<String> = []
    @Published private(set) var downloadModelID: String?
    @Published private(set) var downloadProgress = 0.0
    @Published private(set) var downloadStatus = ""
    @Published private(set) var downloadError: String?
    @Published private(set) var isGenerating = false
    @Published private(set) var lastMetrics: LocalInferenceMetrics?
    @Published private(set) var isCalibrating = false
    @Published private(set) var calibrationStatus = ""

    init(hardware: MacHardwareSnapshot, storageDirectory: URL? = nil) {
        self.hardware = hardware
        self.storageDirectory = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FlowSnip", isDirectory: true)
        cache = HubCache(cacheDirectory: self.storageDirectory.appendingPathComponent("Models", isDirectory: true))
        client = HubClient(host: URL(string: "https://huggingface.co")!, userAgent: "FlowSnip/2.0", bearerToken: nil, cache: cache)
        try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
        refreshDownloads()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in await self?.runtime.unload() }
        }
        source.resume()
        pressureSource = source
    }

    deinit {
        downloadTask?.cancel()
        idleTask?.cancel()
        calibrationTask?.cancel()
        pressureSource?.cancel()
    }

    func directory(for model: LocalModelSpec) -> URL? {
        guard downloadedModels.contains(model.id), let repo = Repo.ID(rawValue: model.id) else { return nil }
        return try? cache.snapshotPath(repo: repo, kind: .model, commitHash: model.revision)
    }

    func refreshDownloads() {
        downloadedModels = Set(LocalModelSpec.all.compactMap { model in
            guard let repo = Repo.ID(rawValue: model.id),
                  let directory = try? cache.snapshotPath(repo: repo, kind: .model, commitHash: model.revision),
                  let marker = try? String(contentsOf: markerURL(for: model), encoding: .utf8), marker == model.revision,
                  (try? Self.validateArtifacts(in: directory)) != nil else { return nil }
            return model.id
        })
    }

    func startDownload(_ model: LocalModelSpec) {
        guard downloadTask == nil else { return }
        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer { self.downloadTask = nil }
            do { try await self.download(model) }
            catch is CancellationError { self.downloadStatus = "Paused; resume to continue." }
            catch {
                if Task.isCancelled { self.downloadStatus = "Paused; resume to continue." }
                else { self.downloadError = error.localizedDescription }
            }
        }
    }

    func cancelDownload() {
        downloadStatus = "Pausing download..."
        downloadTask?.cancel()
    }

    func download(_ model: LocalModelSpec) async throws {
        guard hardware.supports(model) else { throw AIError.unsupportedHardware }
        guard downloadModelID == nil else { throw AIError.busy }
        if downloadedModels.contains(model.id) { return }
        guard let repo = Repo.ID(rawValue: model.id) else { throw AIError.modelMissing }
        downloadModelID = model.id
        downloadProgress = 0
        downloadError = nil
        downloadStatus = "Downloading \(model.name)"
        defer { downloadModelID = nil }
        try FileManager.default.createDirectory(at: cache.cacheDirectory, withIntermediateDirectories: true)
        let values = try cache.cacheDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values.volumeAvailableCapacityForImportantUsage, capacity < model.weightBytes + 536_870_912 {
            throw AIError.message("At least \(model.downloadLabel) plus 512 MB of free storage is required for this model.")
        }
        let directory = try await client.downloadSnapshot(of: repo, revision: model.revision,
            matching: ["*.json", "*.safetensors", "*.jinja", "LICENSE*"], maxConcurrentDownloads: 2,
            progressHandler: { [weak self] progress in
                guard let self, self.downloadModelID == model.id else { return }
                self.downloadProgress = min(max(progress.fractionCompleted, 0), 1)
            })
        try Task.checkCancellation()
        downloadStatus = "Verifying model files..."
        try Self.validateArtifacts(in: directory)
        let marker = markerURL(for: model)
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try model.revision.write(to: marker, atomically: true, encoding: .utf8)
        downloadedModels.insert(model.id)
        downloadProgress = 1
        downloadStatus = "\(model.name) is ready."
    }

    func delete(_ model: LocalModelSpec) async throws {
        guard downloadModelID == nil, !isGenerating, !isCalibrating else { throw AIError.busy }
        await runtime.unload()
        guard let repo = Repo.ID(rawValue: model.id) else { throw AIError.modelMissing }
        let directory = cache.repoDirectory(repo: repo, kind: .model)
        guard directory.standardizedFileURL.path.hasPrefix(cache.cacheDirectory.standardizedFileURL.path + "/") else {
            throw AIError.message("Invalid model storage path.")
        }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        if FileManager.default.fileExists(atPath: markerURL(for: model).path) { try FileManager.default.removeItem(at: markerURL(for: model)) }
        downloadedModels.remove(model.id)
        downloadStatus = "Model removed."
    }

    func respond(_ request: AIRequest, model: LocalModelSpec,
                 onChunk: @escaping @Sendable (String) async -> Void) async throws -> LocalInferenceMetrics {
        guard !isGenerating else { throw AIError.busy }
        guard hardware.supports(model) else { throw AIError.unsupportedHardware }
        guard let directory = directory(for: model) else { throw AIError.modelMissing }
        idleTask?.cancel()
        isGenerating = true
        defer {
            isGenerating = false
            scheduleIdleUnload()
        }
        let metrics = try await runtime.respond(directory: directory, identifier: model.id, request: request, onChunk: onChunk)
        lastMetrics = metrics
        return metrics
    }

    func unload() async { await runtime.unload() }

    func startCalibration(_ model: LocalModelSpec) {
        guard calibrationTask == nil, !isGenerating else { return }
        calibrationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.calibrationTask = nil }
            do { _ = try await self.calibrate(model) }
            catch is CancellationError { self.calibrationStatus = "Calibration stopped." }
            catch { self.calibrationStatus = error.localizedDescription }
        }
    }

    func cancelCalibration() { calibrationTask?.cancel() }

    func calibrate(_ model: LocalModelSpec) async throws -> LocalCalibrationReport {
        guard !isCalibrating, !isGenerating else { throw AIError.busy }
        isCalibrating = true
        defer { isCalibrating = false }
        var results: [LocalCalibrationReport.Result] = []
        for fixture in try ScanValidationFixtures.make() {
            try Task.checkCancellation()
            calibrationStatus = "Checking \(fixture.name.lowercased())..."
            let collector = CalibrationTextCollector()
            let request = AIRequest(imageData: try ScanImageProcessing.pngData(for: fixture.image),
                prompt: fixture.prompt, history: [], extendedReasoning: false)
            let metrics = try await respond(request, model: model) { chunk in await collector.append(chunk) }
            let answer = await collector.text
            let passed = fixture.expectedTerms.allSatisfy { answer.localizedCaseInsensitiveContains($0) }
            results.append(.init(name: fixture.name, answer: answer, matchedExpectedContent: passed, metrics: metrics))
        }
        let report = LocalCalibrationReport(modelID: model.id, revision: model.revision, chip: hardware.chip,
            memoryGB: hardware.memoryGB, date: Date(), results: results)
        try JSONEncoder().encode(report).write(to: storageDirectory.appendingPathComponent("Calibration.json"), options: .atomic)
        calibrationStatus = "\(results.filter(\.matchedExpectedContent).count) of \(results.count) fixture checks matched."
        return report
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(180))
                await self?.runtime.unload()
            } catch {}
        }
    }

    private func markerURL(for model: LocalModelSpec) -> URL {
        storageDirectory.appendingPathComponent("CompletedModels", isDirectory: true)
            .appendingPathComponent(model.id.replacingOccurrences(of: "/", with: "--") + ".revision")
    }

    static func validateArtifacts(in directory: URL) throws {
        let required = ["config.json", "tokenizer.json", "tokenizer_config.json", "preprocessor_config.json"]
        for filename in required {
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path) else {
                throw AIError.message("The model download is incomplete. Resume it in AI Settings.")
            }
        }
        let configuration = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("config.json"))) as? [String: Any]
        guard configuration?["model_type"] as? String == "qwen3_5", configuration?["vision_config"] is [String: Any] else {
            throw AIError.message("This snapshot is not a supported vision-language model.")
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let weights = files.filter { $0.pathExtension == "safetensors" }
        guard !weights.isEmpty else { throw AIError.modelMissing }
        for file in weights {
            guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 > 8 else { throw AIError.modelMissing }
        }
        let indexURL = directory.appendingPathComponent("model.safetensors.index.json")
        if FileManager.default.fileExists(atPath: indexURL.path),
           let index = try JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any],
           let map = index["weight_map"] as? [String: String] {
            for filename in Set(map.values) {
                guard !filename.contains("/"), FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path) else {
                    throw AIError.message("A model weight shard is missing. Resume the download.")
                }
            }
        }
    }
}

struct LocalCalibrationReport: Codable, Sendable {
    struct Result: Codable, Sendable {
        let name: String
        let answer: String
        let matchedExpectedContent: Bool
        let metrics: LocalInferenceMetrics
    }
    let modelID: String
    let revision: String
    let chip: String
    let memoryGB: Int
    let date: Date
    let results: [Result]
}

private actor CalibrationTextCollector {
    private(set) var text = ""
    func append(_ chunk: String) { text += chunk }
}

struct LocalAIProvider: AIProvider {
    let manager: LocalModelManager
    let model: LocalModelSpec

    func respond(_ request: AIRequest, onChunk: @escaping @Sendable (String) async -> Void) async throws -> AIResponseMetadata {
        let metrics = try await manager.respond(request, model: model, onChunk: onChunk)
        return AIResponseMetadata(localMetrics: metrics)
    }
}