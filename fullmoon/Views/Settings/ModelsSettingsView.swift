//
//  ModelsSettingsView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/4/24.
//

import SwiftUI
import MLXLLM

struct ModelsSettingsView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var llm: LLMEvaluator
    @Environment(\.modelContext) var modelContext

    @Binding var currentThread: Thread?

    // So we can remember the last used thread after picking a model
    @AppStorage("lastThreadId") private var lastThreadId: String = ""

    @State private var showInstallLocalModelSheet = false
    @State private var hostedModelToEdit: HostedModel? = nil

    var body: some View {
        List {
            installModelSection
            installedModelsSection
            hostedModelsSection
        }
        .id(currentThread?.modelSelection?.idString ?? "none")
        .navigationTitle("models")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showInstallLocalModelSheet) {
            NavigationStack {
                InstallModelView()
                    .environmentObject(appManager)
                    .environmentObject(llm)
            }
        }
        .sheet(item: $hostedModelToEdit) { model in
            NavigationStack {
                AddHostedModelView(modelToEdit: model) { updatedModel in
                    saveHostedModel(updatedModel)
                }
                .environmentObject(appManager)
            }
        }
    }

    // MARK: - Sections

    private var installModelSection: some View {
        Section {
            Button {
                showInstallLocalModelSheet = true
            } label: {
                Label("Install a model", systemImage: "arrow.down.circle.dotted")
            }
        }
    }

    private var installedModelsSection: some View {
        Section(header: Text("Installed")) {
            let installed = appManager.installedModels
            ForEach(installed, id: \.self) { modelName in
                let isSelected = isCurrentModelLocal(modelName)
                Button {
                    Task {
                        await switchModel(.local(name: modelName))
                    }
                } label: {
                    Label {
                        Text(appManager.modelDisplayName(modelName))
                    } icon: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
            .onDelete(perform: deleteLocalModels)
        }
    }

    private var hostedModelsSection: some View {
        Section(header: Text("Hosted Models")) {
            let hostedModels = appManager.hostedModels
            ForEach(hostedModels, id: \.id) { hostedModel in
                let isSelected = isCurrentModelHosted(hostedModel)
                Button {
                    Task {
                        await switchModel(.hosted(model: hostedModel))
                    }
                } label: {
                    Label {
                        Text(hostedModel.name)
                    } icon: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        deleteHostedModel(hostedModel)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        hostedModelToEdit = hostedModel
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }

            Button {
                hostedModelToEdit = HostedModel(name: "", endpoint: "")
            } label: {
                Label("Add Hosted Model", systemImage: "plus")
            }
        }
    }

    // MARK: - Switch model
    private func switchModel(_ modelSelection: ModelSelection) async {
        if let thread = currentThread {
            thread.modelSelection = modelSelection
            try? modelContext.save()
            // Remember this thread as the last used, so next app launch uses it
            lastThreadId = thread.id.uuidString
        }
        // Also set the global manager's currentModel (optional)
        appManager.currentModel = modelSelection

        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred()

        await llm.switchModel(modelSelection)
    }

    // MARK: - Checking the current model
    private func isCurrentModelLocal(_ modelName: String) -> Bool {
        guard let sel = currentThread?.modelSelection else { return false }
        if case .local(let currentName) = sel {
            return currentName == modelName
        }
        return false
    }

    private func isCurrentModelHosted(_ hostedModel: HostedModel) -> Bool {
        guard let sel = currentThread?.modelSelection else { return false }
        if case .hosted(let currentHosted) = sel {
            return currentHosted.id == hostedModel.id
        }
        return false
    }

    // MARK: - Deletions
    private func deleteLocalModels(at offsets: IndexSet) {
        for index in offsets {
            let modelName = appManager.installedModels[index]
            if isCurrentModelLocal(modelName) {
                currentThread?.modelSelection = nil
                try? modelContext.save()
            }
        }
        appManager.installedModels.remove(atOffsets: offsets)
    }

    private func deleteHostedModel(_ hostedModel: HostedModel) {
        if let index = appManager.hostedModels.firstIndex(where: { $0.id == hostedModel.id }) {
            if isCurrentModelHosted(hostedModel) {
                currentThread?.modelSelection = nil
                try? modelContext.save()
            }
            appManager.hostedModels.remove(at: index)
        }
    }

    // MARK: - Hosted model saving
    private func saveHostedModel(_ updatedModel: HostedModel) {
        if let idx = appManager.hostedModels.firstIndex(where: { $0.id == updatedModel.id }) {
            appManager.hostedModels[idx] = updatedModel
        } else {
            appManager.addHostedModel(updatedModel)
        }
        hostedModelToEdit = nil
    }
}

#Preview {
    ModelsSettingsView(currentThread: .constant(nil))
        .environmentObject(AppManager())
        .environmentObject(LLMEvaluator())
}
