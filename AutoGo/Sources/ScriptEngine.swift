import Foundation
import JavaScriptCore

/// 脚本引擎 — 基于 JavaScriptCore (iOS 内置，零外部依赖)
/// 提供 autogo.* JS 全局对象，TCP 下发 js: / lua: 统一执行
final class ScriptEngine {

    static let shared = ScriptEngine()

    private let context: JSContext
    private let queue = DispatchQueue(label: "autogo.script")

    init() {
        let ctx = JSContext()!
        ctx.exceptionHandler = { _, exc in
            if let e = exc?.toString() { print("[ScriptEngine] JS Error: \(e)") }
        }
        self.context = ctx
        registerAutoGoAPI(in: ctx)
    }

    // MARK: - 注册 autogo.* API (JavaScriptCore)

    private func registerAutoGoAPI(in ctx: JSContext) {
        let ag = JSValue(newObjectIn: ctx)

        // ── 截图 ──
        ag?.setValue(makeFunc(ctx) { _, _ in ScreenCapture.shared.capture() != nil },
                     forProperty: "capture")
        ag?.setValue(makeFunc(ctx) { _, _ in ScreenCapture.shared.captureFresh() != nil },
                     forProperty: "captureFresh")
        ag?.setValue(makeFunc(ctx) { _, args in
            let t = (args.count > 0 ? args[0].toNumber()?.doubleValue : 1.0) ?? 1.0
            return ScreenCapture.shared.captureWait(timeout: t) != nil
        }, forProperty: "captureWait")
        ag?.setValue(makeFunc(ctx) { _, _ in
            ["width": ScreenCapture.shared.width, "height": ScreenCapture.shared.height]
        }, forProperty: "getScreenSize")
        ag?.setValue(makeFunc(ctx) { _, args in
            let x = args[0].toInt32(), y = args[1].toInt32()
            if let c = ScreenCapture.shared.getPixelColor(x: Int(x), y: Int(y)) {
                return ["r": c.r, "g": c.g, "b": c.b]
            }
            return nil as Any?
        }, forProperty: "getPixelColor")

        // ── 找色 ──
        ag?.setValue(makeFunc(ctx) { _, args in
            let r = Int(args[0].toInt32()), g = Int(args[1].toInt32()), b = Int(args[2].toInt32())
            let tol = args.count > 3 ? Int(args[3].toInt32()) : 5
            let max = args.count > 4 ? Int(args[4].toInt32()) : 500
            return ScreenCapture.shared.findColor(r: r, g: g, b: b, tolerance: tol, maxResults: max)
                .map { ["x": $0.x, "y": $0.y] }
        }, forProperty: "findColor")

        ag?.setValue(makeFunc(ctx) { _, args in
            let r = Int(args[0].toInt32()), g = Int(args[1].toInt32()), b = Int(args[2].toInt32())
            let tol = Int(args[3].toInt32())
            let rx = Int(args[4].toInt32()), ry = Int(args[5].toInt32())
            let rw = Int(args[6].toInt32()), rh = Int(args[7].toInt32())
            let max = args.count > 8 ? Int(args[8].toInt32()) : 500
            return ScreenCapture.shared.findColorInRegion(
                r: r, g: g, b: b, tolerance: tol, region: (rx, ry, rw, rh), maxResults: max
            ).map { ["x": $0.x, "y": $0.y] }
        }, forProperty: "findColorInRegion")

        ag?.setValue(makeFunc(ctx) { _, args in
            let fc = (args[0].toString()) ?? ""
            let pts = (args[1].toString()) ?? ""
            let tol = args.count > 2 ? Int(args[2].toInt32()) : 5
            let max = args.count > 3 ? Int(args[3].toInt32()) : 100
            return ScreenCapture.shared.findMultiColorsStr(
                firstColorHex: fc, pointsStr: pts, tolerance: tol, maxResults: max
            ).map { ["x": $0.x, "y": $0.y] }
        }, forProperty: "findMultiColors")

        ag?.setValue(makeFunc(ctx) { _, args in
            let r = Int(args[0].toInt32()), g = Int(args[1].toInt32()), b = Int(args[2].toInt32())
            let tol = Int(args[3].toInt32())
            var rps: [(Int, Int, Int, Int, Int)] = []
            if let table = args[4].toArray() as? [[String: Int]] {
                for pt in table {
                    rps.append((pt["dx"] ?? 0, pt["dy"] ?? 0, pt["r"] ?? 0, pt["g"] ?? 0, pt["b"] ?? 0))
                }
            }
            let max = args.count > 5 ? Int(args[5].toInt32()) : 100
            return ScreenCapture.shared.findMultiColors(
                firstColor: (r, g, b), tolerance: tol, relativePoints: rps, maxResults: max
            ).map { ["x": $0.x, "y": $0.y] }
        }, forProperty: "findMultiColorsEx")

        // ── 触摸 (单指) ──
        ag?.setValue(makeFunc(ctx) { _, args in
            let x = args[0].toDouble(), y = args[1].toDouble()
            let delay = args.count > 2 ? Int(args[2].toInt32()) : 30
            TouchController.shared.tap(x: x, y: y, delayMs: delay)
            return nil as Any?
        }, forProperty: "tap")

        ag?.setValue(makeFunc(ctx) { _, args in
            TouchController.shared.longPress(
                x: args[0].toDouble(), y: args[1].toDouble(),
                durationMs: args.count > 2 ? Int(args[2].toInt32()) : 800)
            return nil as Any?
        }, forProperty: "longPress")

        ag?.setValue(makeFunc(ctx) { _, args in
            TouchController.shared.swipe(
                fromX: args[0].toDouble(), fromY: args[1].toDouble(),
                toX: args[2].toDouble(), toY: args[3].toDouble(),
                durationMs: args.count > 4 ? Int(args[4].toInt32()) : 300,
                steps: args.count > 5 ? Int(args[5].toInt32()) : 30)
            return nil as Any?
        }, forProperty: "swipe")

        // ── 触摸 (多点) ──
        ag?.setValue(makeFunc(ctx) { _, args in
            TouchController.shared.touchDown(
                x: args[0].toDouble(), y: args[1].toDouble(),
                fingerIndex: args.count > 2 ? UInt32(args[2].toInt32()) : 0)
            return nil as Any?
        }, forProperty: "touchDown")

        ag?.setValue(makeFunc(ctx) { _, args in
            TouchController.shared.touchUp(
                x: args[0].toDouble(), y: args[1].toDouble(),
                fingerIndex: args.count > 2 ? UInt32(args[2].toInt32()) : 0)
            return nil as Any?
        }, forProperty: "touchUp")

        ag?.setValue(makeFunc(ctx) { _, args in
            TouchController.shared.touchMove(
                x: args[0].toDouble(), y: args[1].toDouble(),
                fingerIndex: args.count > 2 ? UInt32(args[2].toInt32()) : 0)
            return nil as Any?
        }, forProperty: "touchMove")

        ag?.setValue(makeFunc(ctx) { _, args in
            var pts: [(Double, Double)] = []
            if let table = args[0].toArray() as? [[String: Double]] {
                for pt in table { pts.append((pt["x"] ?? 0, pt["y"] ?? 0)) }
            }
            TouchController.shared.multiTap(pts, delayMs: args.count > 1 ? Int(args[1].toInt32()) : 30)
            return nil as Any?
        }, forProperty: "multiTap")

        ag?.setValue(makeFunc(ctx) { _, args in
            TouchController.shared.pinch(
                centerX: args[0].toDouble(), centerY: args[1].toDouble(),
                fromDistance: args[2].toDouble(), toDistance: args[3].toDouble(),
                durationMs: args.count > 4 ? Int(args[4].toInt32()) : 300,
                steps: args.count > 5 ? Int(args[5].toInt32()) : 20)
            return nil as Any?
        }, forProperty: "pinch")

        // ── HUD 浮窗 ──
        ag?.setValue(makeFunc(ctx) { _, args in
            let text = (args[0].toString()) ?? ""
            if args.count > 2 {
                HudOverlay.shared.show(text: text, position: (CGFloat(args[1].toDouble()), CGFloat(args[2].toDouble())))
            } else {
                HudOverlay.shared.show(text: text)
            }
            return nil as Any?
        }, forProperty: "showHud")

        ag?.setValue(makeFunc(ctx) { _, _ in HudOverlay.shared.hide(); return nil as Any? },
                     forProperty: "hideHud")

        ag?.setValue(makeFunc(ctx) { _, args in
            HudOverlay.shared.update(text: (args[0].toString()) ?? "")
            return nil as Any?
        }, forProperty: "updateHud")

        ag?.setValue(makeFunc(ctx) { _, args in
            HudOverlay.shared.toast((args[0].toString()) ?? "", duration: args.count > 1 ? (args[1].toDouble()) : 1.5)
            return nil as Any?
        }, forProperty: "toast")

        // ── 工具 ──
        ag?.setValue(makeFunc(ctx) { _, args in
            Thread.sleep(forTimeInterval: Double(Int(args[0].toInt32())) / 1000.0)
            return nil as Any?
        }, forProperty: "sleep")

        ag?.setValue(makeFunc(ctx) { _, _ in OCREngine.shared.recognizeSync() ?? "" },
                     forProperty: "ocr")

        ctx.setObject(ag, forKeyedSubscript: "autogo" as NSString)
    }

    // MARK: - 执行脚本

    /// 执行 JavaScript 脚本
    func runJS(_ script: String) -> String {
        return queue.sync {
            let result = context.evaluateScript(script)
            return result?.toString() ?? ""
        }
    }

    /// 执行脚本 (兼容 lua: 前缀，实际走 JS 引擎)
    func runLua(_ script: String) -> String {
        return runJS(script)
    }

    /// 执行 JS 脚本文件
    func runFile(path: String) -> String {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "Error: cannot read file"
        }
        return runJS(content)
    }

    // MARK: - helper

    private func makeFunc(_ ctx: JSContext!,
                          _ block: @escaping (JSContext, [JSValue]) -> Any?) -> JSValue {
        let handler: @convention(block) (JSValue, JSValue, JSValue) -> JSValue? = { _, _, args in
            let arr = args.isArray ? (args.toArray() ?? []) : []
            if let result = block(ctx, arr as? [JSValue] ?? []) {
                return JSValue(object: result, in: ctx)
            }
            return JSValue(undefinedIn: ctx)
        }
        return JSValue(object: handler, in: ctx)
    }
}
