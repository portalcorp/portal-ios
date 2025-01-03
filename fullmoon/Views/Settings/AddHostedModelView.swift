import SwiftUI

struct AddHostedModelView: View {
    @Environment(\.dismiss) var dismiss
    @State private var modelName: String
    @State private var endpoint: String

    var modelToEdit: HostedModel
    var onSave: (HostedModel) -> Void

    init(modelToEdit: HostedModel, onSave: @escaping (HostedModel) -> Void) {
        self.modelToEdit = modelToEdit
        self.onSave = onSave
        _modelName = State(initialValue: modelToEdit.name)
        _endpoint = State(initialValue: modelToEdit.endpoint)
    }

    var body: some View {
        Form {
            Section(header: Text("Model Information")) {
                TextField("Model Name", text: $modelName)
                    .autocapitalization(.none)
                    .autocorrectionDisabled(true)

                TextField("Endpoint URL", text: $endpoint)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled(true)
            }
        }
        .navigationTitle(modelToEdit.name.isEmpty ? "Add Hosted Model" : "Edit Hosted Model")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(modelToEdit.name.isEmpty ? "Add" : "Save") {
                    let updated = HostedModel(
                        id: modelToEdit.id,  // keep the same id
                        name: modelName,
                        endpoint: endpoint
                    )
                    onSave(updated)
                    dismiss()
                }
                .disabled(modelName.isEmpty || endpoint.isEmpty)
            }
        }
    }
}
