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
            print("[LLMEvaluator] switchModel(...) called with: \(modelSelection)")
            try await load(modelSelection: modelSelection)
        } catch {
            // If local load fails, we handle it in generate.
            print("[LLMEvaluator] switchModel error: \(error.localizedDescription)")
            self.output = "Error: \(error.localizedDescription)"
        }
    }

    func load(modelSelection: ModelSelection) async throws {
        print("[LLMEvaluator] load(...) called for \(modelSelection)")
        switch modelSelection {
        case .local(let modelName):
            try await loadLocalModel(modelName: modelName)
        case .hosted:
            // Hosted models do not require local loading
            print("[LLMEvaluator] Hosted model does not require local load.")
            break
        }
    }

    private func loadLocalModel(modelName: String) async throws {
        guard let modelConfiguration = getModelByName(modelName) else {
            throw NSError(domain: "Model not found", code: 0, userInfo: nil)
        }

        switch loadState {
        case .idle:
            print("[LLMEvaluator] Begin loading local model: \(modelConfiguration.id)")
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            let modelContainer = try await MLXLLM.loadModelContainer(configuration: modelConfiguration) { progress in
                Task { @MainActor in
                    self.modelInfo = "Downloading \(modelConfiguration.name): \(Int(progress.fractionCompleted * 100))%"
                    self.progress = progress.fractionCompleted
                    print("[LLMEvaluator] Download progress: \(self.progress)")
                }
            }
            self.modelInfo = "Loaded \(modelConfiguration.id). Weights: \(MLX.GPU.activeMemory / 1024 / 1024)M"
            print("[LLMEvaluator] Finished loading local model: \(modelConfiguration.id)")
            loadState = .loaded(modelContainer, modelConfiguration)

        case .loaded:
            // Already loaded
            print("[LLMEvaluator] Model already loaded, skipping.")
            break
        }
    }

    func generate(modelSelection: ModelSelection, thread: Thread, systemPrompt: String) async -> String {
        print("[LLMEvaluator] generate(...) invoked. ModelSelection: \(modelSelection)")
        guard !running else {
            print("[LLMEvaluator] generate(...) aborted, already running.")
            return ""
        }
        running = true
        self.output = ""
        defer { running = false } // ensures `running` is reset even on errors

        do {
            switch modelSelection {
            case .local(let modelName):
                print("[LLMEvaluator] (Local) Checking if model is loaded...")
                try await loadLocalModel(modelName: modelName)
                guard case let .loaded(modelContainer, modelConfiguration) = loadState else {
                    throw NSError(domain: "Model not loaded", code: 0, userInfo: nil)
                }
                let extraEOSTokens = modelConfiguration.extraEOSTokens

                let promptHistory = modelConfiguration.getPromptHistory(thread: thread, systemPrompt: systemPrompt)
                let prompt = modelConfiguration.prepare(prompt: promptHistory)
                print("[LLMEvaluator] local prompt prepared.")

                let promptTokens = await modelContainer.perform { _, tokenizer in
                    tokenizer.encode(text: prompt)
                }
                print("[LLMEvaluator] prompt tokenized. Token count = \(promptTokens.count)")

                MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

                print("[LLMEvaluator] Starting token generation (local) ...")
                let result = await modelContainer.perform { model, tokenizer in
                    MLXLLM.generate(
                        promptTokens: promptTokens,
                        parameters: generateParameters,
                        model: model,
                        tokenizer: tokenizer,
                        extraEOSTokens: extraEOSTokens
                    ) { tokens in
                        // partial streaming tokens
                        if tokens.count % self.displayEveryNTokens == 0 {
                            let partial = tokenizer.decode(tokens: tokens)
                            Task { @MainActor in
                                self.output = partial
                            }
                        }
                        if tokens.count >= self.maxTokens {
                            return .stop
                        }
                        return .more
                    }
                }
                // Complete final output
                if result.output != self.output {
                    self.output = result.output
                }
                self.stat = " Tokens/s: \(String(format: "%.3f", result.tokensPerSecond))"
                print("[LLMEvaluator] local generation complete. Output length: \(self.output.count)")
                return self.output

            case .hosted(let hostedModel):
                print("[LLMEvaluator] (Hosted) calling generateWithHostedModel for: \(hostedModel.name)")
                let promptHistory = getPromptHistory(thread: thread, systemPrompt: systemPrompt)
                let finalText = try await generateWithHostedModel(hostedModel: hostedModel, promptHistory: promptHistory)
                self.output = finalText
                print("[LLMEvaluator] hosted generation complete. Output length: \(self.output.count)")
                return self.output
            }
        } catch {
            let err = "Error: \(error.localizedDescription)"
            print("[LLMEvaluator] generate(...) error: \(err)")
            self.output = err
            return self.output
        }
    }

    /// Return the final text so that ContentView can use it as a final assistant message
    private func generateWithHostedModel(hostedModel: HostedModel, promptHistory: String) async throws -> String {
        print("[LLMEvaluator] generateWithHostedModel(...) called. endpoint=\(hostedModel.endpoint)")
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

        // We'll store partial output in a local variable
        var combinedOutput = ""

        let sessionDelegate = SSESessionDelegate { eventContent in
            Task { @MainActor [weak self] in
                combinedOutput += eventContent
                print("[LLMEvaluator][SSESessionDelegate] partial eventContent: \(eventContent)")
                self?.output = combinedOutput
            }
        }
        let session = URLSession(configuration: .default, delegate: sessionDelegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        print("[LLMEvaluator] Sending SSE request to \(hostedModel.endpoint)")
        task.resume()

        try await withTaskCancellationHandler {
            task.cancel()
        } operation: {
            await sessionDelegate.waitForCompletion()
        }

        // Return final result (may include "Error: ..." if SSE had an error)
        return combinedOutput
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

    // A small struct to decode the raw error if needed
    struct ErrorJSON: Decodable {
        let object: String?
        let message: String?
        let type: String?
        let code: Int?
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let eventString = String(data: data, encoding: .utf8) else { return }
        print("[SSESessionDelegate] didReceive data chunk: \(eventString)")

        // Check if this might be a raw error JSON instead of SSE data
        if !eventString.hasPrefix("data: ") {
            // Attempt to parse as error JSON
            if let jsonData = eventString.data(using: .utf8),
               let errorObj = try? JSONDecoder().decode(ErrorJSON.self, from: jsonData),
               errorObj.object == "error",
               let msg = errorObj.message
            {
                onEvent("Error: \(msg)")
                return
            }
        }

        // Otherwise handle it as SSE data
        let events = parseSSE(data: eventString)
        for event in events {
            onEvent(event)
        }
    }

    struct ChatCompletionChunk: Decodable {
        let id: String
        let object: String
        let created: Int
        let model: String
        let choices: [ChunkChoice]
    }

    struct ChunkChoice: Decodable {
        let index: Int
        let delta: Delta
        let logprobs: String?
        let finish_reason: String?
    }

    struct Delta: Decodable {
        let role: String?
        let content: String?
    }

    func parseSSE(data: String) -> [String] {
        let lines = data.components(separatedBy: "\n")
        var events: [String] = []
        for line in lines {
            if line.hasPrefix("data: ") {
                let eventData = String(line.dropFirst(6))
                if eventData == "[DONE]" {
                    continue
                }
                if let jsonData = eventData.data(using: .utf8),
                   let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData) {
                    for choice in chunk.choices {
                        if let text = choice.delta.content, !text.isEmpty {
                            events.append(text)
                        }
                    }
                }
            }
        }
        return events
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let errText = "\nError: \(error.localizedDescription)"
            print("[SSESessionDelegate] SSE stream completed with error: \(errText)")
            onEvent(errText)
        } else {
            print("[SSESessionDelegate] SSE stream completed with no error.")
        }
        completionContinuation?.resume()
    }

    func waitForCompletion() async {
        await withCheckedContinuation { continuation in
            self.completionContinuation = continuation
        }
    }
}

