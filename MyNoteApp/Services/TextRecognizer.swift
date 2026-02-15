import Vision
import UIKit

/// 文本识别服务 - 使用 Vision 框架从图片中提取文字
class TextRecognizer {
    
    /// 从单张图片中识别文字
    static func recognizeText(from image: UIImage, completion: @escaping (String) -> Void) {
        guard let cgImage = image.cgImage else {
            DispatchQueue.main.async { completion("") }
            return
        }
        
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async { completion("") }
                return
            }
            
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            
            DispatchQueue.main.async {
                completion(text)
            }
        }
        
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en"]
        request.usesLanguageCorrection = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    /// 从多张图片中识别文字，合并结果
    static func recognizeText(from images: [UIImage], completion: @escaping (String) -> Void) {
        guard !images.isEmpty else {
            DispatchQueue.main.async { completion("") }
            return
        }
        
        var allTexts: [String] = Array(repeating: "", count: images.count)
        let group = DispatchGroup()
        
        for (index, image) in images.enumerated() {
            group.enter()
            recognizeText(from: image) { text in
                allTexts[index] = text
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(allTexts.filter { !$0.isEmpty }.joined(separator: "\n\n"))
        }
    }
}
