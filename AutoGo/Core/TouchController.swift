import Foundation
import CoreGraphics
import UIKit

// MARK: - 触摸模拟控制器（IOHIDEvent 方案）

/// 通过 IOKit HID 事件模拟触摸操作
/// 工作层级：系统底层，对所有 App 透明
final class TouchController {

    static let shared = TouchController()

    // MARK: - 动态函数指针

    private typealias CreateDigitizerEventFn = @convention(c) (
        CFAllocator?,        // allocator
        UInt64,              // timestamp
        Int32,               // transducerType (3 = hand/finger)
        Int32,               // index (手指序号 0-9)
        Int32,               // identifier (触摸 ID)
        Int32,               // eventMask
        Int32,               // buttonMask
        Float,               // x
        Float,               // y
        Float,               // z
        Float,               // tipPressure (0.0 - 1.0)
        Int32,               // twist
        Int32,               // range
        Int32,               // quality
        Int32,               // density
        Int32,               // irregularity
        Int32                // majorRadius
    ) -> Unmanaged<CFTypeRef>?

    private typealias SetFloatFn = @convention(c) (CFTypeRef, Int32, Float) -> Void
    private typealias SetIntegerFn = @convention(c) (CFTypeRef, Int32, Int32) -> Void
    private typealias CreateClientFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias DispatchEventFn = @convention(c) (CFTypeRef, CFTypeRef) -> Int32

    private var createDigitizerEvent: CreateDigitizerEventFn?
    private var setFloat: SetFloatFn?
    private var setInteger: SetIntegerFn?
    private var createClient: CreateClientFn?
    private var dispatchEvent: DispatchEventFn?

    private var hidClient: CFTypeRef?
    private var touchID: Int32 = 0

    private let IOHIDEventFieldDigitizerX: Int32       = 720896  // 0xB0000
    private let IOHIDEventFieldDigitizerY: Int32       = 720897  // 0xB0001
    private let IOHIDEventFieldDigitizerZ: Int32       = 720898  // 0xB0002
    private let IOHIDEventFieldDigitizerRange: Int32   = 720900  // 0xB0004
    private let IOHIDEventFieldDigitizerTouch: Int32   = 720901  // 0xB0005
    private let IOHIDEventFieldDigitizerPressure: Int32 = 720911 // 0xB000F

    // MARK: - Init

    private init() {
        loadIOKitFunctions()
    }

    private func loadIOKitFunctions() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            print("[TouchController] ⚠️ 无法加载 IOKit.framework，尝试备用方案")
            return
        }

        guard let sym1 = dlsym(handle, "IOHIDEventCreateDigitizerEvent"),
              let sym2 = dlsym(handle, "IOHIDEventSetFloatValue"),
              let sym3 = dlsym(handle, "IOHIDEventSetIntegerValue"),
              let sym4 = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let sym5 = dlsym(handle, "IOHIDEventSystemClientDispatchEvent")
        else {
            print("[TouchController] ⚠️ 无法解析 IOKit 函数符号")
            dlclose(handle)
            return
        }

        createDigitizerEvent = unsafeBitCast(sym1, to: CreateDigitizerEventFn.self)
        setFloat = unsafeBitCast(sym2, to: SetFloatFn.self)
        setInteger = unsafeBitCast(sym3, to: SetIntegerFn.self)
        createClient = unsafeBitCast(sym4, to: CreateClientFn.self)
        dispatchEvent = unsafeBitCast(sym5, to: DispatchEventFn.self)

        hidClient = createClient?(kCFAllocatorDefault)?.takeRetainedValue()
        print("[TouchController] ✅ IOKit HID 事件引擎就绪")
    }

    // MARK: - 触摸相位常量

    /// 触摸开始（手指按下）
    private let touchPhaseBegan: Int32   = 1
    /// 触摸移动（手指滑动中）
    private let touchPhaseMoved: Int32   = 2
    /// 触摸结束（手指抬起）
    private let touchPhaseEnded: Int32   = 3
    /// 触摸取消
    private let touchPhaseCancel: Int32  = 4

    // MARK: - 公开方法

    /// 点击指定坐标
    /// - Parameters:
    ///   - x: X 坐标（逻辑点）
    ///   - y: Y 坐标（逻辑点）
    ///   - delayMs: 按下到抬起之间的延迟（毫秒）
    /// - Returns: 是否执行成功
    @discardableResult
    func tap(x: CGFloat, y: CGFloat, delayMs: Int = 50) -> Bool {
        return executeTap(at: CGPoint(x: x, y: y), delay: Double(delayMs) / 1000.0)
    }

    /// 长按指定坐标
    /// - Parameters:
    ///   - x: X 坐标
    ///   - y: Y 坐标
    ///   - durationMs: 按住时长（毫秒）
    @discardableResult
    func longPress(x: CGFloat, y: CGFloat, durationMs: Int = 800) -> Bool {
        return executeTouchPhase(at: CGPoint(x: x, y: y), phase: touchPhaseBegan)
            && usleepAndContinue(UInt32(durationMs) * 1000)
            && executeTouchPhase(at: CGPoint(x: x, y: y), phase: touchPhaseEnded)
    }

    /// 从 (x1,y1) 滑到 (x2,y2)
    /// - Parameters:
    ///   - fromX: 起始 X
    ///   - fromY: 起始 Y
    ///   - toX: 终点 X
    ///   - toY: 终点 Y
    ///   - durationMs: 滑动持续时长（毫秒）
    ///   - steps: 分多少步（越大越平滑）
    @discardableResult
    func swipe(
        fromX: CGFloat, fromY: CGFloat,
        toX: CGFloat, toY: CGFloat,
        durationMs: Int = 300,
        steps: Int = 20
    ) -> Bool {
        let from = CGPoint(x: fromX, y: fromY)
        let to = CGPoint(x: toX, y: toY)
        let stepDelay = useconds_t(Double(durationMs) * 1000.0 / Double(steps))

        guard executeTouchPhase(at: from, phase: touchPhaseBegan) else { return false }

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            // 使用缓动曲线（ease-in-out）
            let eased = t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
            let currentX = from.x + (to.x - from.x) * eased
            let currentY = from.y + (to.y - from.y) * eased
            executeTouchPhase(at: CGPoint(x: currentX, y: currentY), phase: touchPhaseMoved)
            usleep(stepDelay)
        }

        return executeTouchPhase(at: to, phase: touchPhaseEnded)
    }

    /// 双指捏合/展开
    @discardableResult
    func pinch(
        centerX: CGFloat, centerY: CGFloat,
        startDistance: CGFloat, endDistance: CGFloat,
        durationMs: Int = 300
    ) -> Bool {
        let steps = 15
        let stepDelay = useconds_t(Double(durationMs) * 1000.0 / Double(steps))
        let halfS = startDistance / 2
        let halfE = endDistance / 2

        // 两根手指的起始位置
        let f1Start = CGPoint(x: centerX - halfS, y: centerY)
        let f2Start = CGPoint(x: centerX + halfS, y: centerY)

        executeTouchPhase(at: f1Start, phase: touchPhaseBegan, fingerIndex: 0)
        executeTouchPhase(at: f2Start, phase: touchPhaseBegan, fingerIndex: 1)

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let halfD = halfS + (halfE - halfS) * t
            executeTouchPhase(at: CGPoint(x: centerX - halfD, y: centerY), phase: touchPhaseMoved, fingerIndex: 0)
            executeTouchPhase(at: CGPoint(x: centerX + halfD, y: centerY), phase: touchPhaseMoved, fingerIndex: 1)
            usleep(stepDelay)
        }

        executeTouchPhase(at: CGPoint(x: centerX - halfE, y: centerY), phase: touchPhaseEnded, fingerIndex: 0)
        executeTouchPhase(at: CGPoint(x: centerX + halfE, y: centerY), phase: touchPhaseEnded, fingerIndex: 1)

        return true
    }

    /// 多点点击
    @discardableResult
    func multiTap(points: [(CGFloat, CGFloat)], delayMs: Int = 50) -> Bool {
        // 同时按下所有点
        for (i, point) in points.enumerated() {
            executeTouchPhase(at: CGPoint(x: point.0, y: point.1),
                              phase: touchPhaseBegan, fingerIndex: Int32(i))
        }
        usleep(UInt32(delayMs) * 1000)
        // 同时抬起
        for (i, _) in points.enumerated() {
            executeTouchPhase(at: .zero, phase: touchPhaseEnded, fingerIndex: Int32(i))
        }
        return true
    }

    // MARK: - 私有方法

    private func executeTap(at point: CGPoint, delay: TimeInterval) -> Bool {
        guard executeTouchPhase(at: point, phase: touchPhaseBegan) else { return false }
        usleep(UInt32(delay * 1_000_000))
        return executeTouchPhase(at: point, phase: touchPhaseEnded)
    }

    @discardableResult
    private func executeTouchPhase(
        at point: CGPoint,
        phase: Int32,
        fingerIndex: Int32 = 0
    ) -> Bool {
        guard let createFn = createDigitizerEvent,
              let setFloatFn = setFloat,
              let setIntFn = setInteger,
              let client = hidClient,
              let dispatchFn = dispatchEvent
        else {
            print("[TouchController] ⚠️ IOKit 不可用，使用应用内触摸模拟")
            return executeInAppTouch(at: point, phase: phase)
        }

        let touch: Int32 = (phase == touchPhaseBegan || phase == touchPhaseMoved) ? 1 : 0

        // 创建 Digitizer 事件
        guard let eventUnmanaged = createFn(
            kCFAllocatorDefault,
            machAbsoluteTime(),
            3,              // transducerType: hand/finger
            fingerIndex,    // index
            2,              // identifier
            touch,          // eventMask (1=touch, 0=no touch)
            0,              // buttonMask
            Float(point.x), // x
            Float(point.y), // y
            0,              // z
            touch == 1 ? 0.3 : 0.0, // tipPressure
            0,              // twist
            1,              // range
            1,              // quality
            1,              // density
            0,              // irregularity
            5               // majorRadius
        ) else {
            return false
        }

        let event = eventUnmanaged.takeRetainedValue()

        // 设置触摸属性
        setFloatFn(event, IOHIDEventFieldDigitizerX, Float(point.x))
        setFloatFn(event, IOHIDEventFieldDigitizerY, Float(point.y))
        setFloatFn(event, IOHIDEventFieldDigitizerPressure, touch == 1 ? 0.3 : 0.0)
        setIntFn(event, IOHIDEventFieldDigitizerTouch, touch)
        setIntFn(event, IOHIDEventFieldDigitizerRange, 1)

        // 分发事件
        let result = dispatchFn(client, event)
        return result == 0
    }

    /// 备用方案：应用内触摸模拟（仅限本 App）
    private func executeInAppTouch(at point: CGPoint, phase: Int32) -> Bool {
        guard let window = UIApplication.shared.keyWindow else { return false }
        let view = window.hitTest(point, with: nil)
        guard let targetView = view else { return false }

        switch phase {
        case touchPhaseBegan:
            targetView.touchesBegan([], with: nil)
        case touchPhaseMoved:
            targetView.touchesMoved([], with: nil)
        case touchPhaseEnded:
            targetView.touchesEnded([], with: nil)
        default:
            break
        }
        return true
    }

    // MARK: - 辅助

    private func machAbsoluteTime() -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let now = mach_absolute_time()
        return now * UInt64(info.numer) / UInt64(info.denom)
    }

    private func usleepAndContinue(_ microseconds: UInt32) -> Bool {
        usleep(microseconds)
        return true
    }

    /// 获取屏幕尺寸
    var screenSize: CGSize {
        return UIScreen.main.bounds.size
    }

    /// 获取屏幕分辨率（逻辑点）
    var screenBounds: CGRect {
        return UIScreen.main.bounds
    }
}
