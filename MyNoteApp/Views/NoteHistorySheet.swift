import SwiftUI
import SwiftData
import AVKit
import QuickLook
import MapKit

// MARK: - NoteHistorySheet

/// 笔记历史版本面板 — 与时间轴组件保持一致的 UI 风格
struct NoteHistorySheet: View {
    let note: NoteItem
    /// 用户选择「替换当前版本」后的回调，传入完整版本对象
    let onRestore: (NoteVersion) -> Void

    @Environment(NoteStore.self) private var noteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(FontManager.self) private var fontManager

    @State private var versions: [NoteVersion] = []
    @State private var selectedVersion: NoteVersion?

    // MARK: - Day Groups

    private var dayGroups: [(label: String, id: String, versions: [NoteVersion])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日"
        let isoFmt = ISO8601DateFormatter()

        var result: [(label: String, id: String, versions: [NoteVersion])] = []
        var seen: [Date: Int] = [:]

        for version in versions {
            let day = cal.startOfDay(for: version.savedAt)
            if let idx = seen[day] {
                result[idx].versions.append(version)
            } else {
                seen[day] = result.count
                let label: String
                if cal.isDateInToday(day) { label = "今天" }
                else if cal.isDateInYesterday(day) { label = "昨天" }
                else { label = fmt.string(from: day) }
                result.append((label: label, id: isoFmt.string(from: day), versions: [version]))
            }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar
                Divider().opacity(0.5)

                if versions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(dayGroups, id: \.id) { group in
                            Section {
                                ForEach(group.versions) { version in
                                    HistoryVersionRow(version: version) {
                                        selectedVersion = version
                                    }
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation {
                                                noteStore.deleteVersion(version)
                                                versions.removeAll { $0.id == version.id }
                                            }
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                daySectionHeader(label: group.label)
                            }
                            .listSectionSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(theme.colors.surface)
                }
            }
            .background(theme.colors.surface.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .onAppear {
            versions = noteStore.fetchVersions(for: note.id)
        }
        .sheet(item: $selectedVersion) { version in
            let idx = versions.firstIndex(where: { $0.id == version.id }) ?? 0
            VersionDetailSheet(
                version: version,
                allVersions: versions,
                currentIndex: idx,
                attachmentsDirectory: noteStore.attachmentsDirectory
            ) { v in
                onRestore(v)
                dismiss()
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .foregroundColor(theme.colors.accent)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text("历史版本")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.colors.secondaryText)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.35))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 46)
    }

    // MARK: - Day Section Header

    private func daySectionHeader(label: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(theme.colors.border.opacity(0.5))
                .frame(height: 0.5)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(theme.colors.secondaryText.opacity(0.65))
                .fixedSize()
            Rectangle()
                .fill(theme.colors.border.opacity(0.5))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(theme.colors.surface)
        .textCase(nil)
        .listRowInsets(EdgeInsets())
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 38))
                .foregroundColor(theme.colors.secondaryText.opacity(0.25))
            Text("还没有历史版本")
                .font(.subheadline)
                .foregroundColor(theme.colors.secondaryText.opacity(0.45))
            Text("完成编辑后将自动保存一份版本快照")
                .font(.caption)
                .foregroundColor(theme.colors.secondaryText.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - HistoryVersionRow

private struct HistoryVersionRow: View {
    let version: NoteVersion
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(FontManager.self) private var fontManager
    @Environment(NoteStore.self) private var noteStore

    private var timeText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: version.savedAt)
    }

    private var visualSnaps: [AttachmentSnapshot] {
        version.attachmentSnapshots
            .filter { [.photo, .video, .scannedDocument, .drawing].contains($0.type) }
    }

    private var otherSnaps: [AttachmentSnapshot] {
        version.attachmentSnapshots
            .filter { ![.photo, .video, .scannedDocument, .drawing].contains($0.type) }
    }

    var body: some View {
        Button { onTap() } label: {
            HStack(alignment: .top, spacing: 0) {
                // ── 时间列 ──────────────────────────
                Text(timeText)
                    .font(.system(size: 11.5, weight: .light, design: .monospaced))
                    .foregroundColor(theme.colors.secondaryText.opacity(0.6))
                    .frame(width: 42, alignment: .leading)
                    .padding(.top, 14)
                    .padding(.leading, 16)

                // ── 时间线竖脊 ────────────────────────
                timelineSpine

                // ── 版本卡片（完整预览 + 附件马赛克）──────────
                VStack(alignment: .leading, spacing: 8) {
                    if version.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("（此版本内容为空）")
                            .font(.subheadline)
                            .foregroundColor(theme.colors.secondaryText.opacity(0.4))
                    } else {
                        NoteCardPreview(content: version.content)
                    }

                    if !visualSnaps.isEmpty {
                        VersionSnapshotGrid(
                            snaps: visualSnaps,
                            dir: noteStore.attachmentsDirectory
                        )
                    }

                    if !otherSnaps.isEmpty {
                        VersionSnapshotChips(snaps: otherSnaps)
                    }

                    Text("\(version.content.count) 字符")
                        .font(.system(size: 10))
                        .foregroundColor(theme.colors.secondaryText.opacity(0.4))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.colors.card)
                .cornerRadius(12)
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // 时间线竖脊：竖线 + 圆点
    private var timelineSpine: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(theme.colors.border.opacity(0.45))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            Circle()
                .strokeBorder(theme.colors.border.opacity(0.9), lineWidth: 1)
                .background(Circle().fill(theme.colors.surface))
                .frame(width: 7, height: 7)
                .padding(.top, 13)
        }
        .frame(width: 14)
        .padding(.horizontal, 6)
    }
}

// MARK: - VersionSnapshotGrid

/// 与 NoteRowView.visualGrid 相同的马赛克布局，但使用 AttachmentSnapshot + 目录 URL 加载图片
private struct VersionSnapshotGrid: View {
    let snaps: [AttachmentSnapshot]
    let dir: URL

    var body: some View {
        let visible = Array(snaps.prefix(4))
        let overflow = snaps.count - visible.count

        switch visible.count {
        case 1:
            SnapImage(snap: visible[0], dir: dir)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))

        case 2:
            HStack(spacing: 4) {
                ForEach(visible) { s in
                    SnapImage(snap: s, dir: dir)
                        .frame(maxWidth: .infinity)
                        .frame(height: 105)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

        default:
            let lead  = visible[0]
            let rest  = Array(visible.dropFirst())
            let slotH = (150.0 - CGFloat(rest.count - 1) * 4) / CGFloat(rest.count)

            HStack(alignment: .top, spacing: 4) {
                SnapImage(snap: lead, dir: dir)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(spacing: 4) {
                    ForEach(Array(rest.enumerated()), id: \.element.id) { idx, s in
                        ZStack {
                            SnapImage(snap: s, dir: dir)
                                .frame(maxWidth: .infinity)
                                .frame(height: slotH)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            if idx == rest.count - 1, overflow > 0 {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.black.opacity(0.45))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: slotH)
                                Text("+\(overflow)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - SnapImage

/// 从 attachmentsDirectory 异步加载缩略图的图片视图
private struct SnapImage: View {
    let snap: AttachmentSnapshot
    let dir: URL
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity.animation(.easeIn(duration: 0.2)))
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(ProgressView().scaleEffect(0.7))
                }
            }
        }
        .onAppear { load() }
    }

    private func load() {
        guard image == nil else { return }
        let fileName = snap.thumbnailFileName ?? snap.fileName
        let url = dir.appendingPathComponent(fileName)
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                DispatchQueue.main.async { withAnimation { image = img } }
            }
        }
    }
}

// MARK: - VersionSnapshotChips

/// 非可视类型附件的 chip 标签行（录音、文件、位置等）
private struct VersionSnapshotChips: View {
    let snaps: [AttachmentSnapshot]
    @Environment(\.appTheme) private var theme

    var body: some View {
        let shown = Array(snaps.prefix(5))
        let extra = snaps.count - shown.count
        HStack(spacing: 5) {
            ForEach(shown) { s in
                HStack(spacing: 3) {
                    Image(systemName: s.type.iconName)
                        .font(.system(size: 9))
                    Text(s.type.displayName)
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(theme.colors.cardSecondary)
                .foregroundColor(theme.colors.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - VersionDetailSheet

/// 版本详情页 — 只读预览，支持一键替换当前版本，以及前后版本导航
struct VersionDetailSheet: View {
    /// 当前显示的版本（内部通过 index 切换，不直接用 let）
    let initialVersion: NoteVersion
    /// 全部历史版本（倒序：index 0 = 最新）
    let allVersions: [NoteVersion]
    let initialIndex: Int
    let attachmentsDirectory: URL
    let onRestore: (NoteVersion) -> Void

    @Environment(\..dismiss) private var dismiss
    @Environment(\..appTheme) private var theme
    @Environment(FontManager.self) private var fontManager

    @State private var currentIndex: Int
    @State private var showRestoreConfirm = false
    @State private var selectedSnap: AttachmentSnapshot?

    init(version: NoteVersion, allVersions: [NoteVersion], currentIndex: Int,
         attachmentsDirectory: URL, onRestore: @escaping (NoteVersion) -> Void) {
        self.initialVersion = version
        self.allVersions = allVersions
        self.initialIndex = currentIndex
        self.attachmentsDirectory = attachmentsDirectory
        self.onRestore = onRestore
        self._currentIndex = State(initialValue: currentIndex)
    }

    private var version: NoteVersion { allVersions[currentIndex] }
    /// index 0 = 最新版本，所以 index-1 = 更新；index+1 = 更旧
    private var canGoNewer: Bool { currentIndex > 0 }
    private var canGoOlder: Bool { currentIndex < allVersions.count - 1 }

    private var savedAtText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日  HH:mm:ss"
        return fmt.string(from: version.savedAt)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 版本时间标注
                    Text(savedAtText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.colors.secondaryText.opacity(0.5))
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    Divider().opacity(0.4).padding(.horizontal, 18)

                    // Markdown 只读渲染
                    if version.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("（此版本内容为空）")
                            .font(.subheadline)
                            .foregroundColor(theme.colors.secondaryText.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        MarkdownRenderView(
                            content: version.content,
                            attachmentsDirectory: attachmentsDirectory
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }

                    // ── 附件缩略图栏 ──
                    let snapshots = version.attachmentSnapshots
                    if !snapshots.isEmpty {
                        Divider().opacity(0.4).padding(.horizontal, 18).padding(.top, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("附件")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(theme.colors.secondaryText.opacity(0.5))
                                .padding(.horizontal, 18)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(snapshots) { snap in
                                        VersionAttachmentThumb(
                                            snap: snap,
                                            attachmentsDirectory: attachmentsDirectory
                                        )
                                        .onTapGesture { selectedSnap = snap }
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(.vertical, 10)
                    }

                    Spacer(minLength: 100)
                }
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("版本预览")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.colors.primaryText)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // 已是最新版本标签
                    if !canGoNewer {
                        Text("已是最新")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.colors.secondaryText.opacity(0.45))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(theme.colors.card))
                    }
                    // 上一版本（更新）
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { currentIndex -= 1 }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .disabled(!canGoNewer)
                    // 下一版本（更旧）
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { currentIndex += 1 }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .disabled(!canGoOlder)
                    // 恢复按钮
                    Button {
                        showRestoreConfirm = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(theme.colors.accent)
                    }
                }
            }
        }
        .confirmationDialog(
            "替换当前版本",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("替换当前版本", role: .destructive) {
                onRestore(version)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("当前笔记内容将被此历史版本覆盖，操作无法撤销。")
        }
        .sheet(item: $selectedSnap) { snap in
            VersionAttachmentViewerSheet(snap: snap, attachmentsDirectory: attachmentsDirectory)
        }
    }
}

// MARK: - VersionAttachmentThumb

/// 单个附件快照的缩略图 / 图标卡片（仅展示，可点击）
private struct VersionAttachmentThumb: View {
    let snap: AttachmentSnapshot
    let attachmentsDirectory: URL

    @Environment(\.appTheme) private var theme
    @State private var thumbImage: UIImage?

    private let size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.card)

            switch snap.type {
            case .photo, .scannedDocument, .scannedText, .drawing, .location:
                if let img = thumbImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView().scaleEffect(0.7)
                }

            case .video:
                ZStack {
                    if let img = thumbImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        theme.colors.cardSecondary
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(radius: 2)
                }

            case .audio:
                VStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                    Text("录音")
                        .font(.system(size: 10))
                        .foregroundColor(theme.colors.secondaryText)
                }

            case .file:
                VStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                    Text("文件")
                        .font(.system(size: 10))
                        .foregroundColor(theme.colors.secondaryText)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.colors.border, lineWidth: 0.5)
        )
        .onAppear { loadThumb() }
    }

    private func loadThumb() {
        let thumbName = snap.thumbnailFileName ?? snap.fileName
        let url = attachmentsDirectory.appendingPathComponent(thumbName)
        DispatchQueue.global(qos: .userInitiated).async {
            let img = UIImage(data: (try? Data(contentsOf: url)) ?? Data())
            DispatchQueue.main.async { thumbImage = img }
        }
    }
}

// MARK: - VersionAttachmentViewerSheet

/// 版本附件查看器 — 直接使用文件 URL，无需 NoteStore / AttachmentItem
struct VersionAttachmentViewerSheet: View {
    let snap: AttachmentSnapshot
    let attachmentsDirectory: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    private var fileURL: URL {
        attachmentsDirectory.appendingPathComponent(snap.fileName)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch snap.type {
                case .photo, .scannedDocument, .scannedText, .drawing:
                    VersionImageViewer(url: fileURL)

                case .video:
                    VersionVideoViewer(url: fileURL)

                case .audio:
                    VersionAudioViewer(url: fileURL, fileName: snap.fileName)

                case .file:
                    QuickLookPreviewWrapper(url: fileURL)

                case .location:
                    VersionLocationViewer(url: fileURL)
                }
            }
            .navigationTitle(snap.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - VersionImageViewer

private struct VersionImageViewer: View {
    let url: URL
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { scale = $0.magnification }
                            .onEnded { _ in
                                withAnimation(.spring()) { scale = max(1.0, min(scale, 5.0)) }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) { scale = scale > 1.0 ? 1.0 : 2.5 }
                    }
            } else {
                ProgressView().scaleEffect(1.5)
            }
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let img = UIImage(data: (try? Data(contentsOf: url)) ?? Data())
                DispatchQueue.main.async { image = img }
            }
        }
    }
}

// MARK: - VersionVideoViewer

private struct VersionVideoViewer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player).ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            let avPlayer = AVPlayer(url: url)
            avPlayer.allowsExternalPlayback = false
            player = avPlayer
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

// MARK: - VersionAudioViewer

private struct VersionAudioViewer: View {
    let url: URL
    let fileName: String
    @StateObject private var player = AudioPlayerModel()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Color.orange.opacity(0.08)).frame(width: 180, height: 180)
                if player.isPlaying {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 150, height: 150)
                        .scaleEffect(player.isPlaying ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: player.isPlaying)
                }
                Image(systemName: "waveform").font(.system(size: 56)).foregroundColor(.orange)
            }
            Spacer().frame(height: 40)
            VStack(spacing: 6) {
                ProgressView(value: player.progress)
                    .progressViewStyle(.linear).tint(.orange).padding(.horizontal, 40)
                HStack {
                    Text(formatTime(player.currentTime)).font(.caption).foregroundColor(.secondary).monospacedDigit()
                    Spacer()
                    Text(formatTime(player.duration)).font(.caption).foregroundColor(.secondary).monospacedDigit()
                }.padding(.horizontal, 40)
            }
            Spacer().frame(height: 40)
            HStack(spacing: 50) {
                Button { player.seekBackward() } label: {
                    Image(systemName: "gobackward.15").font(.system(size: 28)).foregroundColor(.primary)
                }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64)).foregroundColor(.orange)
                }
                Button { player.seekForward() } label: {
                    Image(systemName: "goforward.15").font(.system(size: 28)).foregroundColor(.primary)
                }
            }
            Spacer()
            Text(fileName).font(.caption).foregroundColor(.secondary).padding(.bottom, 20)
        }
        .onAppear { player.load(url: url) }
        .onDisappear { player.stop() }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - VersionLocationViewer

private struct VersionLocationViewer: View {
    let url: URL
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            if let coordinate {
                Map(position: $position) { Marker("标记位置", coordinate: coordinate) }
                VStack {
                    Spacer()
                    Button {
                        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
                        item.name = "标记位置"
                        item.openInMaps(launchOptions: nil)
                    } label: {
                        HStack {
                            Image(systemName: "map.fill")
                            Text("在地图应用中打开")
                        }
                        .font(.headline).foregroundColor(.primary)
                        .padding().background(.regularMaterial).cornerRadius(12).shadow(radius: 5)
                    }
                    .padding(.bottom, 40)
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = json["latitude"] as? Double,
                  let lon = json["longitude"] as? Double else { return }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            coordinate = coord
            position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1000, longitudinalMeters: 1000))
        }
    }
}
