import Foundation
import Lua

// MARK: - Lua C 桥接辅助

/// Swift 闭包 → Lua C 函数指针包装
private final class LuaClosure {
    let fn: (OpaquePointer) -> Int32
    init(_ fn: @escaping (OpaquePointer) -> Int32) { self.fn = fn }
}
private var closureKey: UInt8 = 0

private func luaL_checkInteger(_ L: OpaquePointer, _ idx: Int32) -> lua_Integer {
    return lua_tointegerx(L, idx, nil)
}
private func luaL_checkNumber(_ L: OpaquePointer, _ idx: Int32) -> lua_Number {
    return lua_tonumberx(L, idx, nil)
}
private func luaL_checkString(_ L: OpaquePointer, _ idx: Int32) -> String? {
    guard let cstr = lua_tolstring(L, idx, nil) else { return nil }
    return String(cString: cstr)
}

// MARK: - 脚本引擎

final class ScriptEngine {

    /// 注册所有 autogo.* Lua 函数
    static func registerAll(in L: OpaquePointer) {
        let functions: [(String, lua_CFunction)] = [
            // ── 截图 ──
            ("capture",       autogo_capture),
            ("captureFresh",  autogo_captureFresh),
            ("captureWait",   autogo_captureWait),
            ("getScreenSize", autogo_getScreenSize),
            ("getPixelColor", autogo_getPixelColor),

            // ── 找色 ──
            ("findColor",         autogo_findColor),
            ("findColorInRegion", autogo_findColorInRegion),
            ("findMultiColors",   autogo_findMultiColors),
            ("findMultiColorsEx", autogo_findMultiColorsEx),

            // ── 触摸 (单指) ──
            ("tap",       autogo_tap),
            ("longPress", autogo_longPress),
            ("swipe",     autogo_swipe),

            // ── 触摸 (多点) ──
            ("touchDown",  autogo_touchDown),
            ("touchUp",    autogo_touchUp),
            ("touchMove",  autogo_touchMove),
            ("multiTap",   autogo_multiTap),
            ("pinch",      autogo_pinch),

            // ── HUD 浮窗 ──
            ("showHud",   autogo_showHud),
            ("hideHud",   autogo_hideHud),
            ("updateHud", autogo_updateHud),
            ("toast",     autogo_toast),

            // ── 工具 ──
            ("sleep", autogo_sleep),
            ("ocr",   autogo_ocr),
        ]

        lua_createtable(L, 0, Int32(functions.count))
        for (name, fn) in functions {
            lua_pushcfunction(L, fn)
            lua_setfield(L, -2, name)
        }
        lua_setglobal(L, "autogo")
    }

    /// 执行 Lua 脚本
    static func runLua(_ script: String) -> String {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let savedOut = dup(STDOUT_FILENO)
        let savedErr = dup(STDERR_FILENO)
        dup2(stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        let L = luaL_newstate()
        luaL_openlibs(L)
        registerAll(in: L!)

        let status = luaL_loadstring(L!, script)
        if status == 0 {
            lua_pcallk(L!, 0, 0, 0, 0, nil)
        } else {
            let err = String(cString: lua_tolstring(L!, -1, nil))
            fputs("Lua load error: \(err)\n", stderr)
        }

        lua_close(L!)

        dup2(savedOut, STDOUT_FILENO)
        dup2(savedErr, STDERR_FILENO)
        close(savedOut)
        close(savedErr)

        stdoutPipe.fileHandleForWriting.closeFile()
        stderrPipe.fileHandleForWriting.closeFile()

        let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return err.isEmpty ? out : "[ERROR]\n\(err)"
    }
}

// MARK: ── C 桥接函数实现 ──

// ============================================================
// 截图
// ============================================================

private func autogo_capture(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    guard let cap = ScreenCapture.shared.capture() else {
        lua_pushboolean(L, 0)
        return 1
    }
    lua_pushboolean(L, 1)
    return 1
}

private func autogo_captureFresh(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    guard let cap = ScreenCapture.shared.captureFresh() else {
        lua_pushboolean(L, 0)
        return 1
    }
    lua_pushboolean(L, 1)
    return 1
}

private func autogo_captureWait(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let timeout = lua_gettop(L) >= 1 ? luaL_checkNumber(L, 1) : 1.0
    guard let cap = ScreenCapture.shared.captureWait(timeout: timeout) else {
        lua_pushboolean(L, 0)
        return 1
    }
    lua_pushboolean(L, 1)
    return 1
}

private func autogo_getScreenSize(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let sc = ScreenCapture.shared
    lua_pushinteger(L, lua_Integer(sc.width))
    lua_pushinteger(L, lua_Integer(sc.height))
    return 2
}

private func autogo_getPixelColor(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let x = Int(luaL_checkInteger(L, 1))
    let y = Int(luaL_checkInteger(L, 2))
    guard let c = ScreenCapture.shared.getPixelColor(x: x, y: y) else {
        lua_pushnil(L)
        return 1
    }
    lua_pushinteger(L, lua_Integer(c.r))
    lua_pushinteger(L, lua_Integer(c.g))
    lua_pushinteger(L, lua_Integer(c.b))
    return 3
}

// ============================================================
// 找色
// ============================================================

private func autogo_findColor(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let r = Int(luaL_checkInteger(L, 1))
    let g = Int(luaL_checkInteger(L, 2))
    let b = Int(luaL_checkInteger(L, 3))
    let tol = lua_gettop(L) >= 4 ? Int(luaL_checkInteger(L, 4)) : 5
    let max = lua_gettop(L) >= 5 ? Int(luaL_checkInteger(L, 5)) : 500

    let results = ScreenCapture.shared.findColor(r: r, g: g, b: b, tolerance: tol, maxResults: max)

    lua_createtable(L, Int32(results.count), 0)
    for (i, pt) in results.enumerated() {
        lua_createtable(L, 0, 2)
        lua_pushinteger(L, lua_Integer(pt.x))
        lua_setfield(L, -2, "x")
        lua_pushinteger(L, lua_Integer(pt.y))
        lua_setfield(L, -2, "y")
        lua_rawseti(L, -2, Int32(i + 1))
    }
    return 1
}

private func autogo_findColorInRegion(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let r = Int(luaL_checkInteger(L, 1))
    let g = Int(luaL_checkInteger(L, 2))
    let b = Int(luaL_checkInteger(L, 3))
    let tol = Int(luaL_checkInteger(L, 4))
    let rx = Int(luaL_checkInteger(L, 5))
    let ry = Int(luaL_checkInteger(L, 6))
    let rw = Int(luaL_checkInteger(L, 7))
    let rh = Int(luaL_checkInteger(L, 8))
    let max = lua_gettop(L) >= 9 ? Int(luaL_checkInteger(L, 9)) : 500

    let results = ScreenCapture.shared.findColorInRegion(
        r: r, g: g, b: b, tolerance: tol,
        region: (rx, ry, rw, rh), maxResults: max
    )

    lua_createtable(L, Int32(results.count), 0)
    for (i, pt) in results.enumerated() {
        lua_createtable(L, 0, 2)
        lua_pushinteger(L, lua_Integer(pt.x))
        lua_setfield(L, -2, "x")
        lua_pushinteger(L, lua_Integer(pt.y))
        lua_setfield(L, -2, "y")
        lua_rawseti(L, -2, Int32(i + 1))
    }
    return 1
}

/// autogo.findMultiColors(firstColorHex, pointsStr, tolerance, maxResults)
/// 与 AutoGo 兼容的字符串格式
private func autogo_findMultiColors(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let fcHex = luaL_checkString(L, 1) ?? ""
    let ptsStr = luaL_checkString(L, 2) ?? ""
    let tol = lua_gettop(L) >= 3 ? Int(luaL_checkInteger(L, 3)) : 5
    let max = lua_gettop(L) >= 4 ? Int(luaL_checkInteger(L, 4)) : 100

    let results = ScreenCapture.shared.findMultiColorsStr(
        firstColorHex: fcHex, pointsStr: ptsStr,
        tolerance: tol, maxResults: max
    )

    lua_createtable(L, Int32(results.count), 0)
    for (i, r) in results.enumerated() {
        lua_createtable(L, 0, 2)
        lua_pushinteger(L, lua_Integer(r.x))
        lua_setfield(L, -2, "x")
        lua_pushinteger(L, lua_Integer(r.y))
        lua_setfield(L, -2, "y")
        lua_rawseti(L, -2, Int32(i + 1))
    }
    return 1
}

/// autogo.findMultiColorsEx(r, g, b, tol, {{dx,dy,r,g,b}, ...}, maxResults)
/// 扩展格式，传入 table
private func autogo_findMultiColorsEx(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let r = Int(luaL_checkInteger(L, 1))
    let g = Int(luaL_checkInteger(L, 2))
    let b = Int(luaL_checkInteger(L, 3))
    let tol = Int(luaL_checkInteger(L, 4))
    let max = lua_gettop(L) >= 6 ? Int(luaL_checkInteger(L, 6)) : 100

    // 解析相对坐标 table
    var rps: [(dx: Int, dy: Int, r: Int, g: Int, b: Int)] = []
    if lua_istable(L, 5) != 0 {
        let n = lua_rawlen(L, 5)
        for i in 1...n {
            lua_rawgeti(L, 5, Int32(i))
            if lua_istable(L, -1) != 0 {
                lua_getfield(L, -1, "dx")
                let dx = Int(lua_tointegerx(L, -1, nil))
                lua_pop(L, 1)
                lua_getfield(L, -1, "dy")
                let dy = Int(lua_tointegerx(L, -1, nil))
                lua_pop(L, 1)
                lua_getfield(L, -1, "r")
                let pr = Int(lua_tointegerx(L, -1, nil))
                lua_pop(L, 1)
                lua_getfield(L, -1, "g")
                let pg = Int(lua_tointegerx(L, -1, nil))
                lua_pop(L, 1)
                lua_getfield(L, -1, "b")
                let pb = Int(lua_tointegerx(L, -1, nil))
                lua_pop(L, 1)
                rps.append((dx, dy, pr, pg, pb))
            }
            lua_pop(L, 1)
        }
    }

    let results = ScreenCapture.shared.findMultiColors(
        firstColor: (r, g, b), tolerance: tol,
        relativePoints: rps, maxResults: max
    )

    lua_createtable(L, Int32(results.count), 0)
    for (i, r) in results.enumerated() {
        lua_createtable(L, 0, 2)
        lua_pushinteger(L, lua_Integer(r.x))
        lua_setfield(L, -2, "x")
        lua_pushinteger(L, lua_Integer(r.y))
        lua_setfield(L, -2, "y")
        lua_rawseti(L, -2, Int32(i + 1))
    }
    return 1
}

// ============================================================
// 触摸 — 单指
// ============================================================

private func autogo_tap(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let x = luaL_checkNumber(L, 1)
    let y = luaL_checkNumber(L, 2)
    let delay = lua_gettop(L) >= 3 ? Int(luaL_checkInteger(L, 3)) : 30
    TouchController.shared.tap(x: x, y: y, delayMs: delay)
    return 0
}

private func autogo_longPress(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let x = luaL_checkNumber(L, 1)
    let y = luaL_checkNumber(L, 2)
    let dur = lua_gettop(L) >= 3 ? Int(luaL_checkInteger(L, 3)) : 800
    TouchController.shared.longPress(x: x, y: y, durationMs: dur)
    return 0
}

private func autogo_swipe(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let x1 = luaL_checkNumber(L, 1)
    let y1 = luaL_checkNumber(L, 2)
    let x2 = luaL_checkNumber(L, 3)
    let y2 = luaL_checkNumber(L, 4)
    let dur = lua_gettop(L) >= 5 ? Int(luaL_checkInteger(L, 5)) : 300
    let steps = lua_gettop(L) >= 6 ? Int(luaL_checkInteger(L, 6)) : 30
    TouchController.shared.swipe(fromX: x1, fromY: y1, toX: x2, toY: y2,
                                  durationMs: dur, steps: steps)
    return 0
}

// ============================================================
// 触摸 — 多点
// ============================================================

private func autogo_touchDown(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let x = luaL_checkNumber(L, 1)
    let y = luaL_checkNumber(L, 2)
    let finger = lua_gettop(L) >= 3 ? UInt32(luaL_checkInteger(L, 3)) : 0
    TouchController.shared.touchDown(x: x, y: y, fingerIndex: finger)
    return 0
}

private func autogo_touchUp(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let x = luaL_checkNumber(L, 1)
    let y = luaL_checkNumber(L, 2)
    let finger = lua_gettop(L) >= 3 ? UInt32(luaL_checkInteger(L, 3)) : 0
    TouchController.shared.touchUp(x: x, y: y, fingerIndex: finger)
    return 0
}

private func autogo_touchMove(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let x = luaL_checkNumber(L, 1)
    let y = luaL_checkNumber(L, 2)
    let finger = lua_gettop(L) >= 3 ? UInt32(luaL_checkInteger(L, 3)) : 0
    TouchController.shared.touchMove(x: x, y: y, fingerIndex: finger)
    return 0
}

/// autogo.multiTap({{x1,y1}, {x2,y2}, ...}, delayMs)
private func autogo_multiTap(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let delay = lua_gettop(L) >= 2 ? Int(luaL_checkInteger(L, 2)) : 30

    var points: [(x: Double, y: Double)] = []
    if lua_istable(L, 1) != 0 {
        let n = lua_rawlen(L, 1)
        for i in 1...n {
            lua_rawgeti(L, 1, Int32(i))
            if lua_istable(L, -1) != 0 {
                lua_getfield(L, -1, "x")
                let x = lua_tonumberx(L, -1, nil)
                lua_pop(L, 1)
                lua_getfield(L, -1, "y")
                let y = lua_tonumberx(L, -1, nil)
                lua_pop(L, 1)
                points.append((x, y))
            }
            lua_pop(L, 1)
        }
    }

    TouchController.shared.multiTap(points, delayMs: delay)
    return 0
}

/// autogo.pinch(cx, cy, fromDist, toDist, duration, steps)
private func autogo_pinch(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let cx = luaL_checkNumber(L, 1)
    let cy = luaL_checkNumber(L, 2)
    let fromDist = luaL_checkNumber(L, 3)
    let toDist = luaL_checkNumber(L, 4)
    let dur = lua_gettop(L) >= 5 ? Int(luaL_checkInteger(L, 5)) : 300
    let steps = lua_gettop(L) >= 6 ? Int(luaL_checkInteger(L, 6)) : 20
    TouchController.shared.pinch(centerX: cx, centerY: cy,
                                  fromDistance: fromDist, toDistance: toDist,
                                  durationMs: dur, steps: steps)
    return 0
}

// ============================================================
// HUD 浮窗
// ============================================================

private func autogo_showHud(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let text = luaL_checkString(L, 1) ?? ""
    if lua_gettop(L) >= 3 {
        let x = CGFloat(luaL_checkNumber(L, 2))
        let y = CGFloat(luaL_checkNumber(L, 3))
        HudOverlay.shared.show(text: text, position: (x, y))
    } else {
        HudOverlay.shared.show(text: text)
    }
    return 0
}

private func autogo_hideHud(_ L: OpaquePointer?) -> Int32 {
    HudOverlay.shared.hide()
    return 0
}

private func autogo_updateHud(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let text = luaL_checkString(L, 1) ?? ""
    HudOverlay.shared.update(text: text)
    return 0
}

private func autogo_toast(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let text = luaL_checkString(L, 1) ?? ""
    let dur = lua_gettop(L) >= 2 ? luaL_checkNumber(L, 2) : 1.5
    HudOverlay.shared.toast(text, duration: dur)
    return 0
}

// ============================================================
// 工具
// ============================================================

private func autogo_sleep(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let ms = Int(luaL_checkInteger(L, 1))
    usleep(UInt32(ms) * 1000)
    return 0
}

private func autogo_ocr(_ L: OpaquePointer?) -> Int32 {
    guard let L = L else { return 0 }
    let text = OCREngine.shared.recognizeSync() ?? ""
    lua_pushstring(L, text)
    return 1
}
