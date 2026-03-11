import Foundation
import NaturalLanguage

// MARK: - Tone-stripping table
// Maps accented vowels (with tone marks) to their plain ASCII equivalents.
private let toneMap: [Character: Character] = [
    // a
    "ā": "a", "á": "a", "ǎ": "a", "à": "a",
    // e
    "ē": "e", "é": "e", "ě": "e", "è": "e",
    // i
    "ī": "i", "í": "i", "ǐ": "i", "ì": "i",
    // o
    "ō": "o", "ó": "o", "ǒ": "o", "ò": "o",
    // u
    "ū": "u", "ú": "u", "ǔ": "u", "ù": "u",
    // ü
    "ǖ": "v", "ǘ": "v", "ǚ": "v", "ǜ": "v", "ü": "v",
]

/// Remove tone marks from a pinyin string, e.g. "zhōng" → "zhong"
private func stripTones(_ pinyin: String) -> String {
    var result = ""
    result.reserveCapacity(pinyin.count)
    for ch in pinyin {
        if let plain = toneMap[ch] {
            result.append(plain)
        } else {
            result.append(ch)
        }
    }
    return result
}

// MARK: - PinyinConverter

enum PinyinConverter {
    
    /// Lazy-loaded pinyin dictionary from JSON resource
    private static let pinyinDict: [Int: String] = {
        guard let url = Bundle.main.url(forResource: "pinyin_dict", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            print("⚠️ Failed to load pinyin_dict.json")
            return [:]
        }
        
        // Convert string keys to Int
        var dict: [Int: String] = [:]
        for (key, value) in json {
            if let code = Int(key) {
                dict[code] = value
            }
        }
        return dict
    }()

    /// Convert a string containing Chinese characters to space-separated pinyin (no tones).
    /// Non-Chinese characters are kept as-is.
    /// Each Chinese character is converted to its first (most common) pinyin reading.
    ///
    /// Example: "你好world" → "ni hao world"
    static func toPinyin(_ text: String) -> String {
        var parts: [String] = []
        var nonChineseBuf = ""

        for scalar in text.unicodeScalars {
            let code = Int(scalar.value)
            if let raw = pinyinDict[code] {
                // flush any buffered non-Chinese text
                if !nonChineseBuf.isEmpty {
                    parts.append(nonChineseBuf)
                    nonChineseBuf = ""
                }
                // Take the first reading (before any comma)
                let reading: String
                if let commaIdx = raw.firstIndex(of: ",") {
                    reading = String(raw[raw.startIndex..<commaIdx])
                } else {
                    reading = raw
                }
                parts.append(stripTones(reading))
            } else {
                // Accumulate non-Chinese characters
                nonChineseBuf.append(Character(scalar))
            }
        }
        if !nonChineseBuf.isEmpty {
            parts.append(nonChineseBuf)
        }
        return parts.joined(separator: " ")
    }

    /// Build a search-friendly pinyin string for indexing.
    /// Uses word tokenization to separate words with spaces.
    /// Returns empty string if no Chinese characters found.
    static func pinyinForSearch(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.simplifiedChinese)
        
        var wordPinyinParts: [String] = []
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            var pinyinForWord = ""
            
            for scalar in word.unicodeScalars {
                let code = Int(scalar.value)
                if let raw = pinyinDict[code] {
                    let reading: String
                    if let commaIdx = raw.firstIndex(of: ",") {
                        reading = String(raw[raw.startIndex..<commaIdx])
                    } else {
                        reading = raw
                    }
                    pinyinForWord += stripTones(reading)
                }
            }
            
            if !pinyinForWord.isEmpty {
                wordPinyinParts.append(pinyinForWord)
            }
            return true
        }
        
        return wordPinyinParts.joined(separator: " ")
    }
}
