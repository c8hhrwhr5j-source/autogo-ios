import UIKit

class ScreenCapture {
    static let shared = ScreenCapture()

    var cachedWidth: Int = 0
    var cachedHeight: Int = 0

    private init() {}

    func capture() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { ctx in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        cachedWidth = Int(image.size.width * image.scale)
        cachedHeight = Int(image.size.height * image.scale)

        return image
    }
}
