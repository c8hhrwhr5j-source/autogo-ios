import Foundation

// ============================================================
// Lua C 回调函数 — @convention(c) 直接传给 lua_pushcfunction
// 这些函数只引用全局单例，不捕获局部变量，符合 C 函数规范
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
    let t = lua_isnumber(L, 1) != 0 ? lua_tonumber(L, 1) : 1.0
    let ok = ScreenCapture.shared.captureWait(timeout: t) != nil
    lua_pushboolean(L, ok ? 1 : 0)
    return 1
}
private func l_getScreenSize(_ L: OpaquePointer?) -> Int32 {
    lua_createtable(L, 0, 2)
    lua_pushnumber(L, Double(ScreenCapture.shared.width))
    lua_setfield(L, -2, "width")
    lua_pushnumber(L, Double(ScreenCapture.shared.height))
    lua_setfield(L, -2, "height")
    return 1
}
private func l_getPixelColor(_ L: OpaquePointer?) -> Int32 {
    let x = Int(lua_tointeger(L, 1))
    let y = Int(lua_tointeger(L, 2))
    guard let c = ScreenCapture.shared.getPixelColor(x: x, y: y) else {
        lua_pushnil(L)
        return 1
    }
    lua_createtable(L, 0, 3)
    lua_pushinteger(L, lua_Integer(c.r)); lua_setfield(L, -2, "r")
    lua_pushinteger(L, lua_Integer(c.g)); lua_setfield(L, -2, "g")
    lua_pushinteger(L, lua_Integer(c.b)); lua_setfield(L, -2, "b")
    return 1
}

// ── 找色 ──
private func l_findColor(_ L: OpaquePointer?) -> Int32 {
    let r = Int(lua_tointeger(L, 1)), g = Int(lua_tointeger(L, 2)), b = Int(lua_tointeger(L, 3))
    let tol = lua_gettop(L) >= 4 ? Int(lua_tointeger(L, 4)) : 5
    let max = lua_gettop(L) >= 5 ? Int(lua_tointeger(L, 5)) : 500
    let pts = ScreenCapture.shared.findColor(r: r, g: g, b: b, tolerance: tol, maxResults: max)
    pushPoints(L, pts)
    return 1
}
private func l_findColorInRegion(_ L: OpaquePointer?) -> Int32 {
    let r = Int(lua_tointeger(L, 1)), g = Int(lua_tointeger(L, 2)), b = Int(lua_tointeger(L, 3))
    let tol = Int(lua_tointeger(L, 4))
    let rx = Int(lua_tointeger(L, 5)), ry = Int(lua_tointeger(L, 6))
    let rw = Int(lua_tointeger(L, 7)), rh = Int(lua_tointeger(L, 8))
    let max = lua_gettop(L) >= 9 ? Int(lua_tointeger(L, 9)) : 500
    let pts = ScreenCapture.shared.findColorInRegion(r: r, g: g, b: b, tolerance: tol, region: (rx, ry, rw, rh), maxResults: max)
    pushPoints(L, pts)
    return 1
}
private func l_findMultiColors(_ L: OpaquePointer?) -> Int32 {
    let fc = String(cString: lua_tostring(L, 1))
    let ptsStr = String(cString: lua_tostring(L, 2))
    let tol = lua_gettop(L) >= 3 ? Int(lua_tointeger(L, 3)) : 5
    let max = lua_gettop(L) >= 4 ? Int(lua_tointeger(L, 4)) : 100
    let pts = ScreenCapture.shared.findMultiColorsStr(firstColorHex: fc, pointsStr: ptsStr, tolerance: tol, maxResults: max)
    pushPoints(L, pts)
    return 1
}
private func l_findMultiColorsEx(_ L: OpaquePointer?) -> Int32 {
    let r = Int(lua_tointeger(L, 1)), g = Int(lua_tointeger(L, 2)), b = Int(lua_tointeger(L, 3))
    let tol = Int(lua_tointeger(L, 4))
    let max = lua_gettop(L) >= 6 ? Int(lua_tointeger(L, 6)) : 100
    var rps: [(Int, Int, Int, Int, Int)] = []
    if lua_istable(L, 5) != 0 {
        let n = lua_objlen(L, 5)
        for i in 1...Int(n) {
            lua_rawgeti(L, 5, lua_Integer(i))
            lua_getfield(L, -1, "dx"); let dx = Int(lua_tointeger(L, -1)); lua_pop(L, 1)
            lua_getfield(L, -1, "dy"); let dy = Int(lua_tointeger(L, -1)); lua_pop(L, 1)
            lua_getfield(L, -1, "r");  let pr = Int(lua_tointeger(L, -1)); lua_pop(L, 1)
            lua_getfield(L, -1, "g");  let pg = Int(lua_tointeger(L, -1)); lua_pop(L, 1)
            lua_getfield(L, -1, "b");  let pb = Int(lua_tointeger(L, -1)); lua_pop(L, 1)
            rps.append((dx, dy, pr, pg, pb))
            lua_pop(L, 1)
        }
    }
    let pts = ScreenCapture.shared.findMultiColors(firstColor: (r, g, b), tolerance: tol, relativePoints: rps, maxResults: max)
    pushPoints(L, pts)
    return 1
}

// ── 触摸 (单指) ──
private func l_tap(_ L: OpaquePointer?) -> Int32 {
    let x = lua_tonumber(L, 1), y = lua_tonumber(L, 2)
    let delay = lua_gettop(L) >= 3 ? Int(lua_tointeger(L, 3)) : 30
    TouchController.shared.tap(x: x, y: y, delayMs: delay)
    return 0
}
private func l_longPress(_ L: OpaquePointer?) -> Int32 {
    let x = lua_tonumber(L, 1), y = lua_tonumber(L, 2)
    let dur = lua_gettop(L) >= 3 ? Int(lua_tointeger(L, 3)) : 800
    TouchController.shared.longPress(x: x, y: y, durationMs: dur)
    return 0
}
private func l_swipe(_ L: OpaquePointer?) -> Int32 {
    let fx = lua_tonumber(L, 1), fy = lua_tonumber(L, 2)
    let tx = lua_tonumber(L, 3), ty = lua_tonumber(L, 4)
    let dur = lua_gettop(L) >= 5 ? Int(lua_tointeger(L, 5)) : 300
    let steps = lua_gettop(L) >= 6 ? Int(lua_tointeger(L, 6)) : 30
    TouchController.shared.swipe(fromX: fx, fromY: fy, toX: tx, toY: ty, durationMs: dur, steps: steps)
    return 0
}

// ── 触摸 (多点) ──
private func l_touchDown(_ L: OpaquePointer?) -> Int32 {
    let x = lua_tonumber(L, 1), y = lua_tonumber(L, 2)
    let idx = lua_gettop(L) >= 3 ? UInt32(lua_tointeger(L, 3)) : 0
    TouchController.shared.touchDown(x: x, y: y, fingerIndex: idx)
    return 0
}
private func l_touchUp(_ L: OpaquePointer?) -> Int32 {
    let x = lua_tonumber(L, 1), y = lua_tonumber(L, 2)
    let idx = lua_gettop(L) >= 3 ? UInt32(lua_tointeger(L, 3)) : 0
    TouchController.shared.touchUp(x: x, y: y, fingerIndex: idx)
    return 0
}
private func l_touchMove(_ L: OpaquePointer?) -> Int32 {
    let x = lua_tonumber(L, 1), y = lua_tonumber(L, 2)
    let idx = lua_gettop(L) >= 3 ? UInt32(lua_tointeger(L, 3)) : 0
    TouchController.shared.touchMove(x: x, y: y, fingerIndex: idx)
    return 0
}
private func l_multiTap(_ L: OpaquePointer?) -> Int32 {
    var pts: [(Double, Double)] = []
    if lua_istable(L, 1) != 0 {
        let n = lua_objlen(L, 1)
        for i in 1...Int(n) {
            lua_rawgeti(L, 1, lua_Integer(i))
            lua_getfield(L, -1, "x"); let x = lua_tonumber(L, -1); lua_pop(L, 1)
            lua_getfield(L, -1, "y"); let y = lua_tonumber(L, -1); lua_pop(L, 1)
            pts.append((x, y))
            lua_pop(L, 1)
        }
    }
    let delay = lua_gettop(L) >= 2 ? Int(lua_tointeger(L, 2)) : 30
    TouchController.shared.multiTap(pts, delayMs: delay)
    return 0
}
private func l_pinch(_ L: OpaquePointer?) -> Int32 {
    let cx = lua_tonumber(L, 1), cy = lua_tonumber(L, 2)
    let fd = lua_tonumber(L, 3), td = lua_tonumber(L, 4)
    let dur = lua_gettop(L) >= 5 ? Int(lua_tointeger(L, 5)) : 300
    let steps = lua_gettop(L) >= 6 ? Int(lua_tointeger(L, 6)) : 20
    TouchController.shared.pinch(centerX: cx, centerY: cy, fromDistance: fd, toDistance: td, durationMs: dur, steps: steps)
    return 0
}

// ── HUD 浮窗 ──
private func l_showHud(_ L: OpaquePointer?) -> Int32 {
    let text = String(cString: lua_tostring(L, 1))
    if lua_gettop(L) >= 3 {
        HudOverlay.shared.show(text: text, position: (CGFloat(lua_tonumber(L, 2)), CGFloat(lua_tonumber(L, 3))))
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
    let text = String(cString: lua_tostring(L, 1))
    HudOverlay.shared.update(text: text)
    return 0
}
private func l_toast(_ L: OpaquePointer?) -> Int32 {
    let text = String(cString: lua_tostring(L, 1))
    let dur = lua_gettop(L) >= 2 ? lua_tonumber(L, 2) : 1.5
    HudOverlay.shared.toast(text, duration: dur)
    return 0
}

// ── 工具 ──
private func l_sleep(_ L: OpaquePointer?) -> Int32 {
    let ms = Int(lua_tointeger(L, 1))
    Thread.sleep(forTimeInterval: Double(ms) / 1000.0)
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

/// 注册单个 Lua 函数到当前栈顶的表
private func regFn(_ L: OpaquePointer?, _ name: String, _ fn: lua_CFunction?) {
    lua_pushcfunction(L, fn)
    lua_setfield(L, -2, name)
}

// ============================================================
// Lua 脚本引擎
// ============================================================

final class ScriptEngine {

    static let shared = ScriptEngine()

    private var L: OpaquePointer? // lua_State*
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
            AutoLuaLuaCloseState(AutoreleasingUnsafeMutablePointer<OpaquePointer>(&L))
        }
    }

    // MARK: - 注册 autolua 全局表

    private func registerAPI() {
        guard let L = L else { return }

        // 创建 autolua 表
        lua_createtable(L, 0, 22)

        // ── 截图 ──
        regFn(L, "capture",          unsafeBitCast(l_capture, to: lua_CFunction.self))
        regFn(L, "captureFresh",     unsafeBitCast(l_captureFresh, to: lua_CFunction.self))
        regFn(L, "captureWait",      unsafeBitCast(l_captureWait, to: lua_CFunction.self))
        regFn(L, "getScreenSize",    unsafeBitCast(l_getScreenSize, to: lua_CFunction.self))
        regFn(L, "getPixelColor",    unsafeBitCast(l_getPixelColor, to: lua_CFunction.self))

        // ── 找色 ──
        regFn(L, "findColor",        unsafeBitCast(l_findColor, to: lua_CFunction.self))
        regFn(L, "findColorInRegion",unsafeBitCast(l_findColorInRegion, to: lua_CFunction.self))
        regFn(L, "findMultiColors",  unsafeBitCast(l_findMultiColors, to: lua_CFunction.self))
        regFn(L, "findMultiColorsEx",unsafeBitCast(l_findMultiColorsEx, to: lua_CFunction.self))

        // ── 触摸 (单指) ──
        regFn(L, "tap",        unsafeBitCast(l_tap, to: lua_CFunction.self))
        regFn(L, "longPress",  unsafeBitCast(l_longPress, to: lua_CFunction.self))
        regFn(L, "swipe",      unsafeBitCast(l_swipe, to: lua_CFunction.self))

        // ── 触摸 (多点) ──
        regFn(L, "touchDown",  unsafeBitCast(l_touchDown, to: lua_CFunction.self))
        regFn(L, "touchUp",    unsafeBitCast(l_touchUp, to: lua_CFunction.self))
        regFn(L, "touchMove",  unsafeBitCast(l_touchMove, to: lua_CFunction.self))
        regFn(L, "multiTap",   unsafeBitCast(l_multiTap, to: lua_CFunction.self))

        // ── 手势 ──
        regFn(L, "pinch",      unsafeBitCast(l_pinch, to: lua_CFunction.self))

        // ── HUD 浮窗 ──
        regFn(L, "showHud",    unsafeBitCast(l_showHud, to: lua_CFunction.self))
        regFn(L, "hideHud",    unsafeBitCast(l_hideHud, to: lua_CFunction.self))
        regFn(L, "updateHud",  unsafeBitCast(l_updateHud, to: lua_CFunction.self))
        regFn(L, "toast",      unsafeBitCast(l_toast, to: lua_CFunction.self))

        // ── 工具 ──
        regFn(L, "sleep",      unsafeBitCast(l_sleep, to: lua_CFunction.self))

        // 注册为全局表
        lua_setglobal(L, "autolua")
    }

    // MARK: - 执行脚本

    /// 执行 Lua 脚本
    func runLua(_ script: String) -> String {
        return queue.sync {
            guard let L = self.L else { return "Error: Lua state not initialized" }

            // 加载代码
            if luaL_loadstring(L, script) != LUA_OK {
                let err = String(cString: lua_tostring(L, -1))
                lua_pop(L, 1)
                return "Lua Error: \(err)"
            }

            // 执行
            if lua_pcall(L, 0, 1, 0) != LUA_OK {
                let err = String(cString: lua_tostring(L, -1))
                lua_pop(L, 1)
                return "Lua Error: \(err)"
            }

            // 提取返回值
            let result: String
            if lua_isnil(L, -1) != 0 {
                result = ""
            } else if lua_isstring(L, -1) != 0 || lua_isnumber(L, -1) != 0 {
                result = String(cString: lua_tostring(L, -1))
            } else {
                result = "(result)"
            }
            lua_pop(L, 1)
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
