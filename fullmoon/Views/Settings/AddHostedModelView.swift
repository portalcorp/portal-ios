import SwiftUI

struct AddHostedModelView: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(\.dismiss) var dismiss
    @State private var modelName: String
    @State private var endpoint: String
    
    // Optional model to edit, if provided
    var modelToEdit: HostedModel?
    var onSave: (HostedModel) -> Void

    init(modelToEdit: HostedModel? = nil, onSave: @escaping (HostedModel) -> Void) {
        self.modelToEdit = modelToEdit
        self.onSave = onSave

        if let modelToEdit = modelToEdit {
            _modelName = State(initialValue: modelToEdit.name)
            _endpoint = State(initialValue: modelToEdit.endpoint)
        } else {
            _modelName = State(initialValue: "")
            _endpoint = State(initialValue: "")
        }
    }

    var body: some View {
        Form {
            Section(header: Text("Model Information")) {
                TextField("Model Name", text: $modelName)
                TextField("Endpoint URL", text: $endpoint)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled(true)
            }
        }
        .navigationTitle(modelToEdit == nil ? "Add Hosted Model" : "Edit Hosted Model")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(modelToEdit == nil ? "Add" : "Save") {
                    let hostedModel = HostedModel(name: modelName, endpoint: endpoint)
                    onSave(hostedModel)
                    dismiss()
                }
                .disabled(modelName.isEmpty || endpoint.isEmpty)
            }
        }
    }
}
