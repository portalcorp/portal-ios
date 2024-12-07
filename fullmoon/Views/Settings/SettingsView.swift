//
//  SettingsView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/4/24.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var llm: LLMEvaluator
    @Binding var currentThread: Thread?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: AppearanceSettingsView()) {
                        Label("appearance", systemImage: "paintpalette")
                    }
                    
                    NavigationLink(destination: ChatsSettingsView(currentThread: $currentThread)) {
                        Label("chats", systemImage: "message")
                    }
                    
                    NavigationLink(destination: ModelsSettingsView()) {
                        Label("models", systemImage: "arrow.down.circle")
                            .badge(truncatedModelName(appManager.currentModelNameDisplay))
                    }

                }
                
                Section {
                    NavigationLink(destination: CreditsView()) {
                        Text("credits")
                    }
                }
                
                Section {
                    HStack {
                        Spacer()
                        Image(systemName: appManager.getMoonPhaseIcon())
                            .foregroundStyle(.quaternary)
                        Spacer()
                    }
                    .padding(.vertical)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .tint(appManager.appTintColor.getColor())
        .environment(\.dynamicTypeSize, appManager.appFontSize.getFontSize())
    }
}

extension SettingsView {
    func truncatedModelName(_ name: String, maxLength: Int = 20) -> String {
        if name.count > maxLength {
            let endIndex = name.index(name.startIndex, offsetBy: maxLength)
            return String(name[..<endIndex]) + "…"
        } else {
            return name
        }
    }
}


#Preview {
    SettingsView(currentThread: .constant(nil))
}
