//
//  ContentView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/4/24.
//

import SwiftData
import SwiftUI
import PhotosUI

struct ContentView: View {
    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    @EnvironmentObject var appManager: AppManager
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var llm: LLMEvaluator
    @State var showOnboarding = false
    @State var showSettings = false
    @State var showChats = false
    @State var prompt = ""
    @FocusState var isPromptFocused: Bool
    @State var currentThread: Thread?
    @Namespace var bottomID

    @State private var counter: Int = 0
    @State private var origin: CGPoint = .zero

    // State variables for image attachment
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedUIImage: UIImage? = nil

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                content(geometry: geometry)
                    .task {
                        isPromptFocused = true
                        if let currentModel = appManager.currentModel {
                            try? await llm.load(modelSelection: currentModel)
                        } else {
                            // No model selected
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if !showChats && gesture.startLocation.x < 20 && gesture.translation.width > 100 {
                                    playHaptic()
                                    showChats = true
                                }
                            }
                    )
                    .sheet(isPresented: $showChats) {
                        ChatsView(currentThread: $currentThread, isPromptFocused: $isPromptFocused)
                            .environmentObject(appManager)
                            .presentationDragIndicator(.hidden)
                            .if(idiom == .phone) { view in
                                view.presentationDetents([.medium, .large])
                            }
                    }
                    .sheet(isPresented: $showSettings) {
                        SettingsView(currentThread: $currentThread)
                            .environmentObject(appManager)
                            .environment(llm)
                            .presentationDragIndicator(.hidden)
                            .if(idiom == .phone) { view in
                                view.presentationDetents([.medium])
                            }
                    }
                    .sheet(isPresented: $showOnboarding, onDismiss: dismissOnboarding) {
                        OnboardingView(showOnboarding: $showOnboarding)
                            .environment(llm)
                            .interactiveDismissDisabled(false)
                    }
                    .tint(appManager.appTintColor.getColor())
                    .fontDesign(appManager.appFontDesign.getFontDesign())
                    .environment(\.dynamicTypeSize, appManager.appFontSize.getFontSize())
                    .fontWidth(appManager.appFontWidth.getFontWidth())
            }
        }
    }

    @ViewBuilder
    private func content(geometry: GeometryProxy) -> some View {
        ZStack {
            animatedBackground
            mainContent(geometry: geometry)
        }
        .navigationTitle(chatTitle)
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    playHaptic()
                    showChats.toggle()
                }) {
                    Image(systemName: "list.bullet")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    playHaptic()
                    createNewChat()
                }) {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    playHaptic()
                    showSettings.toggle()
                }) {
                    Image(systemName: "gear")
                }
            }
        }
    }

    @ViewBuilder
    private var animatedBackground: some View {
        VStack(spacing: 0) {
            Rectangle()
                .frame(height: 50)
                .foregroundStyle(.black)
        }
        .background(.black)
        .overlay {
            Image("Grain")
                .scaleEffect(0.5)
                .ignoresSafeArea()
                .blendMode(.overlay)
                .opacity(0.6)
        }
        .keyframeAnimator(
            initialValue: 0,
            trigger: counter
        ) { view, elapsedTime in
            let posX = Float(origin.x)
            let posY = Float(origin.y)
            let time = Float(elapsedTime)

            let rippleShader = ShaderLibrary.Ripple(
                .float2(posX, posY),
                .float(time),
                .float(12),
                .float(15),
                .float(8),
                .float(1200)
            )

            let enabled = (0 < elapsedTime && elapsedTime < 3)

            view.visualEffect { view, _ in
                view.layerEffect(
                    rippleShader,
                    maxSampleOffset: CGSize(width: 12, height: 12),
                    isEnabled: enabled
                )
            }
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(3, duration: 3)
        }
    }

    @ViewBuilder
    private func mainContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            if let currentThread = currentThread {
                chatScrollView(currentThread: currentThread)
            } else {
                Spacer()
                Image(systemName: appManager.getMoonPhaseIcon())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.quaternary)
                Spacer()
            }

            inputBar(geometry: geometry)
        }
    }

    @ViewBuilder
    private func chatScrollView(currentThread: Thread) -> some View {
        ScrollViewReader { scrollView in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(currentThread.sortedMessages) { message in
                        messageView(message: message)
                            .padding()
                    }

                    if llm.running && !llm.output.isEmpty {
                        HStack {
                            Text(try! AttributedString(markdown: llm.output.trimmingCharacters(in: .whitespacesAndNewlines) + " ◐",
                                                       options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                                .textSelection(.enabled)
                                .multilineTextAlignment(.leading)
                                .padding(.trailing, 48)
                            Spacer()
                        }
                        .padding()
                    }
                }

                Rectangle()
                    .fill(.clear)
                    .frame(height: 1)
                    .id(bottomID)
            }
            .onChange(of: llm.output) { _, _ in
                scrollView.scrollTo(bottomID)
            }
        }
        .defaultScrollAnchor(.bottom)
        #if !os(visionOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    @ViewBuilder
    private func messageView(message: Message) -> some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(
                    try! AttributedString(
                        markdown: message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    )
                )
                .textSelection(.enabled)
                .if(message.role == .user) { view in
                    view
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .mask(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1.5)
                        }
                }
                if message.content == "<image attached>", let uiImage = selectedUIImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(message.role == .user ? .leading : .trailing, 48)

            if message.role == .assistant {
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func inputBar(geometry: GeometryProxy) -> some View {
        HStack {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Image(systemName: "paperclip")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16)
                    .tint(.primary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .foregroundStyle(.ultraThinMaterial)
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.1), lineWidth: 1.5)
                            }
                    )
            }
            .onChange(of: selectedPhotoItem) { newItem in
                handleSelectedPhotoItem(newItem)
            }

            HStack(spacing: 0) {
                TextField("message", text: $prompt)
                    .focused($isPromptFocused)
                    .textFieldStyle(.plain)
                    .padding(.horizontal)
                    .if(idiom == .pad || idiom == .mac) { view in
                        view
                            .onSubmit {
                                generate()
                            }
                            .submitLabel(.send)
                    }

                Button {
                    origin = CGPoint(x: geometry.size.width, y: geometry.size.height)
                    counter += 1
                    generate()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .offset(x: 2.5)
                }
                .disabled(llm.running || prompt.isEmpty)
                .padding(.trailing)
            }
            .frame(height: 48)
            .background(
                Capsule()
                    .foregroundStyle(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1.5)
                    }
            )
        }
        .padding()
    }

    private func handleSelectedPhotoItem(_ newItem: PhotosPickerItem?) {
        if let newItem {
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedUIImage = uiImage
                    if currentThread == nil {
                        let newThread = Thread()
                        currentThread = newThread
                        modelContext.insert(newThread)
                        try? modelContext.save()
                    }

                    if let currentThread = currentThread {
                        sendMessage(Message(role: .user, content: "<image attached>", thread: currentThread))
                    }
                }
            }
        }
    }

    var chatTitle: String {
        let modelName = appManager.currentModelNameDisplay
        return modelName.isEmpty ? "fullmoon" : modelName
    }

    /// Updated createNewChat function
    private func createNewChat() {
        // Instead of creating and saving a new empty Thread right away, just reset the current thread.
        currentThread = nil
        isPromptFocused = true
    }

    private func generate() {
        if !prompt.isEmpty {
            if currentThread == nil {
                let newThread = Thread()
                currentThread = newThread
                modelContext.insert(newThread)
                try? modelContext.save()
            }

            if let currentThread = currentThread {
                let messageContent = prompt
                prompt = ""
                playHaptic()
                sendMessage(Message(role: .user, content: messageContent, thread: currentThread))
                isPromptFocused = true
                Task {
                    if let currentModel = appManager.currentModel {
                        let output = await llm.generate(modelSelection: currentModel, thread: currentThread, systemPrompt: appManager.systemPrompt)
                        sendMessage(Message(role: .assistant, content: output, thread: currentThread))
                    }
                }
            }
        }
    }

    private func sendMessage(_ message: Message) {
        playHaptic()
        modelContext.insert(message)
        try? modelContext.save()
    }

    func playHaptic() {
        #if !os(visionOS)
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred()
        #endif
    }

    func dismissOnboarding() {
        isPromptFocused = true
    }
}

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    ContentView()
}
