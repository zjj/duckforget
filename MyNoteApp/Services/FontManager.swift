import Foundation
import UIKit
import CoreText

// MARK: - FontManager

/// Manages a single user-installed custom font (TTF / OTF).
/// The registered font is persisted across launches and made available to
/// all views that read `FontManager.shared`.
@Observable
final class FontManager {
    static let shared = FontManager()

    private let fontFileNameKey      = "CustomFontFileName"
    private let fontPSNameKey         = "CustomFontPSName"
    private let editorFontSizeKey     = "EditorFontSize"
    private let editorLineSpacingKey  = "EditorLineSpacing"

    /// Display name (original file name) of the installed font, or nil.
    private(set) var customFontFileName: String?

    /// CoreText / UIKit PostScript name used to instantiate `UIFont`, or nil.
    private(set) var customFontPostScriptName: String?

    /// True when a custom font has been successfully installed.
    var hasCustomFont: Bool { customFontPostScriptName != nil }

    /// Editor body font size in points. Default is the system body text size.
    var editorFontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(editorFontSize), forKey: editorFontSizeKey) }
    }

    /// Line height multiplier for the editor (1.0 = normal, 1.5 = 50 % extra). Default 1.0.
    var editorLineSpacing: CGFloat {
        didSet { UserDefaults.standard.set(Double(editorLineSpacing), forKey: editorLineSpacingKey) }
    }

    // MARK: - Font Accessors

    /// Returns a `UIFont` for body text.
    /// Pass an explicit `size` to override the managed font size (e.g. for scaled headings).
    /// With no argument, the managed `editorFontSize` is used.
    func bodyFont(size: CGFloat? = nil) -> UIFont {
        let sz = size ?? editorFontSize
        if let psName = customFontPostScriptName,
           let font = UIFont(name: psName, size: sz) {
            return font
        }
        return UIFont.systemFont(ofSize: sz)
    }

    /// UIFont using the custom typeface (or system fallback) at a chosen UIFont.TextStyle point size.
    /// Uses the text-style's standard point size regardless of `editorFontSize`.
    func bodyFont(textStyle: UIFont.TextStyle) -> UIFont {
        bodyFont(size: UIFont.preferredFont(forTextStyle: textStyle).pointSize)
    }

    // MARK: - Init

    private init() {
        let defaultSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let storedSize  = UserDefaults.standard.double(forKey: editorFontSizeKey)
        self.editorFontSize = storedSize > 0 ? CGFloat(storedSize) : defaultSize

        let storedSpacing = UserDefaults.standard.double(forKey: editorLineSpacingKey)
        self.editorLineSpacing = storedSpacing > 0 ? CGFloat(storedSpacing) : 1.0

        let storedPSName   = UserDefaults.standard.string(forKey: fontPSNameKey)
        let storedFileName = UserDefaults.standard.string(forKey: fontFileNameKey)

        guard let fileName = storedFileName, let psName = storedPSName else { return }

        let url = fontStorageURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            clearUserDefaults()
            return
        }

        // Re-register the font for this process session
        var cfError: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError)

        // Verify the font is actually loadable after registration
        guard UIFont(name: psName, size: 16) != nil else {
            clearUserDefaults()
            return
        }

        customFontFileName       = fileName
        customFontPostScriptName = psName
    }

    // MARK: - Install

    /// Copies `sourceURL` into app-private storage, registers the font with CoreText,
    /// and updates observable state.  Throws `FontError` on failure.
    func installFont(from sourceURL: URL) throws {
        let fileName = sourceURL.lastPathComponent
        let destURL  = fontStorageURL(for: fileName)

        // Unregister / delete any previously installed font first
        removeCurrentFont()

        // Copy to private storage
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        // Extract PostScript name from font binary
        guard
            let data     = try? Data(contentsOf: destURL),
            let provider = CGDataProvider(data: data as CFData),
            let cgFont   = CGFont(provider),
            let psName   = cgFont.postScriptName as String?
        else {
            try? FileManager.default.removeItem(at: destURL)
            throw FontError.invalidFontFile
        }

        // Register with CoreText
        var cfError: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(destURL as CFURL, .process, &cfError)
        if let err = cfError?.takeRetainedValue() {
            try? FileManager.default.removeItem(at: destURL)
            throw err as Error
        }

        // Final sanity-check: UIKit must be able to instantiate the font
        guard UIFont(name: psName, size: 16) != nil else {
            try? FileManager.default.removeItem(at: destURL)
            throw FontError.registrationFailed
        }

        // Persist
        UserDefaults.standard.set(fileName, forKey: fontFileNameKey)
        UserDefaults.standard.set(psName,   forKey: fontPSNameKey)
        customFontFileName       = fileName
        customFontPostScriptName = psName
    }

    // MARK: - Delete

    /// Unregisters and deletes the installed custom font.
    func deleteCustomFont() {
        removeCurrentFont()
        clearUserDefaults()
        customFontFileName       = nil
        customFontPostScriptName = nil
    }

    // MARK: - Private Helpers

    private func removeCurrentFont() {
        if let psName = customFontPostScriptName,
           let cgFont = CGFont(psName as CFString) {
            var cfError: Unmanaged<CFError>?
            CTFontManagerUnregisterGraphicsFont(cgFont, &cfError)
        }
        if let fileName = customFontFileName {
            try? FileManager.default.removeItem(at: fontStorageURL(for: fileName))
        }
    }

    private func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: fontFileNameKey)
        UserDefaults.standard.removeObject(forKey: fontPSNameKey)
        // intentionally does NOT reset font size / line spacing when a font file is deleted
    }

    private func fontStorageDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir  = docs.appendingPathComponent("CustomFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fontStorageURL(for fileName: String) -> URL {
        fontStorageDirectory().appendingPathComponent(fileName)
    }
}

// MARK: - FontError

enum FontError: LocalizedError {
    case invalidFontFile
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .invalidFontFile:
            return "无法读取字体文件，请确认格式正确（TTF 或 OTF）。"
        case .registrationFailed:
            return "字体注册失败，该字体文件可能已损坏或格式不受支持。"
        }
    }
}
