import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private var shellService: ShellService?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        LogManager.shared.info("AutoGo 启动中...")

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ScriptViewController()
        window?.makeKeyAndVisible()

        setupBackgroundAudio()
        startShellService()

        // 启动流式截图
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            ScreenCapture.shared.startStreaming(fps: 20)
            LogManager.shared.info("流式截图已启动 (20fps)")
        }

        let dev = UIDevice.current
        LogManager.shared.info("设备: \(dev.model) | iOS \(dev.systemVersion) | 端口: 9999")

        return true
    }

    // MARK: - Background Audio (Keep Alive)

    private var audioPlayer: AVAudioPlayer?

    private func setupBackgroundAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        startSilentAudio()
    }

    private func startSilentAudio() {
        guard let url = createSilentWAV() else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.0
            audioPlayer?.play()
        } catch {
            print("Audio player error: \(error)")
        }
    }

    private func createSilentWAV() -> URL? {
        let tempDir = NSTemporaryDirectory()
        let url = URL(fileURLWithPath: tempDir).appendingPathComponent("silent.wav")

        let sampleRate: UInt32 = 44100
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples: UInt32 = sampleRate
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = numSamples * UInt32(blockAlign)
        let fileSize: UInt32 = 44 + dataSize

        var data = Data(capacity: 44 + Int(dataSize))

        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: (fileSize - 8).littleEndian, Array.init))
        data.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init)) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))

        // data chunk
        data.append("data".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))

        // silence
        let silence = Data(count: Int(dataSize))
        data.append(silence)

        try? data.write(to: url)
        return url
    }

    // MARK: - Shell Service

    private func startShellService() {
        shellService = ShellService()
        shellService?.start()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        startSilentAudio()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // keep alive
    }

    func applicationWillTerminate(_ application: UIApplication) {
        ScreenCapture.shared.stopStreaming()
        shellService?.stop()
    }
}

import AVFoundation
