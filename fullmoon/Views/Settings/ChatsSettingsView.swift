import SwiftUI

struct ChatsSettingsView: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(\.modelContext) var modelContext
    @State var systemPrompt = ""
    @State var deleteAllChats = false
    @Binding var currentThread: Thread?

    var body: some View {
        List {
            Section(header: Text("System Prompt")) {
                TextEditor(text: $appManager.systemPrompt)
            }
            // Add this section if needed
            Section(header: Text("Preferences")) {
                Toggle("Enable Haptics", isOn: $appManager.shouldPlayHaptics)
            }
            Section {
                Button {
                    deleteAllChats.toggle()
                } label: {
                    Label("Delete All Chats", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .alert("Are you sure?", isPresented: $deleteAllChats) {
                    Button("Cancel", role: .cancel) {
                        deleteAllChats = false
                    }
                    Button("Delete", role: .destructive) {
                        deleteChats()
                    }
                }
            }
        }
        .navigationTitle("Chats")
        .navigationBarTitleDisplayMode(.inline)
    }

    func deleteChats() {
        do {
            currentThread = nil
            try modelContext.delete(model: Thread.self)
            try modelContext.delete(model: Message.self)
        } catch {
            print("Failed to delete.")
        }
    }
}

#Preview {
    ChatsSettingsView(currentThread: .constant(nil))
}
