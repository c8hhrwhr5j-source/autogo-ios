import UIKit
import CoreVideo

// MARK: - IOMobileFramebuffer 私有 API
@_silgen_name("IOMobileFramebufferGetMainDisplay")
func IOMobileFramebufferGetMainDisplay(_: UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32

@_silgen_name("IOMobileFramebufferOpen")
func IOMobileFramebufferOpen(_: UnsafeMutableRawPointer?, _: UInt32, _: UnsafeMutablePointer<UnsafeMutableRawPointer?>, _: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("IOMobileFramebufferGetLayerDefaultSurface")
func IOMobileFramebufferGetLayerDefaultSurface(_: UnsafeMutableRawPointer?, _: Int32, _: UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32

@_silgen_name("IOSurfaceLock")
func IOSurfaceLock(_: UnsafeMutableRawPointer?, _: UInt32, _: UnsafeMutablePointer<UInt32>?) -> Int32

@_silgen_name("IOSurfaceUnlock")
func IOSurfaceUnlock(_: UnsafeMutableRawPointer?, _: UInt32, _: UnsafeMutablePointer<UInt32>?) -> Int32

@_silgen_name("IOSurfaceGetBaseAddress")
func IOSurfaceGetBaseAddress(_: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

@_silgen_name("IOSurfaceGetWidth")
func IOSurfaceGetWidth(_: UnsafeMutableRawPointer?) -> Int

@_silgen_name("IOSurfaceGetHeight")
func IOSurfaceGetHeight(_: UnsafeMutableRawPointer?) -> Int

@_silgen_name("IOSurfaceGetBytesPerRow")
func IOSurfaceGetBytesPerRow(_: UnsafeMutableRawPointer?) -> Int

// MARK: - 多点找色结果
struct FindMultiColorResult {
    let x: Int
    let y: Int
}

/// 屏幕截图 —— 流式后台捕获 + 多点找色
/// 核心机制参考 AutoGo 的 RawFrameSetCallback + RawFrameStart
final class ScreenCapture {
    static let shared = ScreenCapture()

    // MARK: - 流式捕获状态
    private var fbConnection: UnsafeMutableRawPointer?
    private var surface: UnsafeMutableRawPointer?
    private var captureTimer: DispatchSourceTimer?
    private let captureQueue = DispatchQueue(label: "autogo.capture", qos: .userInteractive)

    // 缓存帧 (线程安全)
    private let frameLock = NSLock()
    private var _cachedPixels: [UInt8] = []
    private var _cachedWidth: Int = 0
    private var _cachedHeight: Int = 0
    private var _cachedBytesPerRow: Int = 0
    private var _frameValid: Bool = false

    var width: Int { frameLock.withLock { _cachedWidth } }
    var height: Int { frameLock.withLock { _cachedHeight } }

    // MARK: - 启动 / 停止流式捕获

    /// 启动流式捕获 (AutoGo: RawFrameStart)
    func startStreaming(fps: Int = 20) {
        guard fbConnection == nil else { return }

        // 1. 打开 IOMobileFramebuffer
        var display: UnsafeMutableRawPointer?
        guard IOMobileFramebufferGetMainDisplay(&display) == 0, let disp = display else {
            print("[ScreenCapture] Failed to get main display")
            return
        }

        var connection: UnsafeMutableRawPointer?
        guard IOMobileFramebufferOpen(disp, 0, &connection, nil) == 0, let conn = connection else {
            print("[ScreenCapture] Failed to open framebuffer")
            return
        }
        fbConnection = conn

        // 2. 获取 IOSurface
        var surf: UnsafeMutableRawPointer?
        guard IOMobileFramebufferGetLayerDefaultSurface(conn, 0, &surf) == 0, let s = surf else {
            print("[ScreenCapture] Failed to get surface")
            return
        }
        surface = s

        // 3. 读取一次获取尺寸
        _ = captureRawFrame()

        // 4. 启动定时器，持续捕获 (AutoGo: RawFrameStart → 回调循环)
        let interval = DispatchTimeInterval.nanoseconds(1_000_000_000 / fps)
        captureTimer = DispatchSource.makeTimerSource(queue: captureQueue)
        captureTimer?.schedule(deadline: .now(), repeating: interval)
        captureTimer?.setEventHandler { [weak self] in
            self?.captureRawFrame()
        }
        captureTimer?.resume()

        print("[ScreenCapture] Streaming started at \(fps) FPS, size=\(width)x\(height)")
    }

    /// 停止流式捕获
    func stopStreaming() {
        captureTimer?.cancel()
        captureTimer = nil
        fbConnection = nil
        surface = nil
        frameLock.withLock {
            _frameValid = false
            _cachedPixels = []
        }
    }

    /// 是否正在流式捕获
    var isStreaming: Bool { captureTimer != nil }

    // MARK: - 帧获取 (AutoGo: CaptureScreen → 从回调缓存取)

    /// 获取最新缓存帧 (零延迟，直接返回缓存)
    /// 必须先调用 startStreaming() 启动流式捕获
    func capture() -> (pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int)? {
        return frameLock.withLock {
            guard _frameValid else { return nil }
            return (_cachedPixels, _cachedWidth, _cachedHeight, _cachedBytesPerRow)
        }
    }

    /// 强制立即捕获一帧 (不回缓存，适合需要最新画面的场景)
    func captureFresh() -> (pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int)? {
        captureRawFrame()
        return frameLock.withLock {
            guard _frameValid else { return nil }
            return (_cachedPixels, _cachedWidth, _cachedHeight, _cachedBytesPerRow)
        }
    }

    /// 等待并获取一帧
    func captureWait(timeout: TimeInterval = 1.0) -> (pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int)? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = capture() { return result }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    /// 返回 UIImage (调试/OCR 用)
    func captureImage() -> UIImage? {
        guard let (pixels, w, h, bpr) = capture() else { return nil }
        return makeUIImage(pixels: pixels, width: w, height: h, bytesPerRow: bpr)
    }

    // MARK: - 单点找色 (已有)

    /// 找色，返回所有匹配点 (最多 maxResults 个)
    func findColor(r: Int, g: Int, b: Int, tolerance: Int = 5,
                   maxResults: Int = 500) -> [(x: Int, y: Int)] {
        guard let (pixels, w, h, bpr) = capture() else { return [] }
        return findColorInBuffer(pixels: pixels, width: w, height: h, bytesPerRow: bpr,
                                  r: r, g: g, b: b, tolerance: tolerance,
                                  region: nil, maxResults: maxResults)
    }

    /// 指定区域内找色
    func findColorInRegion(r: Int, g: Int, b: Int, tolerance: Int = 5,
                            region: (x: Int, y: Int, width: Int, height: Int),
                            maxResults: Int = 500) -> [(x: Int, y: Int)] {
        guard let (pixels, w, h, bpr) = capture() else { return [] }
        // 裁剪区域
        let rx = max(0, region.x)
        let ry = max(0, region.y)
        let rw = min(region.width, w - rx)
        let rh = min(region.height, h - ry)
        let clampedRegion = (x: rx, y: ry, width: rw, height: rh)
        return findColorInBuffer(pixels: pixels, width: w, height: h, bytesPerRow: bpr,
                                  r: r, g: g, b: b, tolerance: tolerance,
                                  region: clampedRegion, maxResults: maxResults)
    }

    // MARK: - 多点找色 (AutoGo: FindMultiColors)

    /// 多点相对坐标找色
    ///
    /// - Parameters:
    ///   - firstColor: (r, g, b) 首色
    ///   - tolerance: 首色容差
    ///   - relativePoints: 相对坐标点 [(dx, dy, r, g, b)]，dx/dy 相对于首色位置
    ///   - region: 可选搜索区域
    ///   - maxResults: 最大结果数
    ///
    /// - Returns: 所有匹配的首色坐标
    ///
    /// 示例：找红色按钮上的白色文字
    /// ```swift
    /// findMultiColors(firstColor: (255,0,0), tolerance: 5,
    ///     relativePoints: [(10, 5, 255, 255, 255), (-5, 8, 255, 255, 255)])
    /// ```
    func findMultiColors(
        firstColor: (r: Int, g: Int, b: Int),
        tolerance: Int = 5,
        relativePoints: [(dx: Int, dy: Int, r: Int, g: Int, b: Int)],
        region: (x: Int, y: Int, width: Int, height: Int)? = nil,
        maxResults: Int = 100
    ) -> [FindMultiColorResult] {
        guard !relativePoints.isEmpty else { return [] }
        guard let (pixels, w, h, bpr) = capture() else { return [] }

        // 先找首色候选点
        let candidates = findColorInBuffer(
            pixels: pixels, width: w, height: h, bytesPerRow: bpr,
            r: firstColor.r, g: firstColor.g, b: firstColor.b,
            tolerance: tolerance, region: region, maxResults: maxResults * 3
        )

        // 验证每个候选点的相对位置
        var results: [FindMultiColorResult] = []
        for candidate in candidates {
            var allMatch = true
            for rp in relativePoints {
                let cx = candidate.x + rp.dx
                let cy = candidate.y + rp.dy
                guard cx >= 0, cx < w, cy >= 0, cy < h else { allMatch = false; break }
                let offset = cy * bpr + cx * 4
                let pr = Int(pixels[offset + 2])  // BGRA → R
                let pg = Int(pixels[offset + 1])
                let pb = Int(pixels[offset])
                if abs(pr - rp.r) > tolerance ||
                   abs(pg - rp.g) > tolerance ||
                   abs(pb - rp.b) > tolerance {
                    allMatch = false
                    break
                }
            }
            if allMatch {
                results.append(FindMultiColorResult(x: candidate.x, y: candidate.y))
                if results.count >= maxResults { break }
            }
        }
        return results
    }

    // MARK: - 字符串格式多点找色 (AutoGo: FindMultiColors("0|0|FF0000,10|5|00FF00"))

    /// 字符串格式多点找色 (与 AutoGo 协议兼容)
    ///
    /// - Parameters:
    ///   - firstColorHex: 首色 "RRGGBB" 如 "FF0000"
    ///   - pointsStr: 相对坐标串 "dx|dy|RRGGBB,dx|dy|RRGGBB,..." 如 "10|5|00FF00,-5|8|FFFFFF"
    ///   - tolerance: 容差 0~255
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

    /// 获取指定坐标像素色值
    func getPixelColor(x: Int, y: Int) -> (r: Int, g: Int, b: Int)? {
        guard let (pixels, w, h, bpr) = capture(),
              x >= 0, x < w, y >= 0, y < h else { return nil }
        let offset = y * bpr + x * 4
        return (Int(pixels[offset + 2]), Int(pixels[offset + 1]), Int(pixels[offset]))
    }

    /// 获取屏幕尺寸
    var screenSize: (width: Int, height: Int) {
        return (width, height)
    }

    // MARK: - 内部实现

    /// 从 IOSurface 读取原始像素 (内部调用)
    @discardableResult
    private func captureRawFrame() -> Bool {
        guard let surface = surface else { return false }

        _ = IOSurfaceLock(surface, 1, nil)
        defer { _ = IOSurfaceUnlock(surface, 1, nil) }

        guard let baseAddr = IOSurfaceGetBaseAddress(surface) else { return false }
        let w = IOSurfaceGetWidth(surface)
        let h = IOSurfaceGetHeight(surface)
        let bpr = IOSurfaceGetBytesPerRow(surface)

        guard w > 0, h > 0, bpr > 0 else { return false }

        let totalBytes = bpr * h
        let pixelData = Data(bytes: baseAddr, count: totalBytes)

        frameLock.withLock {
            _cachedPixels = [UInt8](pixelData)
            _cachedWidth = w
            _cachedHeight = h
            _cachedBytesPerRow = bpr
            _frameValid = true
        }

        return true
    }

    /// 在像素缓冲区中找色
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

    /// 从像素数据创建 UIImage
    private func makeUIImage(pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                      CGBitmapInfo.byteOrder32Little.rawValue)

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        context.data?.copyMemory(from: pixels, byteCount: bytesPerRow * height)

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// 解析 "RRGGBB" 格式
    private func parseHex(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 6 else { return nil }
        var val: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&val) else { return nil }
        return (Int((val >> 16) & 0xFF), Int((val >> 8) & 0xFF), Int(val & 0xFF))
    }
}
