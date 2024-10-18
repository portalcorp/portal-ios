//
//  Data.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/5/24.
//

import SwiftUI
import SwiftData

struct HostedModel: Codable, Hashable {
    var name: String
    var endpoint: String
}

enum ModelSelection: Codable {
    case local(name: String)
    case hosted(model: HostedModel)
}

class AppManager: ObservableObject {
    @AppStorage("systemPrompt") var systemPrompt = "you are a helpful assistant"
    @AppStorage("appTintColor") var appTintColor: AppTintColor = .monochrome
    @AppStorage("appFontDesign") var appFontDesign: AppFontDesign = .standard
    @AppStorage("appFontSize") var appFontSize: AppFontSize = .medium
    @AppStorage("appFontWidth") var appFontWidth: AppFontWidth = .standard
    @AppStorage("shouldPlayHaptics") var shouldPlayHaptics = true

    @Published var currentModel: ModelSelection? {
        didSet {
            saveCurrentModelToUserDefaults()
        }
    }

    private let installedModelsKey = "installedModels"
    private let hostedModelsKey = "hostedModels"
    private let currentModelKey = "currentModel"

    @Published var installedModels: [String] = [] {
        didSet {
            saveInstalledModelsToUserDefaults()
        }
    }

    @Published var hostedModels: [HostedModel] = [] {
        didSet {
            saveHostedModelsToUserDefaults()
        }
    }

    init() {
        loadInstalledModelsFromUserDefaults()
        loadHostedModelsFromUserDefaults()
        loadCurrentModelFromUserDefaults()
    }

    // Add this computed property to get the display name of the current model
    var currentModelNameDisplay: String {
        if let currentModel = currentModel {
            switch currentModel {
            case .local(let name):
                return modelDisplayName(name)
            case .hosted(let hostedModel):
                return hostedModel.name
            }
        } else {
            return ""
        }
    }

    private func saveInstalledModelsToUserDefaults() {
        if let jsonData = try? JSONEncoder().encode(installedModels) {
            UserDefaults.standard.set(jsonData, forKey: installedModelsKey)
        }
    }

    private func loadInstalledModelsFromUserDefaults() {
        if let jsonData = UserDefaults.standard.data(forKey: installedModelsKey),
           let decodedArray = try? JSONDecoder().decode([String].self, from: jsonData) {
            self.installedModels = decodedArray
        } else {
            self.installedModels = []
        }
    }

    private func saveHostedModelsToUserDefaults() {
        if let jsonData = try? JSONEncoder().encode(hostedModels) {
            UserDefaults.standard.set(jsonData, forKey: hostedModelsKey)
        }
    }

    private func loadHostedModelsFromUserDefaults() {
        if let jsonData = UserDefaults.standard.data(forKey: hostedModelsKey),
           let decodedArray = try? JSONDecoder().decode([HostedModel].self, from: jsonData) {
            self.hostedModels = decodedArray
        } else {
            self.hostedModels = []
        }
    }

    private func saveCurrentModelToUserDefaults() {
        if let data = try? JSONEncoder().encode(currentModel) {
            UserDefaults.standard.set(data, forKey: currentModelKey)
        }
    }

    private func loadCurrentModelFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: currentModelKey),
           let model = try? JSONDecoder().decode(ModelSelection.self, from: data) {
            self.currentModel = model
        } else {
            self.currentModel = nil
        }
    }

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

    func modelDisplayName(_ modelName: String) -> String {
        return modelName.replacingOccurrences(of: "mlx-community/", with: "").lowercased()
    }
    
    func getMoonPhaseIcon() -> String {
        // Get current date
        let currentDate = Date()
        
        // Define a base date (known new moon date)
        let baseDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 6))!
        
        // Difference in days between the current date and the base date
        let daysSinceBaseDate = Calendar.current.dateComponents([.day], from: baseDate, to: currentDate).day!
        
        // Moon phase repeats approximately every 29.53 days
        let moonCycleLength = 29.53
        let daysIntoCycle = Double(daysSinceBaseDate).truncatingRemainder(dividingBy: moonCycleLength)
        
        // Determine the phase based on how far into the cycle we are
        switch daysIntoCycle {
        case 0..<1.8457:
            return "moonphase.new.moon" // New Moon
        case 1.8457..<5.536:
            return "moonphase.waxing.crescent" // Waxing Crescent
        case 5.536..<9.228:
            return "moonphase.first.quarter" // First Quarter
        case 9.228..<12.919:
            return "moonphase.waxing.gibbous" // Waxing Gibbous
        case 12.919..<16.610:
            return "moonphase.full.moon" // Full Moon
        case 16.610..<20.302:
            return "moonphase.waning.gibbous" // Waning Gibbous
        case 20.302..<23.993:
            return "moonphase.last.quarter" // Last Quarter
        case 23.993..<27.684:
            return "moonphase.waning.crescent" // Waning Crescent
        default:
            return "moonphase.new.moon" // New Moon (fallback)
        }
    }
}

enum Role: String, Codable {
    case assistant
    case user
    case system
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

    var sortedMessages: [Message] {
        return messages.sorted { $0.timestamp < $1.timestamp }
    }

    init() {
        self.id = UUID()
        self.timestamp = Date()
    }
}

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
        case .standard:
            return .default
        case .monospaced:
            return .monospaced
        case .rounded:
            return .rounded
        case .serif:
            return .serif
        }
    }
}

enum AppFontWidth: String, CaseIterable {
    case compressed, condensed, expanded, standard

    func getFontWidth() -> Font.Width {
        switch self {
        case .compressed:
            return .compressed
        case .condensed:
            return .condensed
        case .expanded:
            return .expanded
        case .standard:
            return .standard
        }
    }
}

enum AppFontSize: String, CaseIterable {
    case xsmall, small, medium, large, xlarge

    func getFontSize() -> DynamicTypeSize {
        switch self {
        case .xsmall:
            return .xSmall
        case .small:
            return .small
        case .medium:
            return .medium
        case .large:
            return .large
        case .xlarge:
            return .xLarge
        }
    }
}
