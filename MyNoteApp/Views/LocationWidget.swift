import SwiftUI
import SwiftData
import MapKit

// MARK: - LocationWidget

/// 地理组件 — 支持地图模式和列表模式切换，支持 fullPage 和 large 尺寸
struct LocationWidget: View {
    var size: WidgetSize = .large
    let isEditing: Bool

    @Environment(NoteStore.self) private var noteStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @Environment(FontManager.self) private var fontManager

    @State private var notes: [NoteItem] = []
    @State private var selectedNote: NoteItem?
    @State private var listID = UUID()
    @State private var collapsedCountries: Set<String> = []
    @State private var showMapMode: Bool = true
    @State private var visibleNoteIDs: Set<UUID> = []
    @State private var hasMapRegion: Bool = false

    // MARK: - Location Groups

    /// 从 location 附件的 location 字段解析国家和城市
    private struct LocationInfo {
        let country: String
        let city: String
    }

    /// 解析地址字符串：tab 分隔 country\tadminArea\tlocality\t...，兼容旧空格格式
    private func parseLocation(from address: String) -> LocationInfo? {
        let parts: [String]
        if address.contains("\t") {
            parts = address.components(separatedBy: "\t").filter { !$0.isEmpty }
        } else {
            parts = address.components(separatedBy: " ").filter { !$0.isEmpty }
        }
        guard !parts.isEmpty else { return nil }
        let country = parts[0]
        let city: String
        if parts.count >= 3 {
            city = parts[2]
        } else if parts.count >= 2 {
            city = parts[1]
        } else {
            city = "未知城市"
        }
        return LocationInfo(country: country, city: city)
    }

    /// 列表中实际展示的笔记（地图可见区域过滤后）
    private var filteredNotes: [NoteItem] {
        if !hasMapRegion { return notes }
        return notes.filter { visibleNoteIDs.contains($0.id) }
    }

    /// 按国家 → 城市分组
    private var countryGroups: [(country: String, cities: [(city: String, notes: [NoteItem])])] {
        // country -> city -> [NoteItem]
        var map: [String: [String: [NoteItem]]] = [:]
        var countryOrder: [String] = []
        var cityOrder: [String: [String]] = [:]

        for note in filteredNotes {
            let locationAttachments = note.attachments.filter { $0.type == .location }
            guard !locationAttachments.isEmpty else { continue }

            // 从所有地址附件中提取地点，同一笔记可能出现在多个城市
            var noteAdded: Set<String> = [] // 避免同一笔记在同一城市中重复
            for attachment in locationAttachments {
                let address = attachment.location ?? attachment.recognitionMeta ?? ""
                guard !address.isEmpty,
                      let loc = parseLocation(from: address) else { continue }
                let key = "\(loc.country)/\(loc.city)"
                guard !noteAdded.contains(key) else { continue }
                noteAdded.insert(key)

                if map[loc.country] == nil {
                    map[loc.country] = [:]
                    countryOrder.append(loc.country)
                    cityOrder[loc.country] = []
                }
                if map[loc.country]?[loc.city] == nil {
                    map[loc.country]?[loc.city] = []
                    cityOrder[loc.country]?.append(loc.city)
                }
                map[loc.country]?[loc.city]?.append(note)
            }
        }

        return countryOrder.map { country in
            let cities = (cityOrder[country] ?? []).map { city in
                (city: city, notes: map[country]?[city] ?? [])
            }
            return (country: country, cities: cities)
        }
    }

    /// 所有含地址附件的笔记总数
    private var totalLocationNotes: Int {
        countryGroups.reduce(0) { total, group in
            total + group.cities.reduce(0) { $0 + $1.notes.count }
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                headerBar

                Divider()
                    .opacity(0.5)

                if showMapMode {
                    LocationMapView(
                        notes: notes,
                        selectedNote: $selectedNote,
                        visibleNoteIDs: $visibleNoteIDs,
                        hasMapRegion: $hasMapRegion
                    )
                    .environment(noteStore)
                    .frame(height: max(geo.size.height - 46, 100))
                } else {
                    List {
                        ForEach(countryGroups, id: \.country) { group in
                            Section {
                                if !collapsedCountries.contains(group.country) {
                                    ForEach(group.cities, id: \.city) { cityGroup in
                                        citySectionHeader(city: cityGroup.city, count: cityGroup.notes.count)
                                        ForEach(cityGroup.notes) { note in
                                            LocationNoteRow(note: note, onSelect: { _ in selectedNote = note })
                                                .environment(noteStore)
                                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                                .listRowBackground(Color.clear)
                                                .listRowSeparator(.hidden)
                                        }
                                    }
                                }
                            } header: {
                                countrySectionHeader(
                                    country: group.country,
                                    cityCount: group.cities.count,
                                    noteCount: group.cities.reduce(0) { $0 + $1.notes.count },
                                    isCollapsed: collapsedCountries.contains(group.country)
                                )
                            }
                            .listSectionSeparator(.hidden)
                        }

                        if countryGroups.isEmpty {
                            emptyState
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(theme.colors.surface)
                    .id(listID)
                    .frame(height: max(geo.size.height - 46, 100))
                }
            }
        }
        .frame(minHeight: size == .fullPage ? nil : UIScreen.main.bounds.height * 3 / 5)
        .onAppear { loadNotes() }
        .onChange(of: noteStore.contentRevision) {
            loadNotes()
            listID = UUID()
        }
        .navigationDestination(item: $selectedNote) { note in
            NoteView(note: note, startInEditMode: false)
                .environment(noteStore)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundColor(theme.colors.accent)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text("地图")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.colors.secondaryText)
            Spacer()
            if hasMapRegion && totalLocationNotes > 0 {
                Text("\(totalLocationNotes) 条记录")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.5))
                    .padding(.trailing, 4)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showMapMode.toggle()
                }
            } label: {
                Image(systemName: showMapMode ? "list.bullet" : "map")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.colors.accent)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 46)
    }

    // MARK: - Country Section Header

    private func countrySectionHeader(country: String, cityCount: Int, noteCount: Int, isCollapsed: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                if collapsedCountries.contains(country) {
                    collapsedCountries.remove(country)
                } else {
                    collapsedCountries.insert(country)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.5))
                    .frame(width: 12)

                Image(systemName: "flag.fill")
                    .font(.system(size: 11))
                    .foregroundColor(theme.colors.accent.opacity(0.7))

                Text(country)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.colors.secondaryText)

                Text("\(cityCount)个城市 · \(noteCount)条")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.45))

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.colors.surface)
        .textCase(nil)
        .listRowInsets(EdgeInsets())
    }

    // MARK: - City Section Header

    private func citySectionHeader(city: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(theme.colors.border.opacity(0.4))
                .frame(height: 0.5)
                .frame(width: 20)

            Image(systemName: "building.2.fill")
                .font(.system(size: 10))
                .foregroundColor(theme.colors.accent.opacity(0.55))

            Text(city)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(theme.colors.secondaryText.opacity(0.65))

            Text("(\(count))")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(theme.colors.secondaryText.opacity(0.4))

            Rectangle()
                .fill(theme.colors.border.opacity(0.4))
                .frame(height: 0.5)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 38))
                .foregroundColor(theme.colors.secondaryText.opacity(0.25))
            Text("还没有包含位置的记录")
                .font(.subheadline)
                .foregroundColor(theme.colors.secondaryText.opacity(0.45))
            Text("在笔记中添加位置附件后，这里会按国家和城市归类展示")
                .font(.caption2)
                .foregroundColor(theme.colors.secondaryText.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Data Fetching

    private func loadNotes() {
        var descriptor = FetchDescriptor<NoteItem>(
            predicate: #Predicate { !$0.isDeleted }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        notes = fetched.filter { note in
            note.attachments.contains { $0.type == .location }
        }
    }
}

// MARK: - LocationNoteRow

private struct LocationNoteRow: View {
    let note: NoteItem
    let onSelect: (NoteItem) -> Void

    @Environment(NoteStore.self) private var noteStore
    @Environment(\.appTheme) private var theme
    @Environment(FontManager.self) private var fontManager

    /// 该笔记所有位置附件的地址摘要
    private var locationSummary: String {
        let addresses = note.attachments
            .filter { $0.type == .location }
            .compactMap { $0.location ?? $0.recognitionMeta }
            .filter { !$0.isEmpty }
        if addresses.isEmpty { return "" }
        let raw = addresses[0]
        let parts: [String]
        if raw.contains("\t") {
            parts = raw.components(separatedBy: "\t").filter { !$0.isEmpty }
        } else {
            parts = raw.components(separatedBy: " ").filter { !$0.isEmpty }
        }
        if parts.count > 2 {
            return parts.dropFirst(2).joined(separator: " ")
        }
        return raw.replacingOccurrences(of: "\t", with: " ")
    }

    var body: some View {
        Button { onSelect(note) } label: {
            HStack(alignment: .top, spacing: 0) {
                // ── 位置标记列 ──────────────────────────
                VStack(spacing: 2) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(theme.colors.accent.opacity(0.6))
                        .padding(.top, 14)
                }
                .frame(width: 28)
                .padding(.leading, 16)

                // ── 竖脊线 ────────────────────────
                locationSpine

                // ── 笔记卡片 ──────────
                VStack(alignment: .leading, spacing: 4) {
                    NoteRowView(note: note, showDateFooter: false)
                        .environment(noteStore)

                    if !locationSummary.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 8))
                                .foregroundColor(theme.colors.secondaryText.opacity(0.35))
                            Text(locationSummary)
                                .font(.system(size: 10))
                                .foregroundColor(theme.colors.secondaryText.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // 点 + 竖线
    private var locationSpine: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(theme.colors.border.opacity(0.35))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            Circle()
                .strokeBorder(theme.colors.accent.opacity(0.5), lineWidth: 1)
                .background(Circle().fill(theme.colors.surface))
                .frame(width: 7, height: 7)
                .padding(.top, 14)
        }
        .frame(width: 14)
        .padding(.horizontal, 4)
    }
}

// MARK: - LocationMapView

/// 在地图上标记所有带位置的日记，同一地区合并为一个标记
private struct LocationMapView: View {
    let notes: [NoteItem]
    @Environment(NoteStore.self) private var noteStore
    @Binding var selectedNote: NoteItem?
    @Binding var visibleNoteIDs: Set<UUID>
    @Binding var hasMapRegion: Bool

    /// 单条笔记的坐标信息
    private struct NotePin {
        let coordinate: CLLocationCoordinate2D
        let note: NoteItem
    }

    /// 同一地区聚合后的标记
    private struct ClusterPin: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let notes: [NoteItem]
        var title: String {
            if notes.count == 1 {
                let firstLine = notes[0].content.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? ""
                return firstLine.isEmpty
                    ? notes[0].createdAt.formatted(date: .abbreviated, time: .shortened)
                    : String(firstLine.prefix(20))
            }
            return "\(notes.count) 条笔记"
        }
    }

    @State private var clusters: [ClusterPin] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var expandedCluster: ClusterPin?
    @State private var selectedTag: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, selection: $selectedTag) {
                ForEach(clusters) { cluster in
                    Annotation(cluster.title, coordinate: cluster.coordinate) {
                        clusterView(cluster)
                    }
                    .tag(cluster.id)
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }
            .onChange(of: selectedTag) { _, newValue in
                guard let tag = newValue,
                      let cluster = clusters.first(where: { $0.id == tag }) else { return }
                selectedTag = nil
                if cluster.notes.count == 1 {
                    selectedNote = cluster.notes[0]
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expandedCluster = cluster
                    }
                }
            }
            .onMapCameraChange { context in
                updateVisibleNotes(region: context.region)
            }
            .onAppear { loadPins() }
            .onChange(of: notes.count) { loadPins() }

            // 展开的笔记列表弹出面板
            if let cluster = expandedCluster {
                clusterSheet(cluster)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Cluster Marker View

    private func clusterView(_ cluster: ClusterPin) -> some View {
        ZStack {
            if cluster.notes.count == 1 {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.red)
            } else {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.red)
                    Text("\(cluster.notes.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Circle().fill(.blue))
                        .offset(x: 6, y: -6)
                }
            }
        }
    }

    // MARK: - Expanded Cluster Sheet

    private func clusterSheet(_ cluster: ClusterPin) -> some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                Text(cluster.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expandedCluster = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // 使用和其他组件一致的列表样式
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(cluster.notes) { note in
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                expandedCluster = nil
                            }
                            selectedNote = note
                        } label: {
                            NoteRowView(note: note, showDateFooter: true)
                                .environment(noteStore)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 10, y: -2)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Visible Region Filtering

    private func updateVisibleNotes(region: MKCoordinateRegion) {
        hasMapRegion = true
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        var ids = Set<UUID>()
        for cluster in clusters {
            let lat = cluster.coordinate.latitude
            let lon = cluster.coordinate.longitude
            if lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon {
                for note in cluster.notes {
                    ids.insert(note.id)
                }
            }
        }
        visibleNoteIDs = ids
    }

    // MARK: - Data Loading

    private func loadPins() {
        // 收集所有坐标
        var allPins: [NotePin] = []
        for note in notes {
            let locationAttachments = note.attachments.filter { $0.type == .location }
            for attachment in locationAttachments {
                let url = noteStore.attachmentURL(for: attachment)
                guard let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let lat = json["latitude"] as? Double,
                      let lon = json["longitude"] as? Double
                else { continue }
                allPins.append(NotePin(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    note: note
                ))
            }
        }

        // 按地区聚合：经纬度四舍五入到小数点后两位（约 1km 范围）
        var grouped: [String: (coord: CLLocationCoordinate2D, notes: [NoteItem])] = [:]
        for pin in allPins {
            let key = "\(round(pin.coordinate.latitude * 100) / 100),\(round(pin.coordinate.longitude * 100) / 100)"
            if grouped[key] != nil {
                if !grouped[key]!.notes.contains(where: { $0.id == pin.note.id }) {
                    grouped[key]!.notes.append(pin.note)
                }
            } else {
                grouped[key] = (coord: pin.coordinate, notes: [pin.note])
            }
        }

        clusters = grouped.map { key, value in
            ClusterPin(id: key, coordinate: value.coord, notes: value.notes)
        }

        // 初始化时不设置 hasMapRegion，等用户操作地图后再开始过滤

        // 以当前位置为中心，5km 比例尺
        let mgr = CLLocationManager()
        mgr.requestWhenInUseAuthorization()
        if let coord = mgr.location?.coordinate {
            position = .region(MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 5000,
                longitudinalMeters: 5000
            ))
        } else {
            position = .userLocation(fallback: .automatic)
        }
    }

}
