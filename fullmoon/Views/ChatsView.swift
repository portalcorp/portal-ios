//
//  ChatsView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/5/24.
//

import SwiftUI
import SwiftData

struct ChatsView: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(\.dismiss) var dismiss
    @Binding var currentThread: Thread?
    @FocusState.Binding var isPromptFocused: Bool
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Thread.timestamp, order: .reverse) var threads: [Thread]
    @State var search = ""
    @State var showSettings = false
    @EnvironmentObject var llm: LLMEvaluator
    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredThreads.isEmpty {
                    ContentUnavailableView {
                        Label(threads.isEmpty ? "no chats yet" : "no results", systemImage: "message")
                    }
                } else {
                    List {
                        Section {
                            ForEach(filteredThreads) { thread in
                                Button {
                                    setCurrentThread(thread)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Group {
                                            if let firstMessage = thread.sortedMessages.first {
                                                Text(firstMessage.content)
                                                    .lineLimit(1)
                                            } else {
                                                Text("untitled")
                                            }
                                        }
                                        .foregroundStyle(.primary)
                                        .font(.headline)
                                        
                                        Text("\(thread.timestamp.formatted())")
                                            .foregroundStyle(.secondary)
                                            .font(.subheadline)
                                    }
                                }
                                .tint(.primary)
                            }
                            .onDelete(perform: deleteThreads)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "search")
            .navigationTitle("chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .tint(appManager.appTintColor.getColor())
        .environment(\.dynamicTypeSize, appManager.appFontSize.getFontSize())
        .sheet(isPresented: $showSettings) {
            SettingsView(currentThread: $currentThread)
                .environmentObject(appManager)
                .environmentObject(llm)
                .presentationDragIndicator(.hidden)
                .if(idiom == .phone) { view in
                    view.presentationDetents([.medium])
                }
        }
    }
    
    var filteredThreads: [Thread] {
        threads.filter { thread in
            search.isEmpty || thread.messages.contains { message in
                message.content.localizedCaseInsensitiveContains(search)
            }
        }
    }
    
    private func deleteThreads(at offsets: IndexSet) {
        for offset in offsets {
            let thread = threads[offset]
            
            // If user is currently on this thread, clear it out
            if currentThread?.id == thread.id {
                setCurrentThread(nil)
            }
            
            modelContext.delete(thread)
        }
    }

    // removed @AppStorage("lastThreadId") usage for simplicity
    
    private func setCurrentThread(_ thread: Thread?) {
        currentThread = thread
        // No need to save any "lastThreadId". We simply pick the thread in memory.
        isPromptFocused = true
        dismiss()
    }
}

#Preview {
    @FocusState var isPromptFocused: Bool
    ChatsView(currentThread: .constant(nil), isPromptFocused: $isPromptFocused)
}
