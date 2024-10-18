import SwiftUI

struct AddHostedModelView: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(\.dismiss) var dismiss
    @State private var modelName: String = ""
    @State private var endpoint: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Model Information")) {
                    TextField("Model Name", text: $modelName)
                    TextField("Endpoint URL", text: $endpoint)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled(true)
                }
            }
            .navigationTitle("Add Hosted Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addHostedModel()
                    }
                    .disabled(modelName.isEmpty || endpoint.isEmpty)
                }
            }
        }
        .frame(minHeight: 400)
    }

    private func addHostedModel() {
        let hostedModel = HostedModel(name: modelName, endpoint: endpoint)
        appManager.addHostedModel(hostedModel)
        dismiss()
    }
}
