import SwiftUI

struct ToolbarItemConfig: Identifiable, Codable, Equatable {
    let type: ToolbarItemType
    var isEnabled: Bool
    
    var id: String { type.rawValue }
    
    // Add custom icon/title computed properties if needed for display within config
    var icon: String { type.icon }
    var title: String { type.title }
}

@Observable
class ToolbarSettings {
    var configs: [ToolbarItemConfig] = [] {
        didSet {
            save()
        }
    }
    
    // For backward compatibility and easy access
    var activeItems: [ToolbarItemType] {
        configs.filter { $0.isEnabled }.map { $0.type }
    }
    
    // Voice Input Toggle
    var isVoiceInputEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isVoiceInputEnabled, forKey: "isVoiceInputEnabled")
        }
    }

    // Large Icon Mode (粗大手指模式)
    var isLargeToolbarIcons: Bool = false {
        didSet {
            UserDefaults.standard.set(isLargeToolbarIcons, forKey: "isLargeToolbarIcons")
        }
    }
    
    private let userDefaultsKey = "toolbarOrder"
    private let legacyDefaultsKey = "toolbarOrderLegacy" // If we want to keep old key separate, or just overwrite?
    // Let's reuse key but detect format.
    
    init() {
        load()
    }
    
    private func load() {
        // Load voice input setting (default true)
        if UserDefaults.standard.object(forKey: "isVoiceInputEnabled") != nil {
            isVoiceInputEnabled = UserDefaults.standard.bool(forKey: "isVoiceInputEnabled")
        } else {
            isVoiceInputEnabled = true
        }

        // Load large icon mode (default false)
        if UserDefaults.standard.object(forKey: "isLargeToolbarIcons") != nil {
            isLargeToolbarIcons = UserDefaults.standard.bool(forKey: "isLargeToolbarIcons")
        }

        let savedData = UserDefaults.standard.string(forKey: userDefaultsKey)
        
        if let dataString = savedData,
           let data = dataString.data(using: .utf8) {
               
            // Try to decode new format first
            if let decoded = try? JSONDecoder().decode([ToolbarItemConfig].self, from: data) {
                // Merge new items if any
                let existingTypes = Set(decoded.map { $0.type })
                let missing = ToolbarItemType.allCases.filter { !existingTypes.contains($0) }
                configs = decoded + missing.map { ToolbarItemConfig(type: $0, isEnabled: true) }
                return
            }
            
            // Fallback: Try decode old format [ToolbarItemType]
            if let decoded = try? JSONDecoder().decode([ToolbarItemType].self, from: data) {
                // Migrate to new format
                let existingSet = Set(decoded)
                let missing = ToolbarItemType.allCases.filter { !existingSet.contains($0) }
                let allTypes = decoded + missing
                configs = allTypes.map { ToolbarItemConfig(type: $0, isEnabled: true) }
                return
            }
        }
        
        // Default (if no data or failed to decode both)
        configs = [
            .camera,
            .photo,
            .audio,
            .folder,
            .location,
            .drawing,
            .scanText,
            .scanDocument,
            .markdown
        ].map { ToolbarItemConfig(type: $0, isEnabled: true) }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(configs),
           let string = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(string, forKey: userDefaultsKey)
        }
    }
    
    func move(from source: IndexSet, to destination: Int) {
        configs.move(fromOffsets: source, toOffset: destination)
    }

    /// Move only non-markdown items; keeps markdown entry in its original position
    func moveNonMarkdown(from source: IndexSet, to destination: Int) {
        let nonMarkdownIndices = configs.indices.filter { configs[$0].type != .markdown }
        guard !nonMarkdownIndices.isEmpty else { return }
        let actualSource = IndexSet(source.map { nonMarkdownIndices[$0] })
        let actualDest: Int
        if destination < nonMarkdownIndices.count {
            actualDest = nonMarkdownIndices[destination]
        } else {
            actualDest = (nonMarkdownIndices.last ?? configs.count - 1) + 1
        }
        configs.move(fromOffsets: actualSource, toOffset: actualDest)
    }

    func toggle(_ item: ToolbarItemConfig) {
        if let index = configs.firstIndex(where: { $0.id == item.id }) {
            configs[index].isEnabled.toggle()
        }
    }
}
