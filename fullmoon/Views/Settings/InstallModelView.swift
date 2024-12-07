import SwiftUI
import MLXLLM

struct InstallModelView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var llm: LLMEvaluator
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Available Models")) {
                    ForEach(ModelConfiguration.availableModels, id: \.name) { modelConfig in
                        HStack {
                            Text(appManager.modelDisplayName(modelConfig.name))
                                .font(.headline)

                            Spacer()

                            if appManager.installedModels.contains(modelConfig.name) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Installed")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                Button("Download") {
                                    Task {
                                        // Trigger loading the model, which downloads it
                                        try? await llm.load(modelSelection: .local(name: modelConfig.name))
                                        if llm.progress == 1.0 {
                                            // Add to installed if completed
                                            appManager.addInstalledModel(modelConfig.name)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Install Models")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
