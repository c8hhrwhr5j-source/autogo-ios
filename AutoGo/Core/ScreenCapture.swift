import Foundation
import UIKit
import CoreGraphics
import Accelerate

// MARK: - 屏幕捕获与找色模块

/// 通过 IOSurface 获取屏幕帧缓冲，支持截图、找色、多点匹配
final class ScreenCapture {

    static let shared = ScreenCapture()

    private var cachedImage: CGImage?
    private var cachedData: UnsafeMutablePointer<UInt8>?
    var cachedWidth: Int = 0
    var cachedHeight: Int = 0
    private var cachedBytesPerRow: Int = 0

    private init() {}

    // MARK: - 截图

    /// 捕获当前屏幕截图
    /// - Returns: 屏幕截图 UIImage，失败返回 nil
    func capture() -> UIImage? {
        // 方法 1：尝试 IOSurface 帧缓冲（巨魔权限）
        if let surfaceImg = captureViaSurface() {
            return surfaceImg
        }

        // 方法 2：尝试 UIGraphicsImageRenderer（本 App 窗口）
        if let renderImg = captureViaRenderer() {
            print("[ScreenCapture] ⚠️ 使用应用内渲染（仅捕获本 App）")
            return renderImg
        }

        print("[ScreenCapture] ❌ 所有截屏方法均失败")
        return nil
    }

    /// 捕获并缓存像素数据（供快速找色）
    func captureToCache() -> Bool {
        guard let image = capture()?.cgImage else { return false }

        cachedWidth = image.width
        cachedHeight = image.height
        cachedBytesPerRow = image.bytesPerRow

        // 释放旧缓存
        if let old = cachedData {
            free(old)
        }

        let size = cachedHeight * cachedBytesPerRow
        cachedData = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        cachedImage = image

        // 拷贝像素数据
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data else {
            return false
        }

        let src = CFDataGetBytePtr(data)
        if let src = src {
            memcpy(cachedData, src, size)
            return true
        }

        return false
    }

    // MARK: - 找色（单点）

    /// 查找单个颜色在屏幕上的位置
    /// - Parameters:
    ///   - targetColor: 目标 UIColor
    ///   - tolerance: 颜色容差（0-255，越大越宽松）
    ///   - region: 搜索区域（nil = 全屏），原点为左上角
    ///   - maxResults: 最多返回几个匹配点
    /// - Returns: 匹配点的坐标数组 [(x, y)]
    func findColor(
        _ targetColor: UIColor,
        tolerance: Int = 5,
        region: CGRect? = nil,
        maxResults: Int = 1
    ) -> [CGPoint] {
        let (r, g, b) = extractRGB(from: targetColor)
        return findColor(r: r, g: g, b: b,
                         tolerance: tolerance,
                         region: region,
                         maxResults: maxResults)
    }

    /// 通过 RGB 值找色
    func findColor(
        r: Int, g: Int, b: Int,
        tolerance: Int = 5,
        region: CGRect? = nil,
        maxResults: Int = 1
    ) -> [CGPoint] {
        guard refreshCacheIfNeeded(),
              let data = cachedData else { return [] }

        let searchRegion = region ?? CGRect(x: 0, y: 0,
                                            width: CGFloat(cachedWidth),
                                            height: CGFloat(cachedHeight))

        let startX = max(0, Int(searchRegion.origin.x))
        let startY = max(0, Int(searchRegion.origin.y))
        let endX = min(cachedWidth, startX + Int(searchRegion.size.width))
        let endY = min(cachedHeight, startY + Int(searchRegion.size.height))

        var results: [CGPoint] = []

        for y in stride(from: startY, to: endY, by: 2) {
            if results.count >= maxResults { break }
            for x in stride(from: startX, to: endX, by: 2) {
                if results.count >= maxResults { break }
                let offset = y * cachedBytesPerRow + x * 4
                let pixelR = Int(data[offset])       // BGRA → R
                let pixelG = Int(data[offset + 1])   // BGRA → G
                let pixelB = Int(data[offset + 2])   // BGRA → B

                if abs(pixelR - r) <= tolerance &&
                   abs(pixelG - g) <= tolerance &&
                   abs(pixelB - b) <= tolerance {
                    results.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
                }
            }
        }

        return results
    }

    /// 查找多个颜色（返回各颜色的首次匹配位置）
    func findColors(
        _ targetColors: [UIColor],
        tolerance: Int = 5,
        region: CGRect? = nil
    ) -> [UIColor: CGPoint?] {
        var results: [UIColor: CGPoint?] = [:]
        for color in targetColors {
            let match = findColor(color, tolerance: tolerance, region: region, maxResults: 1)
            results[color] = match.first
        }
        return results
    }

    // MARK: - 找图（模板匹配）

    /// 在屏幕上搜索模板图像位置
    /// - Parameters:
    ///   - template: 要搜索的小图
    ///   - region: 搜索区域（nil = 全屏）
    ///   - threshold: 匹配置信度（0.0-1.0，越大越严格）
    /// - Returns: 匹配矩形
    func findImage(
        template: UIImage,
        region: CGRect? = nil,
        threshold: Float = 0.8
    ) -> CGRect? {
        guard let screen = capture()?.cgImage,
              let tpl = template.cgImage else { return nil }

        return matchTemplate(screen: screen, template: tpl,
                             region: region, threshold: threshold)
    }

    // MARK: - 取色

    /// 获取指定坐标的像素颜色
    func getPixelColor(x: Int, y: Int) -> UIColor? {
        guard refreshCacheIfNeeded(),
              let data = cachedData,
              x >= 0, x < cachedWidth,
              y >= 0, y < cachedHeight else { return nil }

        let offset = y * cachedBytesPerRow + x * 4
        let r = CGFloat(data[offset]) / 255.0
        let g = CGFloat(data[offset + 1]) / 255.0
        let b = CGFloat(data[offset + 2]) / 255.0

        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// 获取指定区域内所有不重复的颜色
    func getColorsInRegion(_ region: CGRect, maxColors: Int = 20) -> [UIColor] {
        guard refreshCacheIfNeeded(),
              let data = cachedData else { return [] }

        let r = Int(region.origin.x)
        let t = Int(region.origin.y)
        let r2 = r + Int(region.width)
        let b2 = t + Int(region.height)

        var colorSet = Set<UInt32>()
        var colors: [UIColor] = []

        for y in stride(from: t, to: min(b2, cachedHeight), by: 3) {
            if colors.count >= maxColors { break }
            for x in stride(from: r, to: min(r2, cachedWidth), by: 3) {
                if colors.count >= maxColors { break }
                let offset = y * cachedBytesPerRow + x * 4
                let hash = UInt32(data[offset]) << 16 |
                           UInt32(data[offset + 1]) << 8 |
                           UInt32(data[offset + 2])
                if colorSet.insert(hash).inserted {
                    let color = UIColor(
                        red: CGFloat(data[offset]) / 255.0,
                        green: CGFloat(data[offset + 1]) / 255.0,
                        blue: CGFloat(data[offset + 2]) / 255.0,
                        alpha: 1.0
                    )
                    colors.append(color)
                }
            }
        }

        return colors
    }

    /// 检查指定区域与参考图像是否一致
    func regionEqualsImage(_ region: CGRect, reference: UIImage, tolerance: Float = 0.95) -> Bool {
        guard let screen = capture()?.cgImage,
              let ref = reference.cgImage else { return false }

        let result = matchTemplate(screen: screen, template: ref, region: region, threshold: tolerance)
        return result != nil
    }

    // MARK: - 私有方法

    private func refreshCacheIfNeeded() -> Bool {
        if cachedData != nil && cachedImage != nil {
            return true
        }
        return captureToCache()
    }

    private func extractRGB(from color: UIColor) -> (Int, Int, Int) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(r * 255), Int(g * 255), Int(b * 255))
    }

    // MARK: - 截屏实现

    private func captureViaSurface() -> UIImage? {
        guard let surface = autoGoGetMainDisplaySurface() else { return nil }
        guard let cgImage = autoGoCreateImageFromSurface(surface) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func captureViaRenderer() -> UIImage? {
        guard let window = UIApplication.shared.keyWindow else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { ctx in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    // MARK: - 模板匹配算法（简化版归一化互相关）

    private func matchTemplate(
        screen: CGImage,
        template: CGImage,
        region: CGRect?,
        threshold: Float
    ) -> CGRect? {
        let sw = screen.width
        let sh = screen.height
        let tw = template.width
        let th = template.height

        guard tw <= sw && th <= sh else { return nil }

        let searchRegion = region ?? CGRect(x: 0, y: 0, width: CGFloat(sw), height: CGFloat(sh))
        let startX = max(0, Int(searchRegion.origin.x))
        let startY = max(0, Int(searchRegion.origin.y))
        let endX = min(sw - tw, startX + Int(searchRegion.size.width) - tw)
        let endY = min(sh - th, startY + Int(searchRegion.size.height) - th)

        guard let screenCtx = CGContext(
            data: nil, width: sw, height: sh,
            bitsPerComponent: 8, bytesPerRow: sw * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ), let tplCtx = CGContext(
            data: nil, width: tw, height: th,
            bitsPerComponent: 8, bytesPerRow: tw * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        screenCtx.draw(screen, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        tplCtx.draw(template, in: CGRect(x: 0, y: 0, width: tw, height: th))

        guard let sData = screenCtx.data, let tData = tplCtx.data else { return nil }

        var bestScore: Float = -1
        var bestRect: CGRect?

        let tplArea = tw * th
        let sBuf = sData.bindMemory(to: UInt8.self, capacity: sw * sh * 4)
        let tBuf = tData.bindMemory(to: UInt8.self, capacity: tw * th * 4)

        for y in startY..<endY {
            for x in startX..<endX {
                var sum: Float = 0
                var skipped = false
                for ty in 0..<th {
                    if skipped { break }
                    for tx in 0..<tw {
                        let sOff = ((y + ty) * sw + (x + tx)) * 4
                        let tOff = (ty * tw + tx) * 4
                        let diffR = Float(abs(Int(sBuf[sOff + 1]) - Int(tBuf[tOff + 1])))
                        let diffG = Float(abs(Int(sBuf[sOff + 2]) - Int(tBuf[tOff + 2])))
                        let diffB = Float(abs(Int(sBuf[sOff + 3]) - Int(tBuf[tOff + 3])))
                        sum += (255 - diffR) / 255 + (255 - diffG) / 255 + (255 - diffB) / 255
                    }
                }
                let score = sum / Float(tplArea * 3)
                if score >= threshold && score > bestScore {
                    bestScore = score
                    bestRect = CGRect(x: CGFloat(x), y: CGFloat(y),
                                      width: CGFloat(tw), height: CGFloat(th))
                }
            }
        }

        return bestRect
    }
}

// MARK: - C 函数桥接声明
@_silgen_name("AutoGoGetMainDisplaySurface")
private func autoGoGetMainDisplaySurface() -> IOSurfaceRef?

@_silgen_name("AutoGoCreateImageFromSurface")
private func autoGoCreateImageFromSurface(_ surface: IOSurfaceRef) -> CGImage?
