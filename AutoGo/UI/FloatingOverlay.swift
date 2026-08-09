import UIKit

// MARK: - 悬浮按钮覆盖层

/// 始终显示在屏幕上方的悬浮按钮
/// 可在其他 App 上方显示（需巨魔权限）
final class FloatingOverlay: UIWindow {

    static let shared = FloatingOverlay()

    private var overlayButton: UIButton!
    private var expandMenu: UIView?
    private var isExpanded = false
    private var lastLocation = CGPoint(x: 320, y: 200)

    private init() {
        // 使用最高层级的窗口
        super.init(windowScene: UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first!)
        self.windowLevel = UIWindow.Level(CGFloat.greatestFiniteMagnitude)
        self.isHidden = false
        self.isUserInteractionEnabled = true
        self.backgroundColor = .clear
        self.frame = UIScreen.main.bounds

        setupOverlayButton()
        setupExpandMenu()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 悬浮按钮

    private func setupOverlayButton() {
        overlayButton = UIButton(type: .custom)
        overlayButton.frame = CGRect(x: lastLocation.x, y: lastLocation.y, width: 48, height: 48)
        overlayButton.backgroundColor = UIColor(red: 0.14, green: 0.55, blue: 0.24, alpha: 0.9)
        overlayButton.layer.cornerRadius = 24
        overlayButton.layer.shadowColor = UIColor.black.cgColor
        overlayButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        overlayButton.layer.shadowRadius = 6
        overlayButton.layer.shadowOpacity = 0.4

        // 图标
        let icon = UILabel()
        icon.text = "⚡"
        icon.font = UIFont.systemFont(ofSize: 20)
        icon.textAlignment = .center
        icon.frame = overlayButton.bounds
        overlayButton.addSubview(icon)

        // 拖动
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        overlayButton.addGestureRecognizer(panGesture)

        // 点击
        overlayButton.addTarget(self, action: #selector(toggleExpand), for: .touchUpInside)

        addSubview(overlayButton)
    }

    // MARK: - 展开菜单

    private func setupExpandMenu() {
        let menu = UIView()
        menu.frame = CGRect(x: 0, y: 0, width: 160, height: 44)
        menu.backgroundColor = UIColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 0.95)
        menu.layer.cornerRadius = 12
        menu.layer.shadowColor = UIColor.black.cgColor
        menu.layer.shadowOffset = CGSize(width: 0, height: 2)
        menu.layer.shadowRadius = 8
        menu.layer.shadowOpacity = 0.5
        menu.alpha = 0

        let items = ["🔍截屏", "📋OCR", "🔄刷新", "✕关闭"]
        let itemWidth: CGFloat = 40
        let spacing: CGFloat = 0

        for (i, title) in items.enumerated() {
            let btn = UIButton(type: .system)
            btn.frame = CGRect(x: CGFloat(i) * itemWidth, y: 0, width: itemWidth, height: 44)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 11)
            btn.tag = i
            btn.addTarget(self, action: #selector(menuAction(_:)), for: .touchUpInside)
            menu.addSubview(btn)
        }

        expandMenu = menu
        addSubview(menu)
    }

    // MARK: - 手势

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let button = overlayButton else { return }
        let translation = gesture.translation(in: self)

        var newX = button.center.x + translation.x
        var newY = button.center.y + translation.y

        // 边界限制
        let halfW = button.bounds.width / 2
        newX = max(halfW, min(bounds.width - halfW, newX))
        newY = max(halfW + 40, min(bounds.height - halfW - 40, newY))

        button.center = CGPoint(x: newX, y: newY)
        gesture.setTranslation(.zero, in: self)
        lastLocation = button.frame.origin
    }

    @objc private func toggleExpand() {
        isExpanded.toggle()
        guard let menu = expandMenu else { return }

        let buttonCenter = overlayButton.center
        let menuX = max(8, min(bounds.width - 168, buttonCenter.x - 80))
        let menuY = buttonCenter.y - 60

        UIView.animate(withDuration: 0.2) {
            menu.frame.origin = CGPoint(x: menuX, y: menuY)
            menu.alpha = self.isExpanded ? 1 : 0
        }
    }

    @objc private func menuAction(_ sender: UIButton) {
        switch sender.tag {
        case 0:
            // 截屏
            DispatchQueue.global().async {
                _ = ScreenCapture.shared.capture()
                DispatchQueue.main.async {
                    self.showToast("截图已保存")
                }
            }
        case 1:
            // OCR
            DispatchQueue.global().async {
                if #available(iOS 13.0, *) {
                    OCREngine.shared.getAllText { text in
                        DispatchQueue.main.async {
                            self.showToast("识别完成: \(text.prefix(50))...")
                        }
                    }
                }
            }
        case 2:
            // 刷新
            AutoGoCore.shared.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AutoGoCore.shared.start()
                self.showToast("服务已重启")
            }
        case 3:
            // 关闭悬浮球
            isHidden = true
        default:
            break
        }

        isExpanded = false
        UIView.animate(withDuration: 0.2) {
            self.expandMenu?.alpha = 0
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        let toast = UILabel()
        toast.text = message
        toast.font = UIFont.systemFont(ofSize: 13)
        toast.textColor = .white
        toast.backgroundColor = UIColor(white: 0.1, alpha: 0.9)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 8
        toast.clipsToBounds = true
        toast.frame = CGRect(x: 40, y: 100, width: bounds.width - 80, height: 40)
        toast.alpha = 0
        addSubview(toast)

        UIView.animate(withDuration: 0.3, animations: {
            toast.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 1.5, animations: {
                toast.alpha = 0
            }) { _ in
                toast.removeFromSuperview()
            }
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 如果菜单展开，先检查菜单区域
        if isExpanded, let menu = expandMenu, menu.alpha > 0,
           menu.frame.contains(point) {
            return menu.hitTest(convert(point, to: menu), with: event)
        }

        // 检查悬浮按钮区域
        let buttonPoint = convert(point, to: overlayButton)
        if overlayButton.bounds.contains(buttonPoint) {
            return overlayButton
        }

        // 不在交互区域，穿透
        return nil
    }
}
