import SwiftUI

@Observable
class DashboardConfig {
    var pages: [DashboardPage] = []
    var selectedPageId: UUID?
    
    // Legacy key for migration
    private let legacyKey = "DashboardConfig"
    private let pagesKey = "DashboardPagesConfig"
    
    init() {
        loadConfig()
    }
    
    func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: pagesKey),
           let decoded = try? JSONDecoder().decode([DashboardPage].self, from: data) {
            let normalized = normalizePages(decoded)
            self.pages = normalized
            if !pages.isEmpty && selectedPageId == nil {
                selectedPageId = pages.first?.id
            }
            if normalized != decoded {
                saveConfig()
            }
        } else if let data = UserDefaults.standard.data(forKey: legacyKey),
                  let decoded = try? JSONDecoder().decode([DashboardItem].self, from: data) {
            // Migration: Convert single dashboard to first page
            let homePage = DashboardPage(id: UUID(), name: "Dashboard", items: normalizeItems(decoded), creationDate: Date())
            self.pages = [homePage]
            self.selectedPageId = homePage.id
            saveConfig()
            UserDefaults.standard.removeObject(forKey: legacyKey)
        } else {
            // Default Layout: 2 pages with pre-populated widgets
            let homeItems = [
                DashboardItem(type: .calendar, size: .large, order: 0),
                DashboardItem(type: .inlineInput, size: .large, order: 1)
            ]
            let homePage = DashboardPage(id: UUID(), name: "起点页", items: homeItems, creationDate: Date())

            let searchItems = [
                DashboardItem(type: .search, size: .medium, order: 0),
                DashboardItem(type: .timeline, size: .fullPage, order: 1)
            ]
            let searchPage = DashboardPage(id: UUID(), name: "搜索", items: searchItems, creationDate: Date())

            self.pages = [homePage, searchPage]
            self.selectedPageId = homePage.id
            saveConfig()
        }
    }
    
    func saveConfig() {
        if let encoded = try? JSONEncoder().encode(pages) {
            UserDefaults.standard.set(encoded, forKey: pagesKey)
        }
    }

    func addDefaultLayoutPages() {
        let homeItems = [
            DashboardItem(type: .calendar, size: .large, order: 0),
            DashboardItem(type: .inlineInput, size: .large, order: 1)
        ]
        let homePage = DashboardPage(id: UUID(), name: "起点页", items: homeItems, creationDate: Date())

        let searchItems = [
            DashboardItem(type: .search, size: .medium, order: 0),
            DashboardItem(type: .timeline, size: .fullPage, order: 1)
        ]
        let searchPage = DashboardPage(id: UUID(), name: "搜索", items: searchItems, creationDate: Date())

        pages.append(contentsOf: [homePage, searchPage])
        saveConfig()
    }

    private func normalizePages(_ pages: [DashboardPage]) -> [DashboardPage] {
        pages.map { page in
            var normalizedPage = page
            normalizedPage.items = normalizeItems(page.items)
            return normalizedPage
        }
    }

    private func normalizeItems(_ items: [DashboardItem]) -> [DashboardItem] {
        items.map { item in
            var normalizedItem = item
            let supportedSizes = item.type.supportedSizes

            guard !supportedSizes.isEmpty,
                  !supportedSizes.contains(item.size) else {
                return normalizedItem
            }

            normalizedItem.size = supportedSizes.first ?? item.size
            return normalizedItem
        }
    }
    
    // MARK: - Page Management
    
    func addPage(name: String) -> DashboardPage {
        let newPage = DashboardPage(id: UUID(), name: name, items: [], creationDate: Date())
        pages.append(newPage)
        saveConfig()
        return newPage
    }
    
    func duplicatePage(_ page: DashboardPage) -> DashboardPage {
        var newPage = page
        newPage.id = UUID()
        newPage.name = page.name + " 副本"
        newPage.creationDate = Date()
        // Generate new IDs for all items
        newPage.items = page.items.map { item in
            var newItem = item
            newItem.id = UUID()
            return newItem
        }
        pages.append(newPage)
        saveConfig()
        return newPage
    }
    
    func removePage(_ page: DashboardPage) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages.remove(at: index)
        
        // Update selection if current page was deleted
        if selectedPageId == page.id {
            selectedPageId = pages.first?.id
        }
        
        saveConfig()
    }

    func movePage(from source: IndexSet, to destination: Int) {
        pages.move(fromOffsets: source, toOffset: destination)
        saveConfig()
    }
    
    func renamePage(_ page: DashboardPage, newName: String) {
        if let index = pages.firstIndex(where: { $0.id == page.id }) {
            var updatedPage = pages[index]
            updatedPage.name = newName
            pages[index] = updatedPage
            saveConfig()
        }
    }
    
    // MARK: - Item Management (Per Page)
    
    func addItem(to pageId: UUID, type: WidgetType, tagName: String? = nil, content: String? = nil) {
        if let index = pages.firstIndex(where: { $0.id == pageId }) {
            let order = pages[index].items.count
            var newItem = DashboardItem(type: type, size: .medium, order: order)
            if type == .encouragement {
                newItem.size = .medium // Default size for encouragement
            }
            if type == .calendar {
                newItem.size = .large // Calendar is always large
            }
            if type == .timeline {
                newItem.size = .fullPage // Timeline only supports fullPage
            }
            if type == .location {
                newItem.size = .large // Default to large; fullPage remains available manually
            }
            newItem.tagName = tagName
            newItem.content = content
            pages[index].items.append(newItem)
            saveConfig()
        }
    }
    
    func removeItems(from pageId: UUID, at offsets: IndexSet) {
        if let index = pages.firstIndex(where: { $0.id == pageId }) {
            pages[index].items.remove(atOffsets: offsets)
            saveConfig()
        }
    }
    
    func removeItem(from pageId: UUID, itemId: UUID) {
        if let pageIndex = pages.firstIndex(where: { $0.id == pageId }) {
            if let itemIndex = pages[pageIndex].items.firstIndex(where: { $0.id == itemId }) {
                pages[pageIndex].items.remove(at: itemIndex)
                saveConfig()
            }
        }
    }
    
    func moveItem(in pageId: UUID, from source: IndexSet, to destination: Int) {
        if let pageIndex = pages.firstIndex(where: { $0.id == pageId }) {
            pages[pageIndex].items.move(fromOffsets: source, toOffset: destination)
            // Re-index order property if needed
            for (i, _) in pages[pageIndex].items.enumerated() {
                var item = pages[pageIndex].items[i]
                item.order = i
                pages[pageIndex].items[i] = item
            }
            saveConfig()
        }
    }
    
    func updateSize(in pageId: UUID, for itemId: UUID, size: WidgetSize) {
        if let pageIndex = pages.firstIndex(where: { $0.id == pageId }) {
            if let itemIndex = pages[pageIndex].items.firstIndex(where: { $0.id == itemId }) {
                var item = pages[pageIndex].items[itemIndex]
                item.size = size
                pages[pageIndex].items[itemIndex] = item
                saveConfig()
            }
        }
    }
    
    func updateContent(in pageId: UUID, for itemId: UUID, content: String) {
        if let pageIndex = pages.firstIndex(where: { $0.id == pageId }) {
            if let itemIndex = pages[pageIndex].items.firstIndex(where: { $0.id == itemId }) {
                var item = pages[pageIndex].items[itemIndex]
                item.content = content
                pages[pageIndex].items[itemIndex] = item
                saveConfig()
            }
        }
    }
}
