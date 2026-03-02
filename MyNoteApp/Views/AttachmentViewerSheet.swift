import Combine
import AVKit
import QuickLook
import SwiftUI
import MapKit

/// 附件查看器 - 根据类型选择合适的查看方式
struct AttachmentViewerSheet: View {
    let attachment: AttachmentItem
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch attachment.type {
                case .photo, .scannedDocument, .scannedText, .drawing:
                    ImageViewer(attachment: attachment)
                case .video:
                    VideoViewer(attachment: attachment)
                case .audio:
                    AudioPlayerView(attachment: attachment)
                case .file:
                    FilePreviewView(attachment: attachment)
                case .location:
                    LocationViewer(attachment: attachment)
                }
            }
            .navigationTitle(attachment.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 图片查看器

struct ImageViewer: View {
    let attachment: AttachmentItem
    @Environment(NoteStore.self) var noteStore
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = value.magnification
                            }
                            .onEnded { _ in
                                withAnimation(.spring()) {
                                    scale = max(1.0, min(scale, 5.0))
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            scale = scale > 1.0 ? 1.0 : 2.5
                        }
                    }
            } else {
                ProgressView()
                    .scaleEffect(1.5)
            }
        }
        .onAppear { loadImage() }
    }

    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = noteStore.attachmentURL(for: attachment)
            if let data = try? Data(contentsOf: url),
                let loaded = UIImage(data: data)
            {
                DispatchQueue.main.async {
                    image = loaded
                }
            }
        }
    }
}

// MARK: - 视频播放器

struct VideoViewer: View {
    let attachment: AttachmentItem
    @Environment(NoteStore.self) var noteStore
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            let url = noteStore.attachmentURL(for: attachment)
            let avPlayer = AVPlayer(url: url)
            // 禁用 AirPlay 设备扫描——AVKit 扫描本地网络 AirPlay 路由是
            // 触发"本地网络权限"弹窗的根本原因
            avPlayer.allowsExternalPlayback = false
            player = avPlayer
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

// MARK: - 音频播放器

struct AudioPlayerView: View {
    let attachment: AttachmentItem
    @Environment(NoteStore.self) var noteStore
    @StateObject private var player = AudioPlayerModel()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 圆形可视化
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.08))
                    .frame(width: 180, height: 180)

                if player.isPlaying {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 150, height: 150)
                        .scaleEffect(player.isPlaying ? 1.1 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true),
                            value: player.isPlaying
                        )
                }

                Image(systemName: player.isPlaying ? "waveform" : "waveform")
                    .font(.system(size: 56))
                    .foregroundColor(.orange)
            }

            Spacer()
                .frame(height: 40)

            // 时间信息
            VStack(spacing: 6) {
                // 进度条
                ProgressView(value: player.progress)
                    .progressViewStyle(.linear)
                    .tint(.orange)
                    .padding(.horizontal, 40)

                HStack {
                    Text(formatTime(player.currentTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(player.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 40)

            // 播放控制
            HStack(spacing: 50) {
                // 后退 15s
                Button {
                    player.seekBackward()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 28))
                        .foregroundColor(.primary)
                }
                .accessibilityLabel("倒退15秒")

                // 播放/暂停
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.orange)
                }
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                // 前进 15s
                Button {
                    player.seekForward()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 28))
                        .foregroundColor(.primary)
                }
                .accessibilityLabel("快进15秒")
            }

            Spacer()

            // 文件名
            Text(attachment.fileName)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
        }
        .onAppear {
            let url = noteStore.attachmentURL(for: attachment)
            player.load(url: url)
        }
        .onDisappear {
            player.stop()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// 音频播放模型
class AudioPlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var progress: Double = 0

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
        } catch {
            print("❌ 音频加载失败: \(error)")
        }
    }

    func togglePlayPause() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        stopTimer()
    }

    func seekForward() {
        guard let player = audioPlayer else { return }
        player.currentTime = min(player.currentTime + 15, player.duration)
        updateProgress()
    }

    func seekBackward() {
        guard let player = audioPlayer else { return }
        player.currentTime = max(player.currentTime - 15, 0)
        updateProgress()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateProgress()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateProgress() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
        duration = player.duration
        progress = duration > 0 ? currentTime / duration : 0

        if !player.isPlaying && currentTime >= duration - 0.1 {
            isPlaying = false
            stopTimer()
        }
    }
}

// MARK: - 文件预览（QuickLook）

struct FilePreviewView: View {
    let attachment: AttachmentItem
    @Environment(NoteStore.self) var noteStore

    var body: some View {
        QuickLookPreviewWrapper(url: noteStore.attachmentURL(for: attachment))
    }
}

/// QLPreviewController 的 SwiftUI 包装
struct QuickLookPreviewWrapper: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int)
            -> QLPreviewItem
        {
            url as NSURL
        }
    }
}

// MARK: - 位置查看器

struct LocationViewer: View {
    let attachment: AttachmentItem
    @Environment(NoteStore.self) var noteStore
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition = .automatic
    
    var body: some View {
        ZStack {
            if let coordinate = coordinate {
                Map(position: $position) {
                    Marker("标记位置", coordinate: coordinate)
                }
                
                VStack {
                    Spacer()
                    Button {
                        openInMaps(coordinate)
                    } label: {
                        HStack {
                            Image(systemName: "map.fill")
                            Text("在地图应用中打开")
                        }
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    }
                    .padding(.bottom, 40)
                }
            } else {
                ProgressView()
            }
        }
        .onAppear { loadLocation() }
    }
    
    private func loadLocation() {
        let url = noteStore.attachmentURL(for: attachment)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = json["latitude"] as? Double,
              let lon = json["longitude"] as? Double
        else { return }
        
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        self.coordinate = coord
        self.position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1000, longitudinalMeters: 1000))
    }
    
    private func openInMaps(_ coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = "标记位置"
        mapItem.openInMaps(launchOptions: nil)
    }
}
