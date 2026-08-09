import Foundation
import JavaScriptCore

class ScriptEngine {

    // MARK: - Lua

    func runLua(_ script: String) -> String {
        return captureStdout {
            let lua = LuaState()
            lua.openLibs()
            let status = lua.loadString(script)
            if status == 0 {
                lua.pcall(0, 0, 0)
            } else {
                if let err = lua.toString(-1) {
                    print("Lua error: \(err)")
                }
            }
            lua.close()
        }
    }

    // MARK: - JavaScript

    func runJS(_ script: String) -> String {
        return captureStdout {
            let ctx = JSContext()!
            ctx.exceptionHandler = { _, exception in
                print("JS Error: \(exception?.toString() ?? "unknown")")
            }

            // expose native bridge
            let bridge: @convention(block) (String) -> Void = { msg in
                print("JS bridge: \(msg)")
            }
            ctx.setObject(bridge, forKeyedSubscript: "nativeLog" as NSCopying & NSObjectProtocol)
            ctx.setObject(UIDevice.current.model,
                          forKeyedSubscript: "deviceModel" as NSCopying & NSObjectProtocol)

            ctx.evaluateScript(script)
        }
    }

    // MARK: - Helpers

    private func captureStdout(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let orig = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        pipe.fileHandleForWriting.closeFile()

        block()

        fflush(stdout)
        dup2(orig, STDOUT_FILENO)
        close(orig)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

import UIKit

// MARK: - Minimal Lua C Bridge

private typealias lua_State = UnsafeMutablePointer<lua_State_t>

private struct lua_State_t { private init() {} }

private func luaL_newstate() -> lua_State? {
    guard let ptr = dlsym(dlopen(nil, RTLD_LAZY), "luaL_newstate") else { return nil }
    typealias F = @convention(c) () -> lua_State
    return unsafeBitCast(ptr, to: F.self)()
}

class LuaState {
    private var L: lua_State?

    init() {
        L = luaL_newstate()
    }

    deinit {
        if let L = L {
            let f = dlsym(dlopen(nil, RTLD_LAZY), "lua_close")
            typealias CF = @convention(c) (lua_State) -> Void
            unsafeBitCast(f, to: CF.self)(L)
        }
    }

    func openLibs() {
        guard let L = L, let f = dlsym(dlopen(nil, RTLD_LAZY), "luaL_openlibs") else { return }
        typealias CF = @convention(c) (lua_State) -> Void
        unsafeBitCast(f, to: CF.self)(L)
    }

    func loadString(_ s: String) -> Int32 {
        guard let L = L, let f = dlsym(dlopen(nil, RTLD_LAZY), "luaL_loadstring") else { return 1 }
        typealias CF = @convention(c) (lua_State, UnsafePointer<CChar>) -> Int32
        return unsafeBitCast(f, to: CF.self)(L, (s as NSString).utf8String!)
    }

    func pcall(_ nargs: Int32, _ nresults: Int32, _ errfunc: Int32) {
        guard let L = L, let f = dlsym(dlopen(nil, RTLD_LAZY), "lua_pcall") else { return }
        typealias CF = @convention(c) (lua_State, Int32, Int32, Int32) -> Int32
        _ = unsafeBitCast(f, to: CF.self)(L, nargs, nresults, errfunc)
    }

    func toString(_ index: Int32) -> String? {
        guard let L = L, let f = dlsym(dlopen(nil, RTLD_LAZY), "lua_tolstring") else { return nil }
        typealias CF = @convention(c) (lua_State, Int32, UnsafeMutablePointer<Int>) -> UnsafePointer<CChar>?
        let ptr = unsafeBitCast(f, to: CF.self)(L, index, nil)
        return ptr.map { String(cString: $0) }
    }

    func close() {
        guard let L = L, let f = dlsym(dlopen(nil, RTLD_LAZY), "lua_close") else { return }
        typealias CF = @convention(c) (lua_State) -> Void
        unsafeBitCast(f, to: CF.self)(L)
        self.L = nil
    }
}

import Darwin
