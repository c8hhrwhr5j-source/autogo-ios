import Foundation
import UIKit

// MARK: - 前台应用检测

/// 获取当前前台应用的包名、名称等信息
final class AppDetector {

    static let shared = AppDetector()

    private init() {}

    // MARK: - 当前前台应用

    /// 当前前台应用的 Bundle ID
    var foregroundBundleID: String? {
        return firstMethod() ?? secondMethod() ?? thirdMethod()
    }

    /// 当前前台应用的显示名称
    var foregroundAppName: String? {
        guard let id = foregroundBundleID else { return nil }
        return appName(for: id)
    }

    /// 当前前台应用是否为指定 Bundle ID
    func isAppInForeground(_ bundleID: String) -> Bool {
        return foregroundBundleID == bundleID
    }

    /// 当前前台应用是否匹配任一 Bundle ID
    func isAppInForeground(_ bundleIDs: [String]) -> Bool {
        guard let current = foregroundBundleID else { return false }
        return bundleIDs.contains(current)
    }

    // MARK: - 检测方法（多级降级）

    /// 方法 1：通过 runningBoard / workspace 获取
    private func firstMethod() -> String? {
        // 尝试通过私有 API LSApplicationWorkspace
        guard let workspace = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else {
            return nil
        }
        let ws = workspace.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue()
        guard let wsObj = ws as? NSObject else { return nil }

        // 获取前台应用
        let apps = wsObj.perform(NSSelectorFromString("allApplications"))?.takeUnretainedValue()
        guard let appArray = apps as? [AnyObject] else { return nil }

        for app in appArray {
            guard let appObj = app as? NSObject else { continue }
            // 检查是否是前台应用
            if let isForeground = appObj.value(forKey: "isForeground") as? Bool, isForeground {
                return appObj.value(forKey: "applicationIdentifier") as? String
            }
        }
        return nil
    }

    /// 方法 2：通过 FrontBoard 服务
    private func secondMethod() -> String? {
        guard let fbDisplay = NSClassFromString("FBDisplayManager") as? NSObject.Type else {
            return nil
        }
        let mgr = fbDisplay.perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue()
        guard let mgrObj = mgr as? NSObject else { return nil }

        // 获取主显示器
        guard let displays = mgrObj.value(forKey: "displays") as? [AnyObject],
              let mainDisplay = displays.first as? NSObject else { return nil }

        // 获取前台场景
        guard let scenes = mainDisplay.value(forKey: "scenes") as? [AnyObject] else { return nil }
        for scene in scenes {
            guard let sceneObj = scene as? NSObject else { continue }
            if let isForeground = sceneObj.value(forKey: "isForeground") as? Bool, isForeground {
                if let clientSettings = sceneObj.value(forKey: "clientSettings") as? NSObject {
                    if let bundleID = clientSettings.value(forKey: "preferredSceneHostIdentifier") as? String {
                        return bundleID
                    }
                }
            }
        }

        return nil
    }

    /// 方法 3：通过 SBApplicationController
    private func thirdMethod() -> String? {
        guard let controllerClass = NSClassFromString("SBApplicationController") as? NSObject.Type else {
            return nil
        }
        let ctrl = controllerClass.perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue()
        guard let ctrlObj = ctrl as? NSObject else { return nil }

        if let app = ctrlObj.perform(NSSelectorFromString("frontmostAppWithBundleID:"),
                                      with: "com.apple.springboard")?.takeUnretainedValue() {
            // 获取前台应用
        }

        // 获取所有应用并检查前台状态
        guard let allApps = ctrlObj.perform(NSSelectorFromString("allApplications"))?.takeUnretainedValue()
                as? [AnyObject] else { return nil }

        for app in allApps {
            guard let appObj = app as? NSObject else { continue }
            if let running = appObj.value(forKey: "isRunning") as? Bool, running {
                if let bundleID = appObj.value(forKey: "bundleIdentifier") as? String {
                    return bundleID
                }
            }
        }

        return nil
    }

    /// 方法 4：通过 ProcessInfo / sysctl（最后手段）
    private func fourthMethod() -> String? {
        // 监控前台应用变化通知
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length: size_t = 0
        if sysctl(&name, 3, nil, &length, nil, 0) == 0 {
            // 如果有权限，这里可以遍历进程列表
        }

        // 回退到获取自己
        return Bundle.main.bundleIdentifier
    }

    // MARK: - 应用信息查询

    /// 根据 Bundle ID 获取应用名称
    func appName(for bundleID: String) -> String? {
        // 方法 1：通过本地化名称
        if let name = localizedName(for: bundleID) {
            return name
        }

        // 方法 2：系统内置映射
        let known: [String: String] = [
            "com.apple.springboard": "主屏幕",
            "com.apple.mobilesafari": "Safari",
            "com.apple.Preferences": "设置",
            "com.apple.MobileSMS": "信息",
            "com.apple.mobilemail": "邮件",
            "com.apple.mobilenotes": "备忘录",
            "com.apple.camera": "相机",
            "com.apple.mobileslideshow": "照片",
            "com.apple.AppStore": "App Store",
            "com.apple.Music": "音乐",
            "com.apple.weather": "天气",
            "com.apple.Maps": "地图",
            "com.apple.Health": "健康",
            "com.apple.news": "新闻",
            "com.tencent.xin": "微信",
            "com.tencent.mqq": "QQ",
            "com.alipay.iphoneclient": "支付宝",
            "com.taobao.taobao4iphone": "淘宝",
        ]
        return known[bundleID] ?? bundleID.components(separatedBy: ".").last
    }

    private func localizedName(for bundleID: String) -> String? {
        // 尝试从 /Applications 或 /var/containers 找 .app
        return nil
    }

    /// 获取所有正在运行的应用
    var runningApplications: [(bundleID: String, name: String, pid: Int32)] {
        var apps: [(String, String, Int32)] = []

        // 通过 kinfo_proc 获取进程列表
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: size_t = 0

        // 先获取大小
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 { return [] }

        buffer.withUnsafeBytes { rawPointer in
            let base = rawPointer.baseAddress!
            var offset = 0
            while offset + MemoryLayout<kinfo_proc>.size <= size {
                let proc = base.load(fromByteOffset: offset, as: kinfo_proc.self)
                let name = withUnsafeBytes(of: proc.kp_proc.p_comm) { buf in
                    String(cString: buf.bindMemory(to: CChar.self).baseAddress!)
                }
                apps.append((bundleID: name, name: name, pid: proc.kp_proc.p_pid))
                offset += MemoryLayout<kinfo_proc>.size
            }
        }

        return apps
    }

    /// 根据 PID 获取 Bundle ID
    func bundleID(for pid: Int32) -> String? {
        // 简化实现
        return nil
    }
}
