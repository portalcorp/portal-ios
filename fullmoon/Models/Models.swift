//
//  Models.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/4/24.
//

import MLXLLM
import Foundation

extension ModelConfiguration: @retroactive Equatable {
    public static func == (lhs: MLXLLM.ModelConfiguration, rhs: MLXLLM.ModelConfiguration) -> Bool {
        return lhs.name == rhs.name
    }
    
    public static let llama_3_2_1B = ModelConfiguration(
        id: "mlx-community/Llama-3.2-1B-Instruct-bf16"
    )
    
    public static let llama_3_2_3b_8bit = ModelConfiguration(
        id: "mlx-community/Llama-3.2-3B-Instruct-8bit"
    )
    
    public static let qwen_3b = ModelConfiguration(
        id: "mlx-community/Qwen2.5-3B-Instruct-8bit"
    )
    
    public static let qwen_1_5b = ModelConfiguration(
        id: "mlx-community/Qwen2.5-1.5B-Instruct-bf16"
    )
    
    public static var availableModels: [ModelConfiguration] = [
        llama_3_2_1B,
        llama_3_2_3b_8bit,
        qwen_3b,
        qwen_1_5b
    ]
    
    public static var defaultModel: ModelConfiguration {
        llama_3_2_1B
    }
    
    func getPromptHistory(thread: Thread, systemPrompt: String) -> String {
        var history = ""
        
        switch self {
        case .llama_3_2_1B, .llama_3_2_3b_8bit, .qwen_3b, .qwen_1_5b:
            history = "<|begin_of_text|>"
            history += "<|start_header_id|>system<|end_header_id|>\n\(systemPrompt)"
            
            for message in thread.sortedMessages {
                print(message.content)
                if message.role == .user {
                    history += "<|eot_id|>\n<|start_header_id|>user<|end_header_id|>\n\(message.content)\n<|eot_id|>\n<|start_header_id|>assistant<|end_header_id|>"
                }
                
                if message.role == .assistant {
                    history += message.content + "\n"
                }
            }
        default:
            break;
        }
        return history
    }
}
