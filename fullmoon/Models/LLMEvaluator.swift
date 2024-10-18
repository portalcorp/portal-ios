//
//  LLMEvaluator.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/4/24.
//

import MLX
import MLXLLM
import MLXRandom
import SwiftUI

@Observable
@MainActor
class LLMEvaluator: ObservableObject {
    var running = false
    var output = ""
    var modelInfo = ""
    var stat = ""
    var progress = 0.0

    var currentModelSelection: ModelSelection?

    let generateParameters = GenerateParameters(temperature: 0.5)
    let maxTokens = 4096
    let displayEveryNTokens = 4

    enum LoadState {
        case idle
        case loaded(ModelContainer, ModelConfiguration)
    }

    var loadState = LoadState.idle

    func switchModel(_ modelSelection: ModelSelection) async {
        progress = 0.0
        loadState = .idle
        currentModelSelection = modelSelection
        do {
            try await load(modelSelection: modelSelection)
        } catch {
            // Handle error
        }
    }

    func load(modelSelection: ModelSelection) async throws {
        switch modelSelection {
        case .local(let modelName):
            try await loadLocalModel(modelName: modelName)
        case .hosted(_):
            // No loading needed for hosted models
            break
        }
    }

    private func loadLocalModel(modelName: String) async throws {
        guard let modelConfiguration = getModelByName(modelName) else {
            throw NSError(domain: "Model not found", code: 0, userInfo: nil)
        }

        switch loadState {
        case .idle:
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            let modelContainer = try await MLXLLM.loadModelContainer(configuration: modelConfiguration) { progress in
                Task { @MainActor in
                    self.modelInfo = "Downloading \(modelConfiguration.name): \(Int(progress.fractionCompleted * 100))%"
                    self.progress = progress.fractionCompleted
                }
            }
            self.modelInfo = "Loaded \(modelConfiguration.id).  Weights: \(MLX.GPU.activeMemory / 1024 / 1024)M"
            loadState = .loaded(modelContainer, modelConfiguration)

        case .loaded(_, _):
            // Model is already loaded
            break
        }
    }

    func generate(modelSelection: ModelSelection, thread: Thread, systemPrompt: String) async -> String {
        guard !running else { return "" }
        running = true
        self.output = ""
        do {
            switch modelSelection {
            case .local(let modelName):
                try await loadLocalModel(modelName: modelName)
                guard case let .loaded(modelContainer, modelConfiguration) = loadState else {
                    throw NSError(domain: "Model not loaded", code: 0, userInfo: nil)
                }
                let extraEOSTokens = modelConfiguration.extraEOSTokens

                let promptHistory = modelConfiguration.getPromptHistory(thread: thread, systemPrompt: systemPrompt)
                let prompt = modelConfiguration.prepare(prompt: promptHistory)

                let promptTokens = await modelContainer.perform { _, tokenizer in
                    tokenizer.encode(text: prompt)
                }

                MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

                let result = await modelContainer.perform { model, tokenizer in
                    MLXLLM.generate(
                        promptTokens: promptTokens, parameters: generateParameters, model: model,
                        tokenizer: tokenizer, extraEOSTokens: extraEOSTokens
                    ) { tokens in
                        if tokens.count % displayEveryNTokens == 0 {
                            let text = tokenizer.decode(tokens: tokens)
                            Task { @MainActor in
                                self.output = text
                            }
                        }
                        if tokens.count >= maxTokens {
                            return .stop
                        } else {
                            return .more
                        }
                    }
                }

                if result.output != self.output {
                    self.output = result.output
                }
                self.stat = " Tokens/second: \(String(format: "%.3f", result.tokensPerSecond))"

            case .hosted(let hostedModel):
                let promptHistory = getPromptHistory(thread: thread, systemPrompt: systemPrompt)
                try await generateWithHostedModel(hostedModel: hostedModel, promptHistory: promptHistory)
            }
        } catch {
            output = "Failed: \(error)"
        }
        running = false
        return output
    }

    func generateWithHostedModel(hostedModel: HostedModel, promptHistory: String) async throws {
        guard let url = URL(string: hostedModel.endpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": hostedModel.name,
            "messages": [
                ["role": "user", "content": promptHistory]
            ],
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let sessionDelegate = SSESessionDelegate { [weak self] event in
            Task { @MainActor in
                self?.output += event
            }
        }

        let session = URLSession(configuration: .default, delegate: sessionDelegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()

        try await withTaskCancellationHandler {
            task.cancel()
        } operation: {
            await sessionDelegate.waitForCompletion()
        }
    }

    func getPromptHistory(thread: Thread, systemPrompt: String) -> String {
        var history = systemPrompt + "\n"
        for message in thread.sortedMessages {
            history += "\(message.role): \(message.content)\n"
        }
        return history
    }

    func getModelByName(_ name: String) -> ModelConfiguration? {
        return ModelConfiguration.availableModels.first { $0.name == name }
    }
}

class SSESessionDelegate: NSObject, URLSessionDataDelegate {
    var onEvent: ((String) -> Void)
    private var completionContinuation: CheckedContinuation<Void, Never>?

    init(onEvent: @escaping (String) -> Void) {
        self.onEvent = onEvent
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let eventString = String(data: data, encoding: .utf8) {
            let events = parseSSE(data: eventString)
            for event in events {
                onEvent(event)
            }
        }
    }

    func parseSSE(data: String) -> [String] {
        let lines = data.components(separatedBy: "\n")
        var events: [String] = []
        for line in lines {
            if line.hasPrefix("data: ") {
                let eventData = String(line.dropFirst(6))
                events.append(eventData)
            }
        }
        return events
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completionContinuation?.resume()
    }

    func waitForCompletion() async {
        await withCheckedContinuation { continuation in
            self.completionContinuation = continuation
        }
    }
}
