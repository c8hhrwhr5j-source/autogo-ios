import UIKit

/// 多点找色结果
struct FindMultiColorResult {
    let x: Int
    let y: Int
}

/// 屏幕截图 —— 通过 Bridge ObjC 层动态加载 IOSurface/IOMobileFramebuffer 私有框架
final class ScreenCapture {
    static let shared = ScreenCapture()

    // MARK: - 流式捕获状态
    private var surface: IOSurfaceRef?
    private var captureTimer: DispatchSourceTimer?
    private let captureQueue = DispatchQueue(label: "autolua.capture", qos: .userInteractive)

    // 缓存帧 (线程安全)
    private let frameLock = NSLock()
    private var _cachedPixels: [UInt8] = []
    private var _cachedWidth: Int = 0
    private var _cachedHeight: Int = 0
    private var _cachedBytesPerRow: Int = 0
    private var _frameValid: Bool = false

    var width: Int  {
        let size = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        return Int(size.width * scale)
    }
    var height: Int {
        let size = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        return Int(size.height * scale)
    }

    // MARK: - 启动 / 停止流式捕获

    func startStreaming(fps: Int = 20) {
        guard captureTimer == nil else { return }

        // 尝试私有 API（IOMobileFramebuffer → IOSurface）
        if let surf = AutoLuaGetMainDisplaySurface()?.takeUnretainedValue() {
            surface = surf
            LogManager.shared.info("[ScreenCapture] 使用私有 API 获取屏幕 Surface")
        } else {
            LogManager.shared.info("[ScreenCapture] 私有 API 不可用，回退到公开 API (UIGraphicsImageRenderer)")
        }

        // 首帧读取（私有/公开 API 内部自动判断）
        _ = captureRawFrame()

        // 启动定时器持续捕获
        let interval = DispatchTimeInterval.nanoseconds(1_000_000_000 / fps)
        captureTimer = DispatchSource.makeTimerSource(queue: captureQueue)
        captureTimer?.schedule(deadline: .now(), repeating: interval)
        captureTimer?.setEventHandler { [weak self] in
            self?.captureRawFrame()
        }
        captureTimer?.resume()

        LogManager.shared.info("[ScreenCapture] 流式截图已启动 \(fps)fps, \(width)x\(height)")
    }

    func stopStreaming() {
        captureTimer?.cancel()
        captureTimer = nil
        surface = nil
        frameLock.withLock {
            _frameValid = false
            _cachedPixels = []
        }
    }

    var isStreaming: Bool { captureTimer != nil }

    // MARK: - 帧获取

    func capture() -> (pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int)? {
        return frameLock.withLock {
            guard _frameValid else { return nil }
            return (_cachedPixels, _cachedWidth, _cachedHeight, _cachedBytesPerRow)
        }
    }

    func captureFresh() -> (pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int)? {
        captureRawFrame()
        return capture()
    }

    func captureWait(timeout: TimeInterval = 1.0) -> (pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int)? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = capture() { return result }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    func captureImage() -> UIImage? {
        guard let surf = surface else { return nil }
        // 每次调用 Bridge 生成新 CGImage（稳妥，但不如缓存高效）
        guard let cgImage = AutoLuaCreateImageFromSurface(surf) else { return nil }
        return UIImage(cgImage: cgImage.takeRetainedValue())
    }

    // MARK: - 单点找色

    func findColor(r: Int, g: Int, b: Int, tolerance: Int = 5,
                   maxResults: Int = 500) -> [(x: Int, y: Int)] {
        guard let (pixels, w, h, bpr) = capture() else { return [] }
        return findColorInBuffer(pixels: pixels, width: w, height: h, bytesPerRow: bpr,
                                  r: r, g: g, b: b, tolerance: tolerance,
                                  region: nil, maxResults: maxResults)
    }

    func findColorInRegion(r: Int, g: Int, b: Int, tolerance: Int = 5,
                            region: (x: Int, y: Int, width: Int, height: Int),
                            maxResults: Int = 500) -> [(x: Int, y: Int)] {
        guard let (pixels, w, h, bpr) = capture() else { return [] }
        let rx = max(0, region.x)
        let ry = max(0, region.y)
        let rw = min(region.width, w - rx)
        let rh = min(region.height, h - ry)
        return findColorInBuffer(pixels: pixels, width: w, height: h, bytesPerRow: bpr,
                                  r: r, g: g, b: b, tolerance: tolerance,
                                  region: (rx, ry, rw, rh), maxResults: maxResults)
    }

    // MARK: - 多点找色

    func findMultiColors(
        firstColor: (r: Int, g: Int, b: Int),
        tolerance: Int = 5,
        relativePoints: [(dx: Int, dy: Int, r: Int, g: Int, b: Int)],
        region: (x: Int, y: Int, width: Int, height: Int)? = nil,
        maxResults: Int = 100
    ) -> [FindMultiColorResult] {
        guard !relativePoints.isEmpty else { return [] }
        guard let (pixels, w, h, bpr) = capture() else { return [] }

        let candidates = findColorInBuffer(
            pixels: pixels, width: w, height: h, bytesPerRow: bpr,
            r: firstColor.r, g: firstColor.g, b: firstColor.b,
            tolerance: tolerance, region: region, maxResults: maxResults * 3
        )

        var results: [FindMultiColorResult] = []
        for candidate in candidates {
            var allMatch = true
            for rp in relativePoints {
                let cx = candidate.x + rp.dx
                let cy = candidate.y + rp.dy
                guard cx >= 0, cx < w, cy >= 0, cy < h else { allMatch = false; break }
                let offset = cy * bpr + cx * 4
                let pr = Int(pixels[offset + 2])
                let pg = Int(pixels[offset + 1])
                let pb = Int(pixels[offset])
                if abs(pr - rp.r) > tolerance || abs(pg - rp.g) > tolerance ||
                   abs(pb - rp.b) > tolerance { allMatch = false; break }
            }
            if allMatch {
                results.append(FindMultiColorResult(x: candidate.x, y: candidate.y))
                if results.count >= maxResults { break }
            }
        }
        return results
    }

    func findMultiColorsStr(firstColorHex: String, pointsStr: String,
                             tolerance: Int = 5,
                             region: (x: Int, y: Int, width: Int, height: Int)? = nil,
                             maxResults: Int = 100) -> [FindMultiColorResult] {
        guard let fc = parseHex(firstColorHex) else { return [] }
        var rps: [(dx: Int, dy: Int, r: Int, g: Int, b: Int)] = []
        for part in pointsStr.split(separator: ",") {
            let comps = part.split(separator: "|")
            guard comps.count == 3,
                  let dx = Int(comps[0]), let dy = Int(comps[1]),
                  let c = parseHex(String(comps[2])) else { continue }
            rps.append((dx, dy, c.r, c.g, c.b))
        }
        return findMultiColors(firstColor: fc, tolerance: tolerance,
                                relativePoints: rps, region: region, maxResults: maxResults)
    }

    // MARK: - 取色

    func getPixelColor(x: Int, y: Int) -> (r: Int, g: Int, b: Int)? {
        guard let (pixels, w, h, bpr) = capture(),
              x >= 0, x < w, y >= 0, y < h else { return nil }
        let offset = y * bpr + x * 4
        return (Int(pixels[offset + 2]), Int(pixels[offset + 1]), Int(pixels[offset]))
    }

    var screenSize: (width: Int, height: Int) { (width, height) }

    // MARK: - 内部实现

    /// 通过 Bridge 的 AutoLuaGetPixelData 读取全屏像素（优先私有 API，失败回退到公开 API）
    @discardableResult
    private func captureRawFrame() -> Bool {
        // 方案1：尝试私有 API（IOMobileFramebuffer → IOSurface）
        if let surf = surface {
            let w = AutoLuaSurfaceGetWidth(surf)
            let h = AutoLuaSurfaceGetHeight(surf)
            if w > 0, h > 0 {
                let fullRect = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
                if let pixelData = AutoLuaGetPixelData(surf, fullRect) as Data? {
                    let pixels = [UInt8](pixelData)
                    let bpr = Int(w) * 4
                    frameLock.withLock {
                        _cachedPixels = pixels
                        _cachedWidth = Int(w)
                        _cachedHeight = Int(h)
                        _cachedBytesPerRow = bpr
                        _frameValid = true
                    }
                    return true
                }
            }
        }

        // 方案2：回退到公开 API — UIGraphicsImageRenderer 截取窗口，再统一转 BGRA
        guard let window = UIApplication.shared.windows.first else { return false }
        let size = window.bounds.size
        let scale = UIScreen.main.scale
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        guard w > 0, h > 0 else { return false }

        let bpr = w * 4
        var pixels: [UInt8] = []
        var success = false

        DispatchQueue.main.sync {
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            guard let cgImage = image.cgImage else { return }

            // 创建 BGRA 格式上下文，绘制 CGImage 进去，保证像素格式一致
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            guard let context = CGContext(
                data: nil,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bpr,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let raw = context.data?.assumingMemoryBound(to: UInt8.self) else { return }

            pixels = Array(UnsafeBufferPointer(start: raw, count: w * h * 4))
            success = true
        }

        guard success else { return false }

        frameLock.withLock {
            _cachedPixels = pixels
            _cachedWidth = w
            _cachedHeight = h
            _cachedBytesPerRow = bpr
            _frameValid = true
        }
        return true
    }

    // MARK: - 像素缓冲区中找色

    private func findColorInBuffer(
        pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int,
        r: Int, g: Int, b: Int, tolerance: Int,
        region: (x: Int, y: Int, width: Int, height: Int)?,
        maxResults: Int
    ) -> [(x: Int, y: Int)] {
        let tolx = tolerance
        let startX = region?.x ?? 0
        let startY = region?.y ?? 0
        let endX = min(startX + (region?.width ?? width), width)
        let endY = min(startY + (region?.height ?? height), height)

        var results: [(x: Int, y: Int)] = []
        results.reserveCapacity(min(maxResults, 100))

        for y in startY..<endY {
            for x in startX..<endX {
                let offset = y * bytesPerRow + x * 4
                let pr = Int(pixels[offset + 2])  // BGRA → R
                let pg = Int(pixels[offset + 1])  // BGRA → G
                let pb = Int(pixels[offset])      // BGRA → B
                if abs(pr - r) <= tolx && abs(pg - g) <= tolx && abs(pb - b) <= tolx {
                    results.append((x, y))
                    if results.count >= maxResults { return results }
                }
            }
        }
        return results
    }

    // MARK: - 工具

    private func parseHex(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 6 else { return nil }
        var val: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&val) else { return nil }
        return (Int((val >> 16) & 0xFF), Int((val >> 8) & 0xFF), Int(val & 0xFF))
    }
}
