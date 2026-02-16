import SwiftUI
import Combine

class ToolbarSettings: ObservableObject {
    @Published var items: [ToolbarItemType] = [] {
        didSet {
            save()
        }
    }
    
    private let userDefaultsKey = "toolbarOrder"
    
    init() {
        load()
    }
    
    private func load() {
        let savedData = UserDefaults.standard.string(forKey: userDefaultsKey)
        
        if let dataString = savedData,
           let data = dataString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([ToolbarItemType].self, from: data) {
            
            // Allow for new enum cases added later
            let existingSet = Set(decoded)
            let missing = ToolbarItemType.allCases.filter { !existingSet.contains($0) }
            items = decoded + missing
            
        } else {
            // Default order
            items = [
                .camera,
                .photo,
                .audio,
                .folder,
                .location, // New case
                .drawing,
                .scanText,
                .scanDocument
            ]
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(items),
           let string = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(string, forKey: userDefaultsKey)
        }
    }
    
    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }
}
