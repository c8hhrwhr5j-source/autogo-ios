import Foundation

// ============================================================
// Lua C 回调函数 — 直接传给 lua_pushcclosure
// ============================================================

// ── 截图 ──
private func l_capture(_ L: OpaquePointer?) -> Int32 {
    let ok = ScreenCapture.shared.capture() != nil
    lua_pushboolean(L, ok ? 1 : 0)
    return 1
}
private func l_captureFresh(_ L: OpaquePointer?) -> Int32 {
    let ok = ScreenCapture.shared.captureFresh() != nil
    lua_pushboolean(L, ok ? 1 : 0)
    return 1
}
private func l_captureWait(_ L: OpaquePointer?) -> Int32 {
    let t = au_isnumber(L, 1) != 0 ? au_tonumber(L, 1) : 1.0
    let ok = ScreenCapture.shared.captureWait(timeout: t) != nil
    lua_pushboolean(L, ok ? 1 : 0)
    return 1
}
private func l_getScreenSize(_ L: OpaquePointer?) -> Int32 {
    lua_pushinteger(L, lua_Integer(ScreenCapture.shared.width))
    lua_pushinteger(L, lua_Integer(ScreenCapture.shared.height))
    return 2
}
private func l_getPixelColor(_ L: OpaquePointer?) -> Int32 {
    let x = Int(au_tointeger(L, 1))
    let y = Int(au_tointeger(L, 2))
    guard let c = ScreenCapture.shared.getPixelColor(x: x, y: y) else {
        lua_pushnil(L); lua_pushnil(L); lua_pushnil(L)
        return 3
    }
    lua_pushinteger(L, lua_Integer(c.r))
    lua_pushinteger(L, lua_Integer(c.g))
    lua_pushinteger(L, lua_Integer(c.b))
    return 3
}

// ── 找色 ──
private func l_findColor(_ L: OpaquePointer?) -> Int32 {
    let x = Int(au_tointeger(L, 1))
    let y = Int(au_tointeger(L, 2))
    guard let c = ScreenCapture.shared.getPixelColor(x: x, y: y) else {
        lua_pushnil(L)
        return 1
    }
    let hex = (Int(c.r) << 16) | (Int(c.g) << 8) | Int(c.b)
    lua_pushinteger(L, lua_Integer(hex))
    return 1
}
private func l_findColorInRegion(_ L: OpaquePointer?) -> Int32 {
    let r = Int(au_tointeger(L, 1)), g = Int(au_tointeger(L, 2)), b = Int(au_tointeger(L, 3))
    let tol = Int(au_tointeger(L, 4))
    let rx = Int(au_tointeger(L, 5)), ry = Int(au_tointeger(L, 6))
    let rw = Int(au_tointeger(L, 7)), rh = Int(au_tointeger(L, 8))
    let max = lua_gettop(L) >= 9 ? Int(au_tointeger(L, 9)) : 500
    let pts = ScreenCapture.shared.findColorInRegion(r: r, g: g, b: b, tolerance: tol, region: (rx, ry, rw, rh), maxResults: max)
    pushPoints(L, pts)
    return 1
}
private func l_findMultiColors(_ L: OpaquePointer?) -> Int32 {
    let fc = String(cString: au_tostring(L, 1))
    let ptsStr = String(cString: au_tostring(L, 2))
    let tol = lua_gettop(L) >= 3 ? Int(au_tointeger(L, 3)) : 5
    let max = lua_gettop(L) >= 4 ? Int(au_tointeger(L, 4)) : 100
    let pts = ScreenCapture.shared.findMultiColorsStr(firstColorHex: fc, pointsStr: ptsStr, tolerance: tol, maxResults: max)
    pushPoints(L, pts.map { ($0.x, $0.y) })
    return 1
}
private func l_findMultiColorsEx(_ L: OpaquePointer?) -> Int32 {
    let r = Int(au_tointeger(L, 1)), g = Int(au_tointeger(L, 2)), b = Int(au_tointeger(L, 3))
    let tol = Int(au_tointeger(L, 4))
    let max = lua_gettop(L) >= 6 ? Int(au_tointeger(L, 6)) : 100
    var rps: [(Int, Int, Int, Int, Int)] = []
    if au_istable(L, 5) != 0 {
        let n = au_objlen(L, 5)
        for i in 1...Int(n) {
            lua_rawgeti(L, 5, lua_Integer(i))
            lua_getfield(L, -1, "dx"); let dx = Int(au_tointeger(L, -1)); au_pop(L, 1)
            lua_getfield(L, -1, "dy"); let dy = Int(au_tointeger(L, -1)); au_pop(L, 1)
            lua_getfield(L, -1, "r");  let pr = Int(au_tointeger(L, -1)); au_pop(L, 1)
            lua_getfield(L, -1, "g");  let pg = Int(au_tointeger(L, -1)); au_pop(L, 1)
            lua_getfield(L, -1, "b");  let pb = Int(au_tointeger(L, -1)); au_pop(L, 1)
            rps.append((dx, dy, pr, pg, pb))
            au_pop(L, 1)
        }
    }
    let pts = ScreenCapture.shared.findMultiColors(firstColor: (r, g, b), tolerance: tol, relativePoints: rps, maxResults: max)
    pushPoints(L, pts.map { ($0.x, $0.y) })
    return 1
}

// ── 触摸 (单指) ──
private func l_tap(_ L: OpaquePointer?) -> Int32 {
    let x = au_tonumber(L, 1), y = au_tonumber(L, 2)
    let delay = lua_gettop(L) >= 3 ? Int(au_tointeger(L, 3)) : 30
    TouchController.shared.tap(x: x, y: y, delayMs: delay)
    return 0
}
private func l_longPress(_ L: OpaquePointer?) -> Int32 {
    let x = au_tonumber(L, 1), y = au_tonumber(L, 2)
    let dur = lua_gettop(L) >= 3 ? Int(au_tointeger(L, 3)) : 800
    TouchController.shared.longPress(x: x, y: y, durationMs: dur)
    return 0
}
private func l_swipe(_ L: OpaquePointer?) -> Int32 {
    let fx = au_tonumber(L, 1), fy = au_tonumber(L, 2)
    let tx = au_tonumber(L, 3), ty = au_tonumber(L, 4)
    let dur = lua_gettop(L) >= 5 ? Int(au_tointeger(L, 5)) : 300
    let steps = lua_gettop(L) >= 6 ? Int(au_tointeger(L, 6)) : 30
    TouchController.shared.swipe(fromX: fx, fromY: fy, toX: tx, toY: ty, durationMs: dur, steps: steps)
    return 0
}

// ── 触摸 (多点) ──
private func l_touchDown(_ L: OpaquePointer?) -> Int32 {
    let x = au_tonumber(L, 1), y = au_tonumber(L, 2)
    let idx = lua_gettop(L) >= 3 ? UInt32(au_tointeger(L, 3)) : 0
    TouchController.shared.touchDown(x: x, y: y, fingerIndex: idx)
    return 0
}
private func l_touchUp(_ L: OpaquePointer?) -> Int32 {
    let x = au_tonumber(L, 1), y = au_tonumber(L, 2)
    let idx = lua_gettop(L) >= 3 ? UInt32(au_tointeger(L, 3)) : 0
    TouchController.shared.touchUp(x: x, y: y, fingerIndex: idx)
    return 0
}
private func l_touchMove(_ L: OpaquePointer?) -> Int32 {
    let x = au_tonumber(L, 1), y = au_tonumber(L, 2)
    let idx = lua_gettop(L) >= 3 ? UInt32(au_tointeger(L, 3)) : 0
    TouchController.shared.touchMove(x: x, y: y, fingerIndex: idx)
    return 0
}
private func l_multiTap(_ L: OpaquePointer?) -> Int32 {
    var pts: [(Double, Double)] = []
    if au_istable(L, 1) != 0 {
        let n = au_objlen(L, 1)
        for i in 1...Int(n) {
            lua_rawgeti(L, 1, lua_Integer(i))
            lua_getfield(L, -1, "x"); let x = au_tonumber(L, -1); au_pop(L, 1)
            lua_getfield(L, -1, "y"); let y = au_tonumber(L, -1); au_pop(L, 1)
            pts.append((x, y))
            au_pop(L, 1)
        }
    }
    let delay = lua_gettop(L) >= 2 ? Int(au_tointeger(L, 2)) : 30
    TouchController.shared.multiTap(pts, delayMs: delay)
    return 0
}
private func l_pinch(_ L: OpaquePointer?) -> Int32 {
    let cx = au_tonumber(L, 1), cy = au_tonumber(L, 2)
    let fd = au_tonumber(L, 3), td = au_tonumber(L, 4)
    let dur = lua_gettop(L) >= 5 ? Int(au_tointeger(L, 5)) : 300
    let steps = lua_gettop(L) >= 6 ? Int(au_tointeger(L, 6)) : 20
    TouchController.shared.pinch(centerX: cx, centerY: cy, fromDistance: fd, toDistance: td, durationMs: dur, steps: steps)
    return 0
}

// ── HUD 浮窗 ──
private func l_showHud(_ L: OpaquePointer?) -> Int32 {
    let text = String(cString: au_tostring(L, 1))
    if lua_gettop(L) >= 3 {
        HudOverlay.shared.show(text: text, position: (CGFloat(au_tonumber(L, 2)), CGFloat(au_tonumber(L, 3))))
    } else {
        HudOverlay.shared.show(text: text)
    }
    return 0
}
private func l_hideHud(_ L: OpaquePointer?) -> Int32 {
    HudOverlay.shared.hide()
    return 0
}
private func l_updateHud(_ L: OpaquePointer?) -> Int32 {
    let text = String(cString: au_tostring(L, 1))
    HudOverlay.shared.update(text: text)
    return 0
}
private func l_toast(_ L: OpaquePointer?) -> Int32 {
    let text = String(cString: au_tostring(L, 1))
    let dur = lua_gettop(L) >= 2 ? au_tonumber(L, 2) : 1.5
    HudOverlay.shared.toast(text, duration: dur)
    return 0
}

// ── 工具 ──
private func l_sleep(_ L: OpaquePointer?) -> Int32 {
    let ms = Int(au_tointeger(L, 1))
    Thread.sleep(forTimeInterval: Double(ms) / 1000.0)
    return 0
}
private func l_debug(_ L: OpaquePointer?) -> Int32 {
    let msg = String(cString: au_tostring(L, 1))
    LogManager.shared.debug(msg)
    return 0
}

// ── 覆盖全局 print，重定向到日志 ──
private func l_print(_ L: OpaquePointer?) -> Int32 {
    let n = lua_gettop(L)
    let parts: [String] = (1...Int(n)).compactMap { i in
        au_tostring(L, Int32(i)).map { String(cString: $0) }
    }
    let msg = parts.joined(separator: "\t")
    LogManager.shared.debug("[lua] \(msg)")
    return 0
}


// MARK: - 辅助函数

/// 将 [(Int, Int)] 点阵数组压入 Lua 表
private func pushPoints(_ L: OpaquePointer?, _ points: [(Int, Int)]) {
    lua_createtable(L, Int32(points.count), 0)
    for (i, pt) in points.enumerated() {
        lua_createtable(L, 0, 2)
        lua_pushinteger(L, lua_Integer(pt.0)); lua_setfield(L, -2, "x")
        lua_pushinteger(L, lua_Integer(pt.1)); lua_setfield(L, -2, "y")
        lua_rawseti(L, -2, lua_Integer(i + 1))
    }
}

/// 注册单个 Lua 函数 — 使用 lua_pushcclosure 代替宏
private func regFn(_ L: OpaquePointer?, _ name: String, _ fn: (@convention(c) (OpaquePointer?) -> Int32)?) {
    lua_pushcclosure(L, fn, 0)
    lua_setfield(L, -2, name)
}

// ============================================================
// Lua 脚本引擎
// ============================================================

final class ScriptEngine {

    static let shared = ScriptEngine()

    private var L: OpaquePointer?
    private let queue = DispatchQueue(label: "autolua.script")

    private init() {
        guard let state = AutoLuaLuaNewState() else {
            fatalError("ScriptEngine: 无法创建 Lua 状态")
        }
        self.L = OpaquePointer(state)
        registerAPI()
        LogManager.shared.info("Lua 5.4 引擎已就绪")
    }

    deinit {
        if let L = L {
            AutoLuaLuaCloseState(unsafeBitCast(L, to: UnsafeMutableRawPointer.self))
        }
    }

    // MARK: - 注册 autolua 全局表

    private func registerAPI() {
        guard let L = L else { return }

        // 覆盖全局 print，重定向到应用日志
        lua_getglobal(L, "_G")
        lua_pushcclosure(L, l_print, 0)
        lua_setfield(L, -2, "print")
        lua_pop(L, 1)

        // 创建 autolua 表
        lua_createtable(L, 0, 23)

        // ── 截图 ──
        regFn(L, "capture",          l_capture)
        regFn(L, "captureFresh",     l_captureFresh)
        regFn(L, "captureWait",      l_captureWait)
        regFn(L, "getScreenSize",    l_getScreenSize)
        regFn(L, "getPixelColor",    l_getPixelColor)

        // ── 找色 ──
        regFn(L, "findColor",        l_findColor)
        regFn(L, "findColorInRegion",l_findColorInRegion)
        regFn(L, "findMultiColors",  l_findMultiColors)
        regFn(L, "findMultiColorsEx",l_findMultiColorsEx)

        // ── 触摸 (单指) ──
        regFn(L, "tap",        l_tap)
        regFn(L, "longPress",  l_longPress)
        regFn(L, "swipe",      l_swipe)

        // ── 触摸 (多点) ──
        regFn(L, "touchDown",  l_touchDown)
        regFn(L, "touchUp",    l_touchUp)
        regFn(L, "touchMove",  l_touchMove)
        regFn(L, "multiTap",   l_multiTap)

        // ── 手势 ──
        regFn(L, "pinch",      l_pinch)

        // ── HUD 浮窗 ──
        regFn(L, "showHud",    l_showHud)
        regFn(L, "hideHud",    l_hideHud)
        regFn(L, "updateHud",  l_updateHud)
        regFn(L, "toast",      l_toast)

        // ── 工具 ──
        regFn(L, "sleep",      l_sleep)
        regFn(L, "debug",      l_debug)

        // 注册为全局表
        lua_setglobal(L, "autolua")
    }

    // MARK: - 执行脚本

    /// 执行 Lua 脚本
    func runLua(_ script: String) -> String {
        return queue.sync {
            guard let L = self.L else { return "Error: Lua state not initialized" }

            // 加载代码
            let loadResult = script.withCString { au_loadstring(L, $0) }
            if loadResult != kLuaOK {
                let err = String(cString: au_tostring(L, -1))
                au_pop(L, 1)
                return "Lua Error: \(err)"
            }

            // 执行
            if au_pcall(L, 0, 1, 0) != kLuaOK {
                let err = String(cString: au_tostring(L, -1))
                au_pop(L, 1)
                return "Lua Error: \(err)"
            }

            // 提取返回值
            let result: String
            if au_isnil(L, -1) != 0 {
                result = ""
            } else if au_isstring(L, -1) != 0 || au_isnumber(L, -1) != 0 {
                result = String(cString: au_tostring(L, -1))
            } else {
                result = "(result)"
            }
            au_pop(L, 1)
            return result
        }
    }

    /// 执行 Lua 脚本文件
    func runFile(path: String) -> String {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "Error: cannot read file: \(path)"
        }
        return runLua(content)
    }
}
