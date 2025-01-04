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

    // SwiftData references
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Thread.timestamp, order: .reverse) var threads: [Thread]

    // Observables
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var llm: LLMEvaluator

    // Some local state
    @State var showOnboarding = false
    @State var showSettings = false
    @State var showChats = false
    @State var prompt = ""
    @FocusState var isPromptFocused: Bool
    
    // For model selector
    @State var showModelSelector = false

    // The current open thread
    @State var currentThread: Thread?

    @Namespace var bottomID

    @State private var counter: Int = 0
    @State private var origin: CGPoint = .zero

    // For image attachment
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedUIImage: UIImage? = nil

    // We no longer auto-restore last thread on launch
    // (Removed @AppStorage("lastThreadId") for a clean empty chat on first open)

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                content(geometry: geometry)
                    .id(currentThread?.modelSelection?.idString ?? "none")
                    .task {
                        // On first load, do NOT auto-load a thread.
                        // Instead, show an empty chat. No new Thread is created here.
                        currentThread = nil
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                // Swipe to reveal Chats
                                if !showChats && gesture.startLocation.x < 20 && gesture.translation.width > 100 {
                                    playHaptic()
                                    showChats = true
                                }
                            }
                    )
                    // Chats sheet
                    .sheet(isPresented: $showChats) {
                        ChatsView(currentThread: $currentThread, isPromptFocused: $isPromptFocused)
                            .environmentObject(appManager)
                            .presentationDragIndicator(.hidden)
                            .if(idiom == .phone) { view in
                                view.presentationDetents([.medium, .large])
                            }
                    }
                    // Settings sheet
                    .sheet(isPresented: $showSettings) {
                        SettingsView(currentThread: $currentThread)
                            .environmentObject(appManager)
                            .environmentObject(llm)
                            .presentationDragIndicator(.hidden)
                            .if(idiom == .phone) { view in
                                view.presentationDetents([.medium])
                            }
                    }
                    // Model selector sheet
                    .sheet(isPresented: $showModelSelector) {
                        ModelsSettingsView(currentThread: $currentThread)
                            .environmentObject(appManager)
                            .environmentObject(llm)
                            .presentationDetents([.medium, .large])
                    }
                    // Onboarding sheet
                    .sheet(isPresented: $showOnboarding, onDismiss: dismissOnboarding) {
                        OnboardingView(showOnboarding: $showOnboarding)
                            .environment(llm)
                            .interactiveDismissDisabled(false)
                    }
                    // Keep your global .tint() to style links, toggles, etc.
                    .tint(appManager.appTintColor.getColor())
                    .fontDesign(appManager.appFontDesign.getFontDesign())
                    .environment(\.dynamicTypeSize, appManager.appFontSize.getFontSize())
                    .fontWidth(appManager.appFontWidth.getFontWidth())
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.automatic)
            .toolbar {
                // Chat title button with a translucent background
                ToolbarItem(placement: .principal) {
                    Button(action: { showModelSelector.toggle() }) {
                        Text(chatTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Color(uiColor: .secondarySystemFill).opacity(0.4)
                            )
                            .cornerRadius(8)
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        playHaptic()
                        showChats.toggle()
                    } label: {
                        Image(systemName: "list.bullet")
                            .foregroundColor(appManager.appTintColor.getColor())
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        playHaptic()
                        createNewChat()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(appManager.appTintColor.getColor())
                    }
                }
            }
        }
    }

    // MARK: - UI Layout

    @ViewBuilder
    private func content(geometry: GeometryProxy) -> some View {
        ZStack {
            animatedBackground
            mainContent(geometry: geometry)
        }
    }

    @ViewBuilder
    private var animatedBackground: some View {
        VStack(spacing: 0) {
            MeshGradientView()
                .ignoresSafeArea()
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
                // Empty chat placeholder
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

                    // If the model is running and partial output exists
                    if llm.running && !llm.output.isEmpty {
                        HStack {
                            Text(
                                try! AttributedString(
                                    markdown: llm.output.trimmingCharacters(in: .whitespacesAndNewlines) + " ◐",
                                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                                )
                            )
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
                if message.role == .assistant, message.content.hasPrefix("Error:") {
                    Text(
                        try! AttributedString(
                            markdown: message.content,
                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                        )
                    )
                    .bold()
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.2))
                    .mask(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
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
                }

                // If it was an image
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

                // If model is running, show spinner
                if llm.running {
                    ProgressView()
                        .padding(.trailing)
                } else {
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
                            .foregroundColor(appManager.appTintColor.getColor())
                    }
                    .disabled(llm.running || prompt.isEmpty)
                    .padding(.trailing)
                }
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

    // MARK: - Photo handling
    private func handleSelectedPhotoItem(_ newItem: PhotosPickerItem?) {
        if let newItem {
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedUIImage = uiImage
                    // Only create a thread if the user is actually sending something:
                    if currentThread == nil {
                        let newThread = Thread()
                        newThread.modelSelection = appManager.currentModel
                        modelContext.insert(newThread)
                        try? modelContext.save()
                        currentThread = newThread
                    }
                    // Insert a message for the image
                    if let currentThread = currentThread {
                        sendMessage(Message(role: .user, content: "<image attached>", thread: currentThread))
                    }
                }
            }
        }
    }

    // MARK: - Title, new chat, generating text

    private var chatTitle: String {
        guard let sel = currentThread?.modelSelection else {
            // If no thread, fallback to global or "fullmoon"
            if let fallback = appManager.currentModel {
                switch fallback {
                case .local(let name): return appManager.modelDisplayName(name)
                case .hosted(let hosted): return hosted.name
                }
            }
            return "fullmoon"
        }
        switch sel {
        case .local(let name):
            return appManager.modelDisplayName(name)
        case .hosted(let hosted):
            return hosted.name
        }
    }

    private func createNewChat() {
        currentThread = nil
        isPromptFocused = true
    }

    private func generate() {
        guard !prompt.isEmpty else { return }

        // Only create/save a Thread once the user actually sends a message
        if currentThread == nil {
            let newThread = Thread()
            newThread.modelSelection = appManager.currentModel
            modelContext.insert(newThread)
            try? modelContext.save()
            currentThread = newThread
        }

        if let currentThread = currentThread, let modelSelection = currentThread.modelSelection {
            let userMessage = Message(role: .user, content: prompt, thread: currentThread)
            prompt = ""
            playHaptic()
            sendMessage(userMessage)

            Task {
                let output = await llm.generate(
                    modelSelection: modelSelection,
                    thread: currentThread,
                    systemPrompt: appManager.systemPrompt
                )
                sendMessage(Message(role: .assistant, content: output, thread: currentThread))
            }
        }
    }

    private func sendMessage(_ message: Message) {
        playHaptic()
        modelContext.insert(message)
        try? modelContext.save()
    }

    // MARK: - Misc

    func playHaptic() {
        #if !os(visionOS)
        if appManager.shouldPlayHaptics {
            let impact = UIImpactFeedbackGenerator(style: .soft)
            impact.impactOccurred()
        }
        #endif
    }

    func dismissOnboarding() {
        isPromptFocused = true
    }
}

extension View {
    @ViewBuilder func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppManager())
        .environmentObject(LLMEvaluator())
}
