//
//  Data.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/5/24.
//

import SwiftUI
import SwiftData

struct HostedModel: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var endpoint: String

    init(id: UUID = UUID(), name: String, endpoint: String) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
    }
}

/// Per-thread model selection
enum ModelSelection: Codable {
    case local(name: String)
    case hosted(model: HostedModel)
}

/// Convert ModelSelection to a string for `.id(...)`
extension ModelSelection {
    var idString: String {
        switch self {
        case .local(let name):
            return "local:\(name)"
        case .hosted(let hosted):
            return "hosted:\(hosted.id.uuidString)"
        }
    }
}

class AppManager: ObservableObject {
    @AppStorage("systemPrompt") var systemPrompt = "you are a helpful assistant"
    @AppStorage("appTintColor") var appTintColor: AppTintColor = .monochrome
    @AppStorage("appFontDesign") var appFontDesign: AppFontDesign = .standard
    @AppStorage("appFontSize") var appFontSize: AppFontSize = .medium
    @AppStorage("appFontWidth") var appFontWidth: AppFontWidth = .standard
    @AppStorage("shouldPlayHaptics") var shouldPlayHaptics = true

    /// The "global" or "default" model selection (for new chats, etc.)
    @Published var currentModel: ModelSelection? {
        didSet {
            saveCurrentModelToUserDefaults()
        }
    }

    private let installedModelsKey = "installedModels"
    private let hostedModelsKey = "hostedModels"
    private let currentModelKey = "currentModel"

    @Published var installedModels: [String] = [] {
        didSet { saveInstalledModelsToUserDefaults() }
    }
    @Published var hostedModels: [HostedModel] = [] {
        didSet { saveHostedModelsToUserDefaults() }
    }

    init() {
        loadInstalledModelsFromUserDefaults()
        loadHostedModelsFromUserDefaults()
        loadCurrentModelFromUserDefaults()
    }

    var currentModelNameDisplay: String {
        guard let currentModel = currentModel else { return "" }
        switch currentModel {
        case .local(let name):
            return modelDisplayName(name)
        case .hosted(let hosted):
            return hosted.name
        }
    }

    // MARK: - Model Storage

    private func saveInstalledModelsToUserDefaults() {
        if let jsonData = try? JSONEncoder().encode(installedModels) {
            UserDefaults.standard.set(jsonData, forKey: installedModelsKey)
        }
    }
    private func loadInstalledModelsFromUserDefaults() {
        if
            let jsonData = UserDefaults.standard.data(forKey: installedModelsKey),
            let decoded = try? JSONDecoder().decode([String].self, from: jsonData) {
            installedModels = decoded
        } else {
            installedModels = []
        }
    }

    private func saveHostedModelsToUserDefaults() {
        if let jsonData = try? JSONEncoder().encode(hostedModels) {
            UserDefaults.standard.set(jsonData, forKey: hostedModelsKey)
        }
    }
    private func loadHostedModelsFromUserDefaults() {
        if
            let jsonData = UserDefaults.standard.data(forKey: hostedModelsKey),
            let decoded = try? JSONDecoder().decode([HostedModel].self, from: jsonData) {
            hostedModels = decoded
        } else {
            hostedModels = []
        }
    }

    private func saveCurrentModelToUserDefaults() {
        if let data = try? JSONEncoder().encode(currentModel) {
            UserDefaults.standard.set(data, forKey: currentModelKey)
        }
    }
    private func loadCurrentModelFromUserDefaults() {
        if
            let data = UserDefaults.standard.data(forKey: currentModelKey),
            let model = try? JSONDecoder().decode(ModelSelection.self, from: data) {
            currentModel = model
        } else {
            currentModel = nil
        }
    }

    // MARK: - Helpers

    func addInstalledModel(_ model: String) {
        if !installedModels.contains(model) {
            installedModels.append(model)
        }
    }
    func addHostedModel(_ model: HostedModel) {
        if !hostedModels.contains(model) {
            hostedModels.append(model)
        }
    }

    func modelDisplayName(_ name: String) -> String {
        // For example, trim "mlx-community/"
        name.replacingOccurrences(of: "mlx-community/", with: "").lowercased()
    }

    func getMoonPhaseIcon() -> String {
        let currentDate = Date()
        let baseDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 6))!
        let daysSinceBaseDate = Calendar.current.dateComponents([.day], from: baseDate, to: currentDate).day!
        let moonCycleLength = 29.53
        let daysIntoCycle = Double(daysSinceBaseDate).truncatingRemainder(dividingBy: moonCycleLength)

        switch daysIntoCycle {
        case 0..<1.8457:
            return "moonphase.new.moon"
        case 1.8457..<5.536:
            return "moonphase.waxing.crescent"
        case 5.536..<9.228:
            return "moonphase.first.quarter"
        case 9.228..<12.919:
            return "moonphase.waxing.gibbous"
        case 12.919..<16.610:
            return "moonphase.full.moon"
        case 16.610..<20.302:
            return "moonphase.waning.gibbous"
        case 20.302..<23.993:
            return "moonphase.last.quarter"
        case 23.993..<27.684:
            return "moonphase.waning.crescent"
        default:
            return "moonphase.new.moon"
        }
    }
}

// MARK: - Roles, Messages, Threads

enum Role: String, Codable {
    case assistant, user, system
}

@Model
class Message {
    @Attribute(.unique) var id: UUID
    var role: Role
    var content: String
    var timestamp: Date

    @Relationship(inverse: \Thread.messages) var thread: Thread?

    init(role: Role, content: String, thread: Thread? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.thread = thread
    }
}

@Model
class Thread {
    @Attribute(.unique) var id: UUID
    var title: String?
    var timestamp: Date

    @Relationship var messages: [Message] = []

    // Store the model selection as JSON in a string
    var storedModelSelection: String?

    // Computed property to read/write the model selection
    var modelSelection: ModelSelection? {
        get {
            guard
                let json = storedModelSelection,
                let data = json.data(using: .utf8),
                let sel = try? JSONDecoder().decode(ModelSelection.self, from: data)
            else {
                return nil
            }
            return sel
        }
        set {
            guard let newValue = newValue else {
                storedModelSelection = nil
                return
            }
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                storedModelSelection = json
            } else {
                storedModelSelection = nil
            }
        }
    }

    var sortedMessages: [Message] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }

    init() {
        self.id = UUID()
        self.timestamp = Date()
    }
}

// MARK: - Appearance Settings

enum AppTintColor: String, CaseIterable {
    case monochrome, blue, brown, gray, green, indigo, mint, orange, pink, purple, red, teal, yellow
    func getColor() -> Color {
        switch self {
        case .monochrome:
            return .primary
        case .blue:
            return .blue
        case .red:
            return .red
        case .green:
            return .green
        case .yellow:
            return .yellow
        case .brown:
            return .brown
        case .gray:
            return .gray
        case .indigo:
            return .indigo
        case .mint:
            return .mint
        case .orange:
            return .orange
        case .pink:
            return .pink
        case .purple:
            return .purple
        case .teal:
            return .teal
        }
    }
}

enum AppFontDesign: String, CaseIterable {
    case standard, monospaced, rounded, serif
    func getFontDesign() -> Font.Design {
        switch self {
        case .standard: return .default
        case .monospaced: return .monospaced
        case .rounded: return .rounded
        case .serif: return .serif
        }
    }
}

enum AppFontWidth: String, CaseIterable {
    case compressed, condensed, expanded, standard
    func getFontWidth() -> Font.Width {
        switch self {
        case .compressed: return .compressed
        case .condensed: return .condensed
        case .expanded: return .expanded
        case .standard: return .standard
        }
    }
}

enum AppFontSize: String, CaseIterable {
    case xsmall, small, medium, large, xlarge
    func getFontSize() -> DynamicTypeSize {
        switch self {
        case .xsmall: return .xSmall
        case .small:  return .small
        case .medium: return .medium
        case .large:  return .large
        case .xlarge: return .xLarge
        }
    }
}
