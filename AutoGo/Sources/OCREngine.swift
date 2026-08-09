import UIKit
import Vision

class OCREngine {
    static let shared = OCREngine()
    private init() {}

    func recognizeSync() -> String? {
        guard let image = ScreenCapture.shared.capture() else { return nil }
        return recognize(image: image)
    }

    func recognize(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.recognizeSync()
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func recognize(image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }

        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String?

        let request = VNRecognizeTextRequest { request, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            let texts = observations.compactMap { $0.topCandidates(1).first?.string }
            resultText = texts.joined(separator: "\n")
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        semaphore.wait(timeout: .now() + 5.0)
        return resultText
    }
}
