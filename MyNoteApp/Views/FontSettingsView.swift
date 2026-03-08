import SwiftUI
import UniformTypeIdentifiers

// MARK: - FontSettingsView

/// Settings page for installing / removing a custom editor font,
/// and for adjusting font size and line height.
struct FontSettingsView: View {
    @Environment(FontManager.self) private var fontManager
    @Environment(\.appTheme) private var theme

    @State private var showDocumentPicker = false
    @State private var showDeleteConfirm  = false
    @State private var errorMessage: String?
    @State private var showError = false

    // Local mirror so sliders can bind
    @State private var fontSize: CGFloat = FontManager.shared.editorFontSize
    @State private var lineSpacing: CGFloat = FontManager.shared.editorLineSpacing

    private let fontSizeRange: ClosedRange<CGFloat> = 12...28
    private let lineSpacingRange: ClosedRange<CGFloat> = 1.0...2.5
    private let systemBodySize: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize

    var body: some View {
        List {
            // ── Font size ─────────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("字体大小")
                        Spacer()
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                        if fontSize != systemBodySize {
                            Button("重置") {
                                fontSize = systemBodySize
                                fontManager.editorFontSize = systemBodySize
                            }
                            .font(.caption)
                            .foregroundColor(theme.colors.accent)
                        }
                    }
                    Slider(value: $fontSize, in: fontSizeRange, step: 1) {
                        Text("字体大小")
                    } minimumValueLabel: {
                        Text("12").font(.caption).foregroundColor(.secondary)
                    } maximumValueLabel: {
                        Text("28").font(.caption).foregroundColor(.secondary)
                    }
                    .tint(theme.colors.accent)
                    .onChange(of: fontSize) { _, v in
                        fontManager.editorFontSize = v
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("字体大小")
            } footer: {
                Text("调整编辑器正文字体大小，标题等元素将按比例缩放。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .listRowBackground(theme.colors.card)

            // ── Line spacing ──────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("行高倍数")
                        Spacer()
                        Text(String(format: "%.1f×", lineSpacing))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                        if lineSpacing != 1.0 {
                            Button("重置") {
                                lineSpacing = 1.0
                                fontManager.editorLineSpacing = 1.0
                            }
                            .font(.caption)
                            .foregroundColor(theme.colors.accent)
                        }
                    }
                    Slider(value: $lineSpacing, in: lineSpacingRange, step: 0.1) {
                        Text("行高")
                    } minimumValueLabel: {
                        Text("1×").font(.caption).foregroundColor(.secondary)
                    } maximumValueLabel: {
                        Text("2.5×").font(.caption).foregroundColor(.secondary)
                    }
                    .tint(theme.colors.accent)
                    .onChange(of: lineSpacing) { _, v in
                        fontManager.editorLineSpacing = v
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("行高")
            } footer: {
                Text("1.0 为紧凑行高，1.5 为舒适，2.0 为宽松。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .listRowBackground(theme.colors.card)

            // ── Live preview ──────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("预览")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("这是一段预览文字，展示当前字体大小与行高效果。\nThe quick brown fox jumps over the lazy dog.\n你好，世界！Hello, World! 0123456789")
                        .font(Font(fontManager.bodyFont()))
                        .lineSpacing((lineSpacing - 1.0) * fontSize)
                        .foregroundColor(theme.colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            } header: {
                Text("效果预览")
            }
            .listRowBackground(theme.colors.card)

            // ── Current font ──────────────────────────────────────────────────
            Section {
                if fontManager.hasCustomFont {
                    currentFontRow
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "textformat")
                            .foregroundColor(.secondary)
                        Text("当前使用系统默认字体")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("自定义字体文件")
            }
            .listRowBackground(theme.colors.card)

            // ── Upload ────────────────────────────────────────────────────────
            Section {
                Button {
                    showDocumentPicker = true
                } label: {
                    Label(
                        fontManager.hasCustomFont ? "替换字体文件" : "上传字体文件",
                        systemImage: "arrow.up.doc"
                    )
                    .foregroundColor(theme.colors.accent)
                }
            } footer: {
                Text("支持 TTF、OTF 格式。每次只能安装一个字体文件，上传后编辑器与预览将自动使用该字体。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .listRowBackground(theme.colors.card)
        }
        .onAppear {
            fontSize     = fontManager.editorFontSize
            lineSpacing  = fontManager.editorLineSpacing
        }
        .scrollContentBackground(.hidden)
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("字体管理")
        .navigationBarTitleDisplayMode(.inline)
        // Font file picker (TTF / OTF)
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [
                UTType(filenameExtension: "ttf") ?? .data,
                UTType(filenameExtension: "otf") ?? .data
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFontImport(result)
        }
        // Delete confirmation
        .confirmationDialog("删除自定义字体", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除字体", role: .destructive) {
                fontManager.deleteCustomFont()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后编辑器将恢复使用系统默认字体。")
        }
        // Error alert
        .alert("上传失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    // MARK: - Current Font Row

    private var currentFontRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已安装字体")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(fontManager.customFontFileName ?? "自定义字体")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.colors.primaryText)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Preview
            VStack(alignment: .leading, spacing: 5) {
                Text("预览")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("这是自定义字体的预览效果。")
                    .font(Font(fontManager.bodyFont()))
                    .foregroundColor(theme.colors.primaryText)
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(Font(fontManager.bodyFont()))
                    .foregroundColor(theme.colors.primaryText)
                Text("你好，世界！Hello, World! 0123456789")
                    .font(Font(fontManager.bodyFont()))
                    .foregroundColor(theme.colors.primaryText)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Import Handler

    private func handleFontImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            try fontManager.installFont(from: url)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
