import Foundation
import UIKit

// MARK: - 核心服务协调器

/// 统一管理所有核心模块的启动、停止、状态
final class AutoGoCore {

    static let shared = AutoGoCore()

    private let touchController = TouchController.shared
    private let screenCapture = ScreenCapture.shared
    private let appDetector = AppDetector.shared
    private let httpServer = HttpServer.shared

    private(set) var isRunning = false

    private init() {}

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // 启动 HTTP 服务器（默认 8989 端口）
        httpServer.start(port: 8989) { [weak self] request in
            return self?.handleAPI(request: request) ?? HttpServer.Response(
                statusCode: 500,
                contentType: "text/plain",
                body: "Internal Error"
            )
        }

        print("[AutoGo] ✅ 全部服务已启动")
        print("[AutoGo] 🌐 HTTP 服务器: http://127.0.0.1:8989")
        print("[AutoGo] 📱 屏幕: \(screenCapture.cachedWidth)x\(screenCapture.cachedHeight)")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        httpServer.stop()
        print("[AutoGo] ⏹️ 服务已停止")
    }

    // MARK: - 便捷方法（供脚本调用）

    /// 点击坐标
    @discardableResult
    func tap(_ x: CGFloat, _ y: CGFloat, delayMs: Int = 50) -> Bool {
        return touchController.tap(x: x, y: y, delayMs: delayMs)
    }

    /// 滑动
    @discardableResult
    func swipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, durationMs: Int = 300) -> Bool {
        return touchController.swipe(fromX: fromX, fromY: fromY, toX: toX, toY: toY, durationMs: durationMs)
    }

    /// 长按
    @discardableResult
    func longPress(_ x: CGFloat, _ y: CGFloat, durationMs: Int = 800) -> Bool {
        return touchController.longPress(x: x, y: y, durationMs: durationMs)
    }

    /// 找色
    func findColor(hex: String, tolerance: Int = 5, region: CGRect? = nil) -> [CGPoint] {
        let color = UIColor(hex: hex) ?? .black
        return screenCapture.findColor(color, tolerance: tolerance, region: region, maxResults: 5)
    }

    /// 前台应用
    var foregroundApp: String {
        return appDetector.foregroundBundleID ?? "unknown"
    }

    /// 前台应用名
    var foregroundAppName: String {
        return appDetector.foregroundAppName ?? "未知"
    }

    /// OCR 识别
    func ocr(completion: @escaping (String) -> Void) {
        if #available(iOS 13.0, *) {
            OCREngine.shared.getAllText(completion: completion)
        } else {
            completion("OCR requires iOS 13+")
        }
    }

    /// 截屏
    func screenshot() -> UIImage? {
        return screenCapture.capture()
    }

    // MARK: - API 路由处理

    private func handleAPI(request: HttpServer.Request) -> HttpServer.Response {

        // 获取路径
        let path = request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        switch path {
        // ---- 触摸操作 ----
        case "touch/tap":
            return handleTap(request)

        case "touch/swipe":
            return handleSwipe(request)

        case "touch/longpress":
            return handleLongPress(request)

        case "touch/multitap":
            return handleMultiTap(request)

        case "touch/pinch":
            return handlePinch(request)

        // ---- 屏幕操作 ----
        case "screen/findcolor":
            return handleFindColor(request)

        case "screen/screenshot":
            return handleScreenshot(request)

        case "screen/getpixel":
            return handleGetPixel(request)

        case "screen/findimage":
            return handleFindImage(request)

        case "screen/regioncolors":
            return handleRegionColors(request)

        // ---- 应用信息 ----
        case "app/foreground":
            return handleForegroundApp(request)

        case "app/running":
            return handleRunningApps(request)

        case "app/switchto":
            return handleSwitchApp(request)

        // ---- OCR ----
        case "ocr/recognize":
            return handleOCR(request)

        case "ocr/findtext":
            return handleFindText(request)

        // ---- 系统信息 ----
        case "system/info":
            return handleSystemInfo(request)

        case "system/screensize":
            return handleScreenSize(request)

        // ---- 默认返回 Web UI ----
        case "":
            return handleWebUI(request)

        default:
            // 尝试作为 Web 静态文件
            return handleWebUI(request)
        }
    }

    // MARK: - 具体 API 处理

    private func handleTap(_ request: HttpServer.Request) -> HttpServer.Response {
        guard let x = request.params["x"].flatMap(CGFloat.init),
              let y = request.params["y"].flatMap(CGFloat.init) else {
            return .error("缺少 x 或 y 参数")
        }
        let delay = request.params["delay"].flatMap(Int.init) ?? 50
        let success = tap(x, y, delayMs: delay)
        return .json(["success": success, "action": "tap", "x": x, "y": y])
    }

    private func handleSwipe(_ request: HttpServer.Request) -> HttpServer.Response {
        guard let x1 = request.params["x1"].flatMap(CGFloat.init),
              let y1 = request.params["y1"].flatMap(CGFloat.init),
              let x2 = request.params["x2"].flatMap(CGFloat.init),
              let y2 = request.params["y2"].flatMap(CGFloat.init) else {
            return .error("缺少坐标参数")
        }
        let duration = request.params["duration"].flatMap(Int.init) ?? 300
        let success = swipe(fromX: x1, fromY: y1, toX: x2, toY: y2, durationMs: duration)
        return .json(["success": success, "action": "swipe"])
    }

    private func handleLongPress(_ request: HttpServer.Request) -> HttpServer.Response {
        guard let x = request.params["x"].flatMap(CGFloat.init),
              let y = request.params["y"].flatMap(CGFloat.init) else {
            return .error("缺少坐标参数")
        }
        let duration = request.params["duration"].flatMap(Int.init) ?? 800
        let success = longPress(x, y, durationMs: duration)
        return .json(["success": success, "action": "longPress"])
    }

    private func handleMultiTap(_ request: HttpServer.Request) -> HttpServer.Response {
        // 从 body 解析 JSON 坐标数组
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let points = json["points"] as? [[String: Double]] else {
            return .error("需要 JSON body: { \"points\": [[x,y], ...] }")
        }
        let tuples = points.compactMap { p -> (CGFloat, CGFloat)? in
            guard let x = p["x"], let y = p["y"] else { return nil }
            return (CGFloat(x), CGFloat(y))
        }
        let success = touchController.multiTap(points: tuples)
        return .json(["success": success, "action": "multitap", "count": tuples.count])
    }

    private func handlePinch(_ request: HttpServer.Request) -> HttpServer.Response {
        guard let cx = request.params["cx"].flatMap(CGFloat.init),
              let cy = request.params["cy"].flatMap(CGFloat.init),
              let sDist = request.params["startDistance"].flatMap(CGFloat.init),
              let eDist = request.params["endDistance"].flatMap(CGFloat.init) else {
            return .error("缺少参数")
        }
        let success = touchController.pinch(centerX: cx, centerY: cy,
                                             startDistance: sDist, endDistance: eDist)
        return .json(["success": success, "action": "pinch"])
    }

    private func handleFindColor(_ request: HttpServer.Request) -> HttpServer.Response {
        guard let hex = request.params["color"] ?? request.params["hex"] else {
            return .error("缺少 color 参数（hex 格式，如 FF0000）")
        }
        let tolerance = request.params["tolerance"].flatMap(Int.init) ?? 5
        let results = findColor(hex: hex, tolerance: tolerance)

        if results.isEmpty {
            return .json(["success": false, "found": false, "points": []])
        }

        return .json([
            "success": true,
            "found": true,
            "count": results.count,
            "points": results.map { ["x": $0.x, "y": $0.y] },
            "best": ["x": results.first!.x, "y": results.first!.y]
        ])
    }

    private func handleScreenshot(_ request: HttpServer.Request) -> HttpServer.Response {
        guard let image = screenshot() else {
            return .error("截图失败")
        }
        guard let data = image.pngData() else {
            return .error("图片编码失败")
        }
        let base64 = data.base64EncodedString()
        let screenSize = UIScreen.main.bounds.size
        return .json([
            "success": true,
            "format": "png",
            "width": Int(screenSize.width * UIScreen.main.scale),
            "height": Int(screenSize.height * UIScreen.main.scale),
            "base64": base64
        ])
    }

    private func handleGetPixel(_ request: HttpServer.Request) -> HttpServer.Response {
        guard let x = request.params["x"].flatMap(Int.init),
              let y = request.params["y"].flatMap(Int.init) else {
            return .error("缺少 x, y 参数")
        }
        guard let color = screenCapture.getPixelColor(x: x, y: y) else {
            return .error("取色失败")
        }
        return .json([
            "success": true,
            "x": x, "y": y,
            "color": color.hexString,
            "r": color.rgba.r,
            "g": color.rgba.g,
            "b": color.rgba.b
        ])
    }

    private func handleFindImage(_ request: HttpServer.Request) -> HttpServer.Response {
        // 期望 POST body 包含模板图片（base64）
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let base64 = json["template"] as? String,
              let imgData = Data(base64Encoded: base64),
              let template = UIImage(data: imgData) else {
            return .error("需要 JSON body 含 base64 图片")
        }
        let threshold = (json["threshold"] as? Double).flatMap(Float.init) ?? 0.8
        if let rect = screenCapture.findImage(template: template, threshold: threshold) {
            return .json(["success": true, "found": true,
                          "x": rect.origin.x, "y": rect.origin.y,
                          "width": rect.width, "height": rect.height])
        }
        return .json(["success": false, "found": false])
    }

    private func handleRegionColors(_ request: HttpServer.Request) -> HttpServer.Response {
        guard let x = request.params["x"].flatMap(Int.init),
              let y = request.params["y"].flatMap(Int.init),
              let w = request.params["w"].flatMap(Int.init),
              let h = request.params["h"].flatMap(Int.init) else {
            return .error("缺少矩形参数")
        }
        let region = CGRect(x: x, y: y, width: w, height: h)
        let colors = screenCapture.getColorsInRegion(region).map { $0.hexString }
        return .json(["success": true, "colors": colors, "count": colors.count])
    }

    private func handleForegroundApp(_ request: HttpServer.Request) -> HttpServer.Response {
        return .json([
            "success": true,
            "bundleID": foregroundApp,
            "name": foregroundAppName
        ])
    }

    private func handleRunningApps(_ request: HttpServer.Request) -> HttpServer.Response {
        let apps = appDetector.runningApplications.map {
            ["bundleID": $0.bundleID, "name": $0.name, "pid": $0.pid]
        }
        return .json(["success": true, "apps": apps, "count": apps.count])
    }

    private func handleSwitchApp(_ request: HttpServer.Request) -> HttpServer.Response {
        guard let bundleID = request.params["bundleID"] ?? request.params["id"] else {
            return .error("缺少 bundleID")
        }
        // 通过 SBSLaunchApplicationWithIdentifier 启动
        openApp(bundleID: bundleID)
        return .json(["success": true, "action": "switchApp", "bundleID": bundleID])
    }

    private func handleOCR(_ request: HttpServer.Request) -> HttpServer.Response {
        // OCR 是异步的，这里用同步方式
        guard let image = screenshot() else {
            return .error("截图失败")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var resultText = ""
        if #available(iOS 13.0, *) {
            OCREngine.shared.getAllText { text in
                resultText = text
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 15)
        }
        return .json(["success": true, "text": resultText])
    }

    private func handleFindText(_ request: HttpServer.Request) -> HttpServer.Response {
        guard let keyword = request.params["keyword"] else {
            return .error("缺少 keyword 参数")
        }
        guard let image = screenshot() else {
            return .error("截图失败")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var foundPoint: CGPoint? = nil
        if #available(iOS 13.0, *) {
            let result = OCREngine.shared.recognizeSync(image: image)
            let screenSize = UIScreen.main.bounds.size
            let imageSize = CGSize(width: screenSize.width * UIScreen.main.scale,
                                   height: screenSize.height * UIScreen.main.scale)
            foundPoint = result?.findTextCenter(keyword, in: imageSize)
            if let pt = foundPoint {
                foundPoint = CGPoint(x: pt.x / UIScreen.main.scale, y: pt.y / UIScreen.main.scale)
            }
        }

        if let pt = foundPoint {
            return .json(["success": true, "found": true, "x": pt.x, "y": pt.y])
        }
        return .json(["success": false, "found": false])
    }

    private func handleSystemInfo(_ request: HttpServer.Request) -> HttpServer.Response {
        let device = UIDevice.current
        let screen = UIScreen.main
        return .json([
            "success": true,
            "device": device.model,
            "name": device.name,
            "systemVersion": device.systemVersion,
            "systemName": device.systemName,
            "screenWidth": screen.bounds.width,
            "screenHeight": screen.bounds.height,
            "scale": screen.scale,
            "identifier": Bundle.main.bundleIdentifier ?? "com.autogo.ios"
        ])
    }

    private func handleScreenSize(_ request: HttpServer.Request) -> HttpServer.Response {
        let screen = UIScreen.main
        return .json([
            "success": true,
            "width": screen.bounds.width,
            "height": screen.bounds.height,
            "scale": screen.scale,
            "pixelWidth": Int(screen.bounds.width * screen.scale),
            "pixelHeight": Int(screen.bounds.height * screen.scale)
        ])
    }

    // MARK: - App 切换

    private func openApp(bundleID: String) {
        // 使用 SBSLaunchApplicationWithIdentifier 私有 API
        typealias LaunchFn = @convention(c) (CFString, Bool) -> Int32
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY),
              let sym = dlsym(handle, "SBSLaunchApplicationWithIdentifier") else {
            return
        }
        let fn = unsafeBitCast(sym, to: LaunchFn.self)
        _ = fn(bundleID as CFString, false)
        dlclose(handle)
    }

    // MARK: - Web UI

    private func handleWebUI(_ request: HttpServer.Request) -> HttpServer.Response {
        let path = request.path.isEmpty || request.path == "/" ? "index.html" : request.path
        return HttpServer.serveFile(path)
    }
}

// MARK: - UIColor 扩展

extension UIColor {
    convenience init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.hasPrefix("0X") { hex.removeFirst(2) }

        guard hex.count == 6 || hex.count == 8 else { return nil }

        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)

        if hex.count == 6 {
            self.init(
                red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
                blue: CGFloat(rgb & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        } else {
            self.init(
                red: CGFloat((rgb & 0xFF000000) >> 24) / 255.0,
                green: CGFloat((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: CGFloat((rgb & 0x0000FF00) >> 8) / 255.0,
                alpha: CGFloat(rgb & 0x000000FF) / 255.0
            )
        }
    }

    var rgba: (r: Int, g: Int, b: Int, a: Int) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
    }

    var hexString: String {
        let rgba = self.rgba
        return String(format: "#%02X%02X%02X", rgba.r, rgba.g, rgba.b)
    }
}
