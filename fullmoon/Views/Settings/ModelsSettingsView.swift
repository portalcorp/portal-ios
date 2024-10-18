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
    @State var showOnboardingInstallModelView = false
    @State private var showAddHostedModelView = false

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
                }
                .onDelete(perform: deleteHostedModels)

                Button {
                    showAddHostedModelView.toggle()
                } label: {
                    Label("Add Hosted Model", systemImage: "plus")
                }
            }
        }
        .navigationTitle("models")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddHostedModelView) {
            AddHostedModelView()
                .environmentObject(appManager)
                .frame(minHeight: 400) // Set a minimum height for the sheet
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

    private func deleteHostedModels(at offsets: IndexSet) {
        appManager.hostedModels.remove(atOffsets: offsets)
    }
}
