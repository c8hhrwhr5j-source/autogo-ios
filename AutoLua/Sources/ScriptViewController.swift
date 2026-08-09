import UIKit

/// 主容器 — 底部双Tab切换 (脚本 / 设置)
final class ScriptViewController: UIViewController {

    // MARK: - Child VCs

    private let scriptsVC = ScriptsViewController()
    private let settingsVC = SettingsViewController()

    // MARK: - Bottom Bar

    private let bottomBar = UIView()
    private let scriptsBtn = UIButton(type: .system)
    private let settingsBtn = UIButton(type: .system)
    private let indicator = UIView()

    private var activeTab: Int = 0 {
        didSet { updateTabAppearance() }
    }

    // MARK: - Container

    private let contentContainer = UIView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupContent()
        setupBottomBar()
        switchToTab(0, animated: false)
    }

    // MARK: - Content

    private func setupContent() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: safe.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -60),
        ])
    }

    // MARK: - Bottom Bar

    private func setupBottomBar() {
        bottomBar.backgroundColor = .secondarySystemBackground
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.topAnchor.constraint(equalTo: safe.bottomAnchor, constant: -54),
        ])

        // Top border line
        let border = UIView()
        border.backgroundColor = UIColor.separator
        border.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(border)
        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            border.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        // Scripts button (left)
        scriptsBtn.setTitle("📜 脚本", for: .normal)
        scriptsBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        scriptsBtn.setTitleColor(.systemGray, for: .normal)
        scriptsBtn.tag = 0
        scriptsBtn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        scriptsBtn.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(scriptsBtn)

        // Settings button (right)
        settingsBtn.setTitle("⚙️ 设置", for: .normal)
        settingsBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        settingsBtn.setTitleColor(.systemGray, for: .normal)
        settingsBtn.tag = 1
        settingsBtn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        settingsBtn.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(settingsBtn)

        // Active indicator — frame-based positioning
        indicator.backgroundColor = .systemGreen
        indicator.layer.cornerRadius = 2
        indicator.frame = CGRect(x: 0, y: 2, width: 32, height: 3)
        bottomBar.addSubview(indicator)

        NSLayoutConstraint.activate([
            scriptsBtn.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 4),
            scriptsBtn.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            scriptsBtn.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor),
            scriptsBtn.widthAnchor.constraint(equalTo: bottomBar.widthAnchor, multiplier: 0.5),

            settingsBtn.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 4),
            settingsBtn.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            settingsBtn.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor),
            settingsBtn.widthAnchor.constraint(equalTo: bottomBar.widthAnchor, multiplier: 0.5),
        ])
    }

    // MARK: - Tab Switching

    @objc private func tabTapped(_ sender: UIButton) {
        guard sender.tag != activeTab else { return }
        switchToTab(sender.tag, animated: true)
    }

    private func switchToTab(_ index: Int, animated: Bool) {
        activeTab = index

        // Remove old VC
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }

        // Add new VC
        let vc = (index == 0) ? scriptsVC : settingsVC
        addChild(vc)
        vc.view.frame = contentContainer.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentContainer.addSubview(vc.view)
        vc.didMove(toParent: self)
    }

    private func updateTabAppearance() {
        let activeColor = UIColor.systemGreen
        let inactiveColor = UIColor.systemGray

        scriptsBtn.setTitleColor(activeTab == 0 ? activeColor : inactiveColor, for: .normal)
        settingsBtn.setTitleColor(activeTab == 1 ? activeColor : inactiveColor, for: .normal)

        // Frame-based indicator animation (runs after layout)
        DispatchQueue.main.async {
            let btn = (self.activeTab == 0) ? self.scriptsBtn : self.settingsBtn
            let targetX = btn.frame.midX - 16
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
                self.indicator.frame.origin.x = targetX
            }
        }
    }
}
