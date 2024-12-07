import SwiftUI
import MLXLLM

struct OnboardingInstallModelView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var llm: LLMEvaluator
    @Binding var showOnboarding: Bool

    @State var selectedModel: ModelConfiguration? = nil
    @State private var navigateToInstallProgress = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.dotted")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .foregroundStyle(.primary, .tertiary)

                    VStack(spacing: 4) {
                        Text("install a model")
                            .font(.title)
                            .fontWeight(.semibold)
                        Text("select from models that are optimized for apple silicon")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            Section(header: Text("Available Models")) {
                ForEach(ModelConfiguration.availableModels, id: \.name) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        HStack {
                            Image(systemName: modelIconName(for: model))
                            Text(appManager.modelDisplayName(model.name))
                                .tint(.primary)
                            Spacer()
                            if isInstalled(model) {
                                Text("installed")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Install Model")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    showOnboarding = false
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(
                    destination: OnboardingDownloadingModelProgressView(
                        showOnboarding: $showOnboarding,
                        selectedModel: .constant(selectedModel ?? ModelConfiguration.defaultModel)
                    )
                    .environmentObject(appManager)
                    .environmentObject(llm),
                    isActive: $navigateToInstallProgress
                ) {
                    Text("install")
                        .font(.headline)
                }
                .disabled(!canInstallSelectedModel)
                .onChange(of: selectedModel) { _ in
                    // If user picks a model, pressing "install" will navigate
                    // but only if model not installed
                }
                .onTapGesture {
                    if let selectedModel = selectedModel, !isInstalled(selectedModel) {
                        navigateToInstallProgress = true
                    }
                }
            }
        }
    }

    private var canInstallSelectedModel: Bool {
        guard let selectedModel = selectedModel else { return false }
        return !isInstalled(selectedModel)
    }

    private func isInstalled(_ model: ModelConfiguration) -> Bool {
        return appManager.installedModels.contains(model.name)
    }

    private func modelIconName(for model: ModelConfiguration) -> String {
        if selectedModel?.name == model.name {
            return "checkmark.circle.fill"
        } else {
            return "circle"
        }
    }
}
