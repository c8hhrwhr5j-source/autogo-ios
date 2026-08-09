import UIKit
import AVFoundation
import WebKit

// MARK: - 应用入口

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        print("[AutoGo] AppDelegate 启动")

        // 启动后台保活音频（空音频循环）
        startBackgroundAudio()

        // 启动核心服务
        AutoGoCore.shared.start()

        // 创建主窗口
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: MainViewController())
        window.makeKeyAndVisible()
        self.window = window

        // 延迟显示悬浮球，避免启动时布局异常
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            _ = FloatingOverlay.shared
        }

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        print("[AutoGo] 进入后台，保持HTTP服务运行")
        // 重新播放空音频，保持后台存活
        startBackgroundAudio()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        print("[AutoGo] 返回前台")
    }

    // MARK: - 后台保活音频

    private var audioPlayer: AVAudioPlayer?

    private func startBackgroundAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            // 1秒 16-bit 单声道静音 WAV
            let wavData = createSilentWAV(duration: 1.0, sampleRate: 44100)
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.001
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            print("[AutoGo] 后台音频保活已启动")
        } catch {
            print("[AutoGo] 后台音频启动失败: \(error)")
        }
    }

    private func createSilentWAV(duration: Double, sampleRate: Double) -> Data {
        let totalSamples = Int(sampleRate * duration)
        let byteCount = totalSamples * 2 // 16-bit mono
        let silence = Data(count: byteCount)

        var data = Data()

        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            data.append(contentsOf: Swift.withUnsafeBytes(of: &v) { Array($0) })
        }

        data.append(contentsOf: "RIFF".utf8)
        appendLE(UInt32(36 + byteCount)) // chunk size
        data.append(contentsOf: "WAVE".utf8)

        data.append(contentsOf: "fmt ".utf8)
        appendLE(UInt32(16))            // subchunk size
        appendLE(UInt16(1))             // PCM
        appendLE(UInt16(1))             // channels
        appendLE(UInt32(sampleRate))    // sample rate
        appendLE(UInt32(sampleRate * 2))// byte rate
        appendLE(UInt16(2))             // block align
        appendLE(UInt16(16))            // bits per sample

        data.append(contentsOf: "data".utf8)
        appendLE(UInt32(byteCount))
        data.append(silence)

        return data
    }
}
