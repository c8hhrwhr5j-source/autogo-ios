import UIKit

// MARK: - IOHIDEvent 私有 API
@_silgen_name("IOHIDEventCreateDigitizerEvent")
func IOHIDEventCreateDigitizerEvent(
    _ allocator: CFAllocator?, _ timestamp: UInt64, _ type: UInt32,
    _ index: UInt32, _ identity: UInt32, _ eventMask: UInt32,
    _ buttonMask: UInt32, _ x: Double, _ y: Double, _ z: Double,
    _ transX: Double, _ transY: Double, _ transZ: Double,
    _ range: UInt32, _ touch: UInt32, _ options: UInt32
) -> Unmanaged<AnyObject>

@_silgen_name("IOHIDEventSetSenderID")
func IOHIDEventSetSenderID(_ event: Unmanaged<AnyObject>, _ senderID: UInt64)

@_silgen_name("IOHIDEventPostEvent")
func IOHIDEventPostEvent(_ connection: AnyObject, _ event: AnyObject, _ dest: Int32)

/// 触摸控制器 —— 基于 IOHIDEvent 私有 API 注入系统级触摸事件
/// 支持多点触控 (finger 0~9) 和精准延时控制
final class TouchController {
    static let shared = TouchController()

    // 事件类型常量 (来自 IOHIDEventTypes.h)
    private let kDigitizerTypeHand: UInt32   = 2   // 手指触摸
    private let kDigitizerEventRange: UInt32    = 1
    private let kDigitizerEventTouch: UInt32    = 1
    private let kDigitizerEventIdentity: UInt32 = 2

    // 事件阶段位掩码
    private let maskTouch: UInt32    = 1 << 0   // 触摸存在
    private let maskRange: UInt32    = 1 << 1   // 范围内
    private let maskAttribute: UInt32 = 1 << 2  // 属性变化 (用于 ended)

    private let senderID: UInt64 = 0x8000000817310012
    private let ioHIDEventConnection: AnyObject?

    private init() {
        ioHIDEventConnection = IOHIDEventSystemConnection()
    }

    // MARK: - 底层：单指事件

    /// 手指按下
    /// - Parameters:
    ///   - x: 屏幕 X 坐标 (逻辑像素)
    ///   - y: 屏幕 Y 坐标 (逻辑像素)
    ///   - fingerIndex: 手指编号 0~9，默认 0
    func touchDown(x: Double, y: Double, fingerIndex: UInt32 = 0) {
        let timestamp = machAbsoluteTime()
        let mask = maskTouch | maskRange
        let event = IOHIDEventCreateDigitizerEvent(
            nil, timestamp, kDigitizerTypeHand,
            fingerIndex, kDigitizerEventIdentity,
            mask, 0, x, y, 0, 0, 0, 0,
            kDigitizerEventRange, kDigitizerEventTouch, 0
        )
        IOHIDEventSetSenderID(event, senderID)
        IOHIDEventPostEvent(ioHIDEventConnection as AnyObject, event.takeRetainedValue(), 0)
    }

    /// 手指移动
    func touchMove(x: Double, y: Double, fingerIndex: UInt32 = 0) {
        let timestamp = machAbsoluteTime()
        let mask = maskTouch | maskRange
        let event = IOHIDEventCreateDigitizerEvent(
            nil, timestamp, kDigitizerTypeHand,
            fingerIndex, kDigitizerEventIdentity,
            mask, 0, x, y, 0, 0, 0, 0,
            kDigitizerEventRange, kDigitizerEventTouch, 0
        )
        IOHIDEventSetSenderID(event, senderID)
        IOHIDEventPostEvent(ioHIDEventConnection as AnyObject, event.takeRetainedValue(), 0)
    }

    /// 手指抬起
    func touchUp(x: Double, y: Double, fingerIndex: UInt32 = 0) {
        let timestamp = machAbsoluteTime()
        let mask = maskAttribute
        let event = IOHIDEventCreateDigitizerEvent(
            nil, timestamp, kDigitizerTypeHand,
            fingerIndex, kDigitizerEventIdentity,
            mask, 0, x, y, 0, 0, 0, 0,
            kDigitizerEventRange, kDigitizerEventTouch, 0
        )
        IOHIDEventSetSenderID(event, senderID)
        IOHIDEventPostEvent(ioHIDEventConnection as AnyObject, event.takeRetainedValue(), 0)
    }

    // MARK: - 高级：单指操作

    /// 基础点击 (按下 → 等待 delayMs → 抬起)
    /// delayMs 默认 30ms，模拟快速点击
    func tap(x: Double, y: Double, delayMs: Int = 30) {
        touchDown(x: x, y: y)
        preciseSleep(milliseconds: delayMs)
        touchUp(x: x, y: y)
    }

    /// 长按 (按下 → 保持 durationMs → 抬起)
    func longPress(x: Double, y: Double, durationMs: Int = 800) {
        touchDown(x: x, y: y)
        preciseSleep(milliseconds: durationMs)
        touchUp(x: x, y: y)
    }

    /// 滑动 (从 fromX,fromY 匀速移动到 toX,toY)
    func swipe(fromX: Double, fromY: Double, toX: Double, toY: Double,
               durationMs: Int = 300, steps: Int = 30) {
        guard steps > 0 else { return }
        let stepTime = durationMs / steps
        let dx = (toX - fromX) / Double(steps)
        let dy = (toY - fromY) / Double(steps)

        touchDown(x: fromX, y: fromY)
        for i in 1...steps {
            preciseSleep(milliseconds: stepTime)
            let x = fromX + dx * Double(i)
            let y = fromY + dy * Double(i)
            touchMove(x: x, y: y)
        }
        preciseSleep(milliseconds: 20)
        touchUp(x: toX, y: toY)
    }

    // MARK: - 高级：多点触控

    /// 多点同时按下
    /// - Parameter points: [(x, y)] 数组，每个元素对应一个手指
    ///   例如 [(100,200), (300,400)] 表示食指按 (100,200)，中指按 (300,400)
    func multiTouchDown(_ points: [(x: Double, y: Double)]) {
        for (i, pt) in points.enumerated() {
            touchDown(x: pt.x, y: pt.y, fingerIndex: UInt32(i))
        }
    }

    /// 多点同时抬起
    func multiTouchUp(_ points: [(x: Double, y: Double)]) {
        for (i, pt) in points.enumerated() {
            touchUp(x: pt.x, y: pt.y, fingerIndex: UInt32(i))
        }
    }

    /// 多点同时点击 (双指缩放等手势)
    func multiTap(_ points: [(x: Double, y: Double)], delayMs: Int = 30) {
        multiTouchDown(points)
        preciseSleep(milliseconds: delayMs)
        multiTouchUp(points)
    }

    /// 双指缩放
    /// - Parameters:
    ///   - centerX / centerY: 缩放中心点
    ///   - fromDistance: 起始两指间距
    ///   - toDistance: 目标两指间距
    func pinch(centerX: Double, centerY: Double,
               fromDistance: Double, toDistance: Double,
               durationMs: Int = 300, steps: Int = 20) {
        guard steps > 0 else { return }
        let stepTime = durationMs / steps
        let dDist = (toDistance - fromDistance) / Double(steps)

        for i in 0...steps {
            let dist = fromDistance + dDist * Double(i)
            let half = dist / 2
            let p1 = (x: centerX - half, y: centerY)
            let p2 = (x: centerX + half, y: centerY)

            if i == 0 {
                multiTouchDown([p1, p2])
            } else if i == steps {
                multiTouchUp([p1, p2])
            } else {
                touchMove(x: p1.x, y: p1.y, fingerIndex: 0)
                touchMove(x: p2.x, y: p2.y, fingerIndex: 1)
            }
            if i < steps { preciseSleep(milliseconds: stepTime) }
        }
    }

    // MARK: - 辅助

    private func preciseSleep(milliseconds: Int) {
        if milliseconds <= 0 { return }
        var ts = timespec(tv_sec: milliseconds / 1000,
                          tv_nsec: (milliseconds % 1000) * 1_000_000)
        nanosleep(&ts, nil)
    }

    private func machAbsoluteTime() -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let now = mach_absolute_time()
        return now * UInt64(info.numer) / UInt64(info.denom)  // → 纳秒
    }

    private func IOHIDEventSystemConnection() -> AnyObject? {
        typealias IOHIDEventSystemClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
        typealias IOHIDEventSystemClientDispatchEventQueueCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?

        guard let IOKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            return nil
        }
        guard let clientCreate = dlsym(IOKit, "IOHIDEventSystemClientCreate") else {
            return nil
        }
        let createFn = unsafeBitCast(clientCreate, to: IOHIDEventSystemClientCreate.self)
        return createFn(nil)?.takeRetainedValue()
    }
}
