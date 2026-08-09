import UIKit

/// 后台脚本管理器 — 管理 Lua 脚本的完整生命周期，不依赖任何 UI 对象
/// 确保脚本在后台持续运行，闪退后自动恢复，任何情况下不主动停止就不会停
final class BackgroundScriptManager {

    static let shared = BackgroundScriptManager()

    private let runQueue = DispatchQueue(label: "autolua.bg.manager")
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    /// 是否正在运行脚本
    private(set) var isRunning: Bool = false
    /// 当前运行的脚本路径
    private(set) var currentScriptPath: String?
    /// 当前运行的脚本名称
    private(set) var currentScriptName: String?
    /// 是否启用崩溃/结束后的自动重启（手动停止时设为 false）
    var autoRestart: Bool = true

    // MARK: - Notifications

    static let stateChangedNotification = Notification.Name("BackgroundScriptManager.stateChanged")

    private init() {}

    // MARK: - App Lifecycle（由 AppDelegate 调用）

    func applicationDidLaunch() {
        // 首次启动时，从 Bundle 复制打包的 main.lua 到脚本目录
        copyBundledScriptsIfNeeded()
        // 自动启动 main.lua
        autoStartMainScript()
    }

    func applicationDidEnterBackground() {
        // 脚本运行时申请后台任务，防止被系统挂起
        if isRunning {
            beginBackgroundTask()
        }
    }

    func applicationWillEnterForeground() {
        endBackgroundTask()
    }

    // MARK: - Script Control

    /// 运行指定路径的脚本
    func startScript(name: String, path: String) {
        guard !isRunning else {
            LogManager.shared.warning("BackgroundScriptManager: 已有脚本 (\(currentScriptName ?? "?")) 在运行，跳过 \(name)")
            return
        }

        autoRestart = true  // 默认启用自动重启
        runQueue.async { [weak self] in
            guard let self = self else { return }
            self.isRunning = true
            self.currentScriptName = name
            self.currentScriptPath = path
            self.notifyStateChanged()

            LogManager.shared.info("BackgroundScriptManager: 开始执行 \(name) [\(path)]")
            let result = ScriptEngine.shared.runFile(path: path)
            LogManager.shared.info("BackgroundScriptManager: \(name) 执行完成: \(result)")

            self.isRunning = false
            self.currentScriptPath = nil
            self.currentScriptName = nil
            self.notifyStateChanged()

            // 如果启用了自动重启，且不是被手动停止的，则重新启动
            if self.autoRestart {
                LogManager.shared.info("BackgroundScriptManager: \(name) 自动重启...")
                self.startScript(name: name, path: path)
            }

            self.endBackgroundTask()
        }
    }

    /// 停止当前运行的脚本
    func stopScript() {
        autoRestart = false  // 手动停止时不自动重启
        ScriptEngine.shared.stop()
        // 等待脚本完全退出后重置状态
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if !self.isRunning { return }  // 已经被清理过了
            self.isRunning = false
            self.currentScriptPath = nil
            self.currentScriptName = nil
            self.notifyStateChanged()
            self.endBackgroundTask()
        }
    }

    // MARK: - Private: Auto-start

    /// 应用启动时自动启动 main.lua
    private func autoStartMainScript() {
        let scriptsDir = URL(fileURLWithPath: "/var/mobile/AutoLua/Scripts")
        let mainScriptURL = scriptsDir.appendingPathComponent("main.lua")

        if FileManager.default.fileExists(atPath: mainScriptURL.path) {
            LogManager.shared.info("BackgroundScriptManager: 自动启动 main.lua")
            startScript(name: "main.lua", path: mainScriptURL.path)
        } else {
            LogManager.shared.warning("BackgroundScriptManager: main.lua 未找到，跳过自动启动")
        }
    }

    /// 首次启动时从 Bundle 复制打包的 main.lua 到脚本目录
    private func copyBundledScriptsIfNeeded() {
        let scriptsDir = URL(fileURLWithPath: "/var/mobile/AutoLua/Scripts")
        let mainScriptURL = scriptsDir.appendingPathComponent("main.lua")

        // 已存在则保留用户修改版本，不覆盖
        guard !FileManager.default.fileExists(atPath: mainScriptURL.path) else { return }

        // 从 app bundle 读取
        guard let bundledPath = Bundle.main.path(forResource: "main", ofType: "lua") else {
            LogManager.shared.warning("BackgroundScriptManager: Bundle 中未找到 main.lua")
            return
        }

        // 确保目录存在
        try? FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)

        do {
            try FileManager.default.copyItem(atPath: bundledPath, toPath: mainScriptURL.path)
            LogManager.shared.info("BackgroundScriptManager: 已复制 main.lua 到 \(mainScriptURL.path)")
        } catch {
            LogManager.shared.error("BackgroundScriptManager: 复制失败: \(error)")
        }
    }

    // MARK: - Private: Background Task

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "AutoLua.ScriptRunner") { [weak self] in
            LogManager.shared.warning("BackgroundScriptManager: 后台任务即将过期")
            self?.endBackgroundTask()
        }
        if backgroundTaskId != .invalid {
            LogManager.shared.debug("BackgroundScriptManager: 后台任务已开始 id=\(backgroundTaskId.rawValue)")
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
    }

    // MARK: - Private: Notifications

    private func notifyStateChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.stateChangedNotification, object: self, userInfo: [
                "isRunning": self.isRunning,
                "scriptName": self.currentScriptName ?? "",
                "scriptPath": self.currentScriptPath ?? "",
            ])
        }
    }
}
