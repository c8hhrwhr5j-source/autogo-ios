import UIKit

/// 触摸控制器 —— 通过 Bridge ObjC 层注入 IOHIDEvent（动态加载 IOKit 私有框架）
final class TouchController {
    static let shared = TouchController()

    private let touchQueue = DispatchQueue(label: "autolua.touch", qos: .userInteractive)
    private var nextFingerID: Int32 = 1

    /// 通过 Bridge 创建 HID 事件客户端
    private lazy var hidClient: CFTypeRef = AutoLuaHIDEventSystemClientCreate().takeRetainedValue()

    // MARK: - 点击

    func tap(x: Int, y: Int) {
        let id = nextFinger()
        postTouch(phase: kAutoLuaTouchPhaseBegan, x: Float(x), y: Float(y), fingerID: id)
        Thread.sleep(forTimeInterval: 0.01)
        postTouch(phase: kAutoLuaTouchPhaseEnded, x: Float(x), y: Float(y), fingerID: id)
    }

    func longPress(x: Int, y: Int, durationMs: Int) {
        let id = nextFinger()
        postTouch(phase: kAutoLuaTouchPhaseBegan, x: Float(x), y: Float(y), fingerID: id)
        Thread.sleep(forTimeInterval: Double(durationMs) / 1000.0)
        postTouch(phase: kAutoLuaTouchPhaseEnded, x: Float(x), y: Float(y), fingerID: id)
    }

    // MARK: - 滑动

    func swipe(from fromX: Int, fromY: Int, to toX: Int, toY: Int, durationMs: Int) {
        // 简单实现：起点 → 终点 两阶段
        let id = nextFinger()
        postTouch(phase: kAutoLuaTouchPhaseBegan, x: Float(fromX), y: Float(fromY), fingerID: id)
        Thread.sleep(forTimeInterval: 0.005)
        postTouch(phase: kAutoLuaTouchPhaseMoved, x: Float(toX), y: Float(toY), fingerID: id)
        Thread.sleep(forTimeInterval: 0.01)
        postTouch(phase: kAutoLuaTouchPhaseEnded, x: Float(toX), y: Float(toY), fingerID: id)
    }

    // MARK: - 多点触控原始操作

    func touchDown(x: Int, y: Int, fingerIndex: UInt32 = 0) {
        let id = Int32(fingerIndex) + 1
        postTouch(phase: kAutoLuaTouchPhaseBegan, x: Float(x), y: Float(y), fingerID: id)
    }

    func touchUp(x: Int, y: Int, fingerIndex: UInt32 = 0) {
        let id = Int32(fingerIndex) + 1
        postTouch(phase: kAutoLuaTouchPhaseEnded, x: Float(x), y: Float(y), fingerID: id)
    }

    func touchMove(x: Int, y: Int, fingerIndex: UInt32 = 0) {
        let id = Int32(fingerIndex) + 1
        postTouch(phase: kAutoLuaTouchPhaseMoved, x: Float(x), y: Float(y), fingerID: id)
    }

    // MARK: - 多点触控组合

    func multiTap(points: [(x: Int, y: Int)]) {
        // 多点同时落下
        var ids: [Int32] = []
        for pt in points {
            let id = nextFinger()
            ids.append(id)
            postTouch(phase: kAutoLuaTouchPhaseBegan, x: Float(pt.x), y: Float(pt.y), fingerID: id)
        }
        Thread.sleep(forTimeInterval: 0.01)
        // 多点同时抬起
        for (i, pt) in points.enumerated() {
            postTouch(phase: kAutoLuaTouchPhaseEnded, x: Float(pt.x), y: Float(pt.y), fingerID: ids[i])
        }
    }

    func pinch(centerX: Int, centerY: Int, scale: Float, durationMs: Int) {
        // 双指缩放模拟：两指向外/向内移动
        let distance: Float = 50.0 * scale
        let id1 = nextFinger()
        let id2 = nextFinger()

        postTouch(phase: kAutoLuaTouchPhaseBegan, x: Float(centerX) - 30, y: Float(centerY), fingerID: id1)
        postTouch(phase: kAutoLuaTouchPhaseBegan, x: Float(centerX) + 30, y: Float(centerY), fingerID: id2)
        Thread.sleep(forTimeInterval: 0.01)

        let steps = max(1, durationMs / 10)
        for step in 1...steps {
            let t = Float(step) / Float(steps)
            let d = distance * t
            postTouch(phase: kAutoLuaTouchPhaseMoved, x: Float(centerX) - 30 - d, y: Float(centerY), fingerID: id1)
            postTouch(phase: kAutoLuaTouchPhaseMoved, x: Float(centerX) + 30 + d, y: Float(centerY), fingerID: id2)
            Thread.sleep(forTimeInterval: 0.01)
        }

        postTouch(phase: kAutoLuaTouchPhaseEnded, x: Float(centerX) - 30 - distance, y: Float(centerY), fingerID: id1)
        postTouch(phase: kAutoLuaTouchPhaseEnded, x: Float(centerX) + 30 + distance, y: Float(centerY), fingerID: id2)
    }

    // MARK: - 内部

    private func nextFinger() -> Int32 {
        nextFingerID += 1
        return nextFingerID
    }

    private func postTouch(phase: Int32, x: Float, y: Float, fingerID: Int32) {
        guard let event = AutoLuaCreateDigitizerEvent(
            0,                                          // timestamp (0 = 自动)
            kAutoLuaTransducerTypeHand,
            fingerID,                                    // index
            fingerID,                                    // identifier
            phase,                                       // eventMask (phase)
            0,                                           // buttonMask
            x, y,
            0,                                           // z
            1.0,                                         // tipPressure
            0, 0, 0, 0, 0,                                // twist, range, quality, density, irregularity
            0                                            // majorRadius
        )?.takeRetainedValue() else { return }

        // 设置发送者 ID（关键：不设置则触控不会被识别）
        AutoLuaHIDEventSetInteger(event, 0x00010000, 0x0810)

        _ = AutoLuaHIDEventSystemClientDispatchEvent(hidClient, event)
    }
}
