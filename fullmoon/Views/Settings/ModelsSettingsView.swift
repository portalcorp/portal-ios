//
//  ModelsSettingsView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/5/24.
//

import SwiftUI
import MLXLLM

struct ModelsSettingsView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var llm: LLMEvaluator
    @State private var showOnboardingInstallModelView = false
    @State private var showAddHostedModelView = false
    
    // New state for editing
    @State private var modelToEdit: HostedModel? = nil

    var body: some View {
        List {
            Button {
                showOnboardingInstallModelView.toggle()
            } label: {
                Label("install a model", systemImage: "arrow.down.circle.dotted")
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
                                .tint(.primary)
                        } icon: {
                            Image(systemName: isCurrentModelLocal(modelName) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
                .onDelete(perform: deleteLocalModels)
            }

            Section(header: Text("Hosted Models")) {
                ForEach(appManager.hostedModels, id: \.self) { hostedModel in
                    Button {
                        Task {
                            await switchModel(.hosted(model: hostedModel))
                        }
                    } label: {
                        Label {
                            Text(hostedModel.name)
                                .tint(.primary)
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
                            modelToEdit = hostedModel
                            showAddHostedModelView = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }

                Button {
                    modelToEdit = nil
                    showAddHostedModelView.toggle()
                } label: {
                    Label("Add Hosted Model", systemImage: "plus")
                }
            }
        }
        .navigationTitle("models")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddHostedModelView) {
            NavigationStack {
                AddHostedModelView(modelToEdit: modelToEdit) { updatedModel in
                    if let modelToEdit = modelToEdit,
                       let index = appManager.hostedModels.firstIndex(of: modelToEdit) {
                        // Editing existing model
                        appManager.hostedModels[index] = updatedModel
                    } else {
                        // Adding a new model
                        appManager.addHostedModel(updatedModel)
                    }
                    modelToEdit = nil
                }
                .environmentObject(appManager)
            }
            .frame(minHeight: 400)
        }
        .sheet(isPresented: $showOnboardingInstallModelView) {
            NavigationStack {
                OnboardingInstallModelView(showOnboarding: $showOnboardingInstallModelView)
                    .environmentObject(appManager)
                    .environmentObject(llm)
            }
        }
    }

    private func switchModel(_ modelSelection: ModelSelection) async {
        appManager.currentModel = modelSelection
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred()
        await llm.switchModel(modelSelection)
    }

    private func isCurrentModelLocal(_ modelName: String) -> Bool {
        if case .local(let currentModelName) = appManager.currentModel {
            return currentModelName == modelName
        }
        return false
    }

    private func isCurrentModelHosted(_ hostedModel: HostedModel) -> Bool {
        if case .hosted(let currentHostedModel) = appManager.currentModel {
            return currentHostedModel == hostedModel
        }
        return false
    }

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
        if let index = appManager.hostedModels.firstIndex(of: hostedModel) {
            if isCurrentModelHosted(hostedModel) {
                appManager.currentModel = nil
            }
            appManager.hostedModels.remove(at: index)
        }
    }
}
