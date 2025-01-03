import SwiftUI
import MLXLLM

struct ModelsSettingsView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var llm: LLMEvaluator

    // Separate flags for local vs. hosted flows:
    @State private var showInstallLocalModelSheet = false

    // For "Add or Edit" hosted model
    @State private var hostedModelToEdit: HostedModel? = nil  // .sheet(item:) uses an Identifiable type

    var body: some View {
        List {
            // ============== LOCAL MODELS SECTION ==============
            Section {
                Button {
                    // Show local "InstallModelView"
                    showInstallLocalModelSheet = true
                } label: {
                    Label("Install a model", systemImage: "arrow.down.circle.dotted")
                }
            }

            Section(header: Text("Installed")) {
                ForEach(appManager.installedModels, id: \.self) { modelName in
                    Button {
                        Task {
                            await switchModel(.local(name: modelName))
                        }
                    } label: {
                        Label {
                            Text(appManager.modelDisplayName(modelName))
                        } icon: {
                            Image(systemName: isCurrentModelLocal(modelName) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
                .onDelete(perform: deleteLocalModels)
            }

            // ============== HOSTED MODELS SECTION ==============
            Section(header: Text("Hosted Models")) {
                ForEach(appManager.hostedModels, id: \.id) { hostedModel in
                    Button {
                        Task {
                            await switchModel(.hosted(model: hostedModel))
                        }
                    } label: {
                        Label {
                            Text(hostedModel.name)
                        } icon: {
                            Image(systemName: isCurrentModelHosted(hostedModel) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            deleteHostedModel(hostedModel)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            // We want to edit this model
                            hostedModelToEdit = hostedModel
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }

                Button {
                    // Add brand-new hosted model
                    // The id is generated automatically
                    hostedModelToEdit = HostedModel(name: "", endpoint: "")
                } label: {
                    Label("Add Hosted Model", systemImage: "plus")
                }
            }
        }
        .navigationTitle("models")
        .navigationBarTitleDisplayMode(.inline)

        // ============== SHEET FOR INSTALL MODEL ==============
        .sheet(isPresented: $showInstallLocalModelSheet) {
            NavigationStack {
                InstallModelView()
                    .environmentObject(appManager)
                    .environmentObject(llm)
            }
        }

        // ============== SHEET FOR ADD/EDIT HOSTED MODEL ==============
        .sheet(item: $hostedModelToEdit) { model in
            // If model.name is empty => "Add Hosted Model"
            // Otherwise => "Edit Hosted Model"
            NavigationStack {
                AddHostedModelView(modelToEdit: model) { updatedModel in
                    saveHostedModel(updatedModel)
                }
                .environmentObject(appManager)
            }
        }
    }

    // MARK: - Save the updated or newly added model
    private func saveHostedModel(_ updatedModel: HostedModel) {
        // Try to find the old record by id
        if let index = appManager.hostedModels.firstIndex(where: { $0.id == updatedModel.id }) {
            // Overwrite in place
            appManager.hostedModels[index] = updatedModel
        } else {
            // Add a new model
            appManager.addHostedModel(updatedModel)
        }

        // Dismiss the sheet
        hostedModelToEdit = nil
    }

    // MARK: - Switch model
    private func switchModel(_ modelSelection: ModelSelection) async {
        appManager.currentModel = modelSelection
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred()
        await llm.switchModel(modelSelection)
    }

    // MARK: - Checking the current model
    private func isCurrentModelLocal(_ modelName: String) -> Bool {
        if case .local(let currentModelName) = appManager.currentModel {
            return currentModelName == modelName
        }
        return false
    }

    private func isCurrentModelHosted(_ hostedModel: HostedModel) -> Bool {
        if case .hosted(let currentHostedModel) = appManager.currentModel {
            return currentHostedModel.id == hostedModel.id
        }
        return false
    }

    // MARK: - Deletions
    private func deleteLocalModels(at offsets: IndexSet) {
        for index in offsets {
            let modelName = appManager.installedModels[index]
            if isCurrentModelLocal(modelName) {
                appManager.currentModel = nil
            }
        }
        appManager.installedModels.remove(atOffsets: offsets)
    }

    private func deleteHostedModel(_ hostedModel: HostedModel) {
        if let index = appManager.hostedModels.firstIndex(where: { $0.id == hostedModel.id }) {
            if isCurrentModelHosted(hostedModel) {
                appManager.currentModel = nil
            }
            appManager.hostedModels.remove(at: index)
        }
    }
}
