import UIKit

/// 悬浮调试窗口 —— 显示脚本运行状态
/// 参考 AutoLua 的 _STHud (CATextLayer 叠加到最顶层窗口)
final class HudOverlay {
    static let shared = HudOverlay()

    private var hudWindow: UIWindow?
    private var textLabel: UILabel?
    private var bgView: UIView?

    private init() {}

    // MARK: - 显示 / 隐藏

    /// 显示浮窗文本
    func show(text: String, position: (x: CGFloat, y: CGFloat)? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.showInternal(text: text, position: position)
        }
    }

    /// 更新文本 (不改变位置)
    func update(text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.textLabel?.text = text
            self?.sizeToFit()
        }
    }

    /// 隐藏浮窗
    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.hudWindow?.isHidden = true
            self?.hudWindow = nil
            self?.textLabel = nil
            self?.bgView = nil
        }
    }

    /// 设置位置
    func setPosition(x: CGFloat, y: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            guard let bg = self?.bgView, let window = self?.hudWindow else { return }
            bg.frame.origin = CGPoint(x: x, y: y)
            window.frame = CGRect(origin: .zero, size: UIScreen.main.bounds.size)
        }
    }

    /// 是否正在显示
    var isShowing: Bool {
        return hudWindow != nil && !(hudWindow?.isHidden ?? true)
    }

    // MARK: - 便捷方法

    /// 显示 Toast 样式提示 (自动消失)
    func toast(_ text: String, duration: TimeInterval = 1.5) {
        show(text: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.hide()
        }
    }

    // MARK: - 内部实现

    private func showInternal(text: String, position: (x: CGFloat, y: CGFloat)? = nil) {
        // 确保旧窗口清理
        hudWindow?.isHidden = true

        let screenSize = UIScreen.main.bounds.size

        // 创建独立 UIWindow (windowScene 方式，iOS 13+)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.frame = CGRect(origin: .zero, size: screenSize)
        window.windowLevel = .alert + 100  // 最顶层
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false  // 穿透触摸

        // 背景视图 (半透明黑底)
        let bg = UIView()
        bg.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        bg.layer.cornerRadius = 8
        bg.clipsToBounds = true

        // 文本标签
        let label = UILabel()
        label.text = text
        label.textColor = UIColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0)  // 绿色终端风
        label.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        label.numberOfLines = 0
        label.textAlignment = .center

        bg.addSubview(label)
        window.addSubview(bg)
        window.isHidden = false

        // 计算尺寸
        let maxWidth = screenSize.width - 40
        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth - 16, height: screenSize.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: label.font!],
            context: nil
        )
        let bw = min(textSize.width + 20, maxWidth)
        let bh = textSize.height + 14
        bg.frame = CGRect(x: 0, y: 0, width: bw, height: bh)
        label.frame = CGRect(x: 10, y: 7, width: bw - 20, height: textSize.height)

        // 默认位置：屏幕顶部居中
        if let pos = position {
            bg.frame.origin = CGPoint(x: pos.x, y: pos.y)
        } else {
            bg.center = CGPoint(x: screenSize.width / 2, y: 60)
        }

        self.hudWindow = window
        self.textLabel = label
        self.bgView = bg
    }

    private func sizeToFit() {
        guard let label = textLabel, let bg = bgView, let text = label.text else { return }
        let screenSize = UIScreen.main.bounds.size
        let maxWidth = screenSize.width - 40
        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth - 16, height: screenSize.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: label.font!],
            context: nil
        )
        let bw = min(textSize.width + 20, maxWidth)
        let bh = textSize.height + 14
        let cx = bg.center.x
        let cy = bg.center.y
        bg.frame = CGRect(x: cx - bw / 2, y: cy - bh / 2, width: bw, height: bh)
        label.frame = CGRect(x: 10, y: 7, width: bw - 20, height: textSize.height)
    }
}
