import Foundation
import UIKit
import Vision

// MARK: - OCR 文字识别引擎

/// 基于 Vision 框架进行屏幕文字识别
/// iOS 13+ 可用，无需额外依赖
@available(iOS 13.0, *)
final class OCREngine {

    static let shared = OCREngine()

    private var defaultLanguages: [String] = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]

    // MARK: - 识别请求

    /// OCR 结果结构
    struct OCRResult {
        let text: String                    // 所有识别的文字（换行分隔）
        let blocks: [TextBlock]            // 文字块列表
        let confidence: Float              // 平均置信度

        struct TextBlock {
            let text: String               // 文字内容
            let boundingBox: CGRect        // 归一化边界框（0-1）
            let confidence: Float          // 置信度（0-1）
            let cornerPoints: [CGPoint]    // 四个角点（归一化）
        }

        /// 所有识别文字拼接
        var allText: String {
            return blocks.map { $0.text }.joined(separator: "\n")
        }

        /// 是否包含指定文字
        func contains(_ keyword: String, caseSensitive: Bool = false) -> Bool {
            if caseSensitive {
                return text.contains(keyword)
            }
            return text.localizedCaseInsensitiveContains(keyword)
        }

        /// 查找包含指定文字的文字块坐标区域（屏幕坐标）
        func findTextRegion(_ keyword: String, in imageSize: CGSize) -> [CGRect] {
            var regions: [CGRect] = []
            for block in blocks {
                if block.text.localizedCaseInsensitiveContains(keyword) {
                    let rect = CGRect(
                        x: block.boundingBox.origin.x * imageSize.width,
                        y: (1 - block.boundingBox.origin.y - block.boundingBox.height) * imageSize.height,
                        width: block.boundingBox.width * imageSize.width,
                        height: block.boundingBox.height * imageSize.height
                    )
                    regions.append(rect)
                }
            }
            return regions
        }

        /// 获取指定文字的中心坐标（用于点击）
        func findTextCenter(_ keyword: String, in imageSize: CGSize) -> CGPoint? {
            guard let region = findTextRegion(keyword, in: imageSize).first else {
                return nil
            }
            return CGPoint(x: region.midX, y: region.midY)
        }
    }

    private init() {}

    // MARK: - 公开方法

    /// 识别屏幕上的所有文字（自动截屏）
    func recognizeScreen(
        region: CGRect? = nil,
        completion: @escaping (OCRResult?) -> Void
    ) {
        guard let screenshot = ScreenCapture.shared.capture() else {
            completion(nil)
            return
        }
        recognize(image: screenshot, region: region, completion: completion)
    }

    /// 识别指定图像中的文字
    func recognize(
        image: UIImage,
        region: CGRect? = nil,
        completion: @escaping (OCRResult?) -> Void
    ) {
        let requestHandler: VNImageRequestHandler

        if let cgImage = image.cgImage {
            requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        } else if let ciImage = image.ciImage {
            requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        } else {
            completion(nil)
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            let result = self.parseTextRecognitionResult(request: request, error: error)
            completion(result)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = defaultLanguages
        if let region = region {
            request.regionOfInterest = region
        }

        do {
            try requestHandler.perform([request])
        } catch {
            print("[OCR] 识别失败: \(error.localizedDescription)")
            completion(nil)
        }
    }

    /// 同步识别（简单场景使用）
    func recognizeSync(image: UIImage, region: CGRect? = nil) -> OCRResult? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: OCRResult? = nil

        recognize(image: image, region: region) { r in
            result = r
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10.0)
        return result
    }

    /// 快速查找屏幕上包含指定文字的位置
    func findText(
        _ keyword: String,
        tolerance: Float = 0.6,
        completion: @escaping (CGPoint?) -> Void
    ) {
        recognizeScreen { result in
            guard let result = result else {
                completion(nil)
                return
            }

            let screenSize = UIScreen.main.bounds.size
            let imageSize = CGSize(width: screenSize.width * UIScreen.main.scale,
                                   height: screenSize.height * UIScreen.main.scale)

            if let center = result.findTextCenter(keyword, in: imageSize) {
                completion(CGPoint(x: center.x / UIScreen.main.scale,
                                   y: center.y / UIScreen.main.scale))
                return
            }

            // 如果精确匹配未找到，尝试模糊匹配
            for block in result.blocks {
                let similarity = self.stringSimilarity(block.text, keyword)
                if similarity >= tolerance {
                    let rect = CGRect(
                        x: block.boundingBox.origin.x * imageSize.width,
                        y: (1 - block.boundingBox.origin.y - block.boundingBox.height) * imageSize.height,
                        width: block.boundingBox.width * imageSize.width,
                        height: block.boundingBox.height * imageSize.height
                    )
                    completion(CGPoint(x: rect.midX / UIScreen.main.scale,
                                       y: rect.midY / UIScreen.main.scale))
                    return
                }
            }

            completion(nil)
        }
    }

    /// 获取屏幕上所有文字
    func getAllText(completion: @escaping (String) -> Void) {
        recognizeScreen { result in
            completion(result?.allText ?? "")
        }
    }

    // MARK: - 处理回调

    private func parseTextRecognitionResult(request: VNRequest, error: Error?) -> OCRResult? {
        if let error = error {
            print("[OCR] 错误: \(error.localizedDescription)")
            return OCRResult(text: "", blocks: [], confidence: 0)
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            return OCRResult(text: "", blocks: [], confidence: 0)
        }

        var blocks: [OCRResult.TextBlock] = []
        var totalConfidence: Float = 0

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }

            let text = candidate.string
            let confidence = Float(candidate.confidence)
            totalConfidence += confidence

            let block = OCRResult.TextBlock(
                text: text,
                boundingBox: observation.boundingBox,
                confidence: confidence,
                cornerPoints: [
                    observation.topLeft,
                    observation.topRight,
                    observation.bottomRight,
                    observation.bottomLeft
                ].map { CGPoint(x: $0.x, y: $0.y) }
            )
            blocks.append(block)
        }

        let avgConfidence = blocks.isEmpty ? 0 : totalConfidence / Float(blocks.count)
        let allText = blocks.map { $0.text }.joined(separator: "\n")

        return OCRResult(text: allText, blocks: blocks, confidence: avgConfidence)
    }

    // MARK: - 模糊匹配

    private func stringSimilarity(_ s1: String, _ s2: String) -> Float {
        let a = s1.lowercased()
        let b = s2.lowercased()

        if a == b { return 1.0 }
        if a.contains(b) || b.contains(a) { return 0.9 }

        // 简单的字符级编辑距离
        let (shorter, longer) = a.count < b.count ? (a, b) : (b, a)
        if shorter.isEmpty { return 0.0 }

        var matches = 0
        for char in shorter {
            if longer.contains(char) {
                matches += 1
            }
        }

        return Float(matches) / Float(max(a.count, b.count))
    }
}
