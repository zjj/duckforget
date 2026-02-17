import SwiftUI

/// 导出备忘录的操作表
struct ExportSheet: View {
    let note: NoteItem
    @Environment(NoteStore.self) var noteStore
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var exportedItems: [Any] = []

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("导出格式")) {
                    // 导出为纯文本
                    Button {
                        let text = noteStore.exportAsText(note)
                        exportedItems = [text]
                        showShareSheet = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("纯文本")
                                    .foregroundColor(.primary)
                                Text("导出为 .txt 格式")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.plaintext")
                                .foregroundColor(.blue)
                        }
                    }

                    // 导出为 PDF
                    Button {
                        let pdfData = noteStore.exportAsPDF(note)
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("\(note.preview).pdf")
                        try? pdfData.write(to: tempURL)
                        exportedItems = [tempURL]
                        showShareSheet = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PDF 文档")
                                    .foregroundColor(.primary)
                                Text("导出为 .pdf 格式")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.richtext")
                                .foregroundColor(.red)
                        }
                    }
                }

                Section(header: Text("预览")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.preview)
                            .font(.headline)
                        Text(note.updatedAt.formattedFull)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(note.content.prefix(200) + (note.content.count > 200 ? "..." : ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(6)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("导出备忘录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityViewController(activityItems: exportedItems)
            }
        }
    }
}

/// UIActivityViewController 的 SwiftUI 包装
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController, context: Context
    ) {}
}
