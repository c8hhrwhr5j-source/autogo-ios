import UIKit
import WebKit

// MARK: - 主界面控制器

final class MainViewController: UIViewController {

    private var webView: WKWebView!
    private var statusLabel: UILabel!
    private var addressLabel: UILabel!
    private var floatingButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1.0)
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)

        // 更新状态
        updateStatus()
    }

    // MARK: - UI 构建

    private func setupUI() {
        // 顶部状态栏区域
        let topBar = UIView()
        topBar.backgroundColor = UIColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 1.0)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        // 标题
        let titleLabel = UILabel()
        titleLabel.text = "AutoLua"
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(titleLabel)

        // 状态标签
        statusLabel = UILabel()
        statusLabel.font = UIFont.systemFont(ofSize: 11)
        statusLabel.textColor = UIColor(white: 0.5, alpha: 1.0)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(statusLabel)

        // 地址标签
        addressLabel = UILabel()
        addressLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        addressLabel.textColor = UIColor(red: 0.35, green: 0.85, blue: 0.35, alpha: 1.0)
        addressLabel.textAlignment = .right
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(addressLabel)

        // 清除按钮
        let clearBtn = UIButton(type: .system)
        clearBtn.setTitle("清除缓存", for: .normal)
        clearBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        clearBtn.setTitleColor(UIColor(white: 0.6, alpha: 1.0), for: .normal)
        clearBtn.addTarget(self, action: #selector(clearCache), for: .touchUpInside)
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(clearBtn)

        // WKWebView — 加载 HTTP 服务地址
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptEnabled = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1.0)
        webView.isOpaque = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        // 加载 Web UI
        if let url = URL(string: "http://127.0.0.1:8989/") {
            webView.load(URLRequest(url: url))
        }

        // 约束
        NSLayoutConstraint.activate([
            // Top bar
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            clearBtn.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            clearBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            addressLabel.trailingAnchor.constraint(equalTo: clearBtn.leadingAnchor, constant: -12),
            addressLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor, constant: 8),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor, constant: 8),

            // WebView
            webView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func updateStatus() {
        let screen = UIScreen.main
        addressLabel.text = "http://127.0.0.1:8989"

        DispatchQueue.global().async {
            let app = AutoLuaCore.shared.foregroundAppName
            DispatchQueue.main.async {
                self.statusLabel.text =
                    "前台: \(app) | \(Int(screen.bounds.width))x\(Int(screen.bounds.height))"
            }
        }
    }

    @objc private func clearCache() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) { [weak self] in
            self?.webView.reload()
            print("[UI] 缓存已清除")
        }
    }
}

// MARK: - WKNavigationDelegate

extension MainViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[UI] Web UI 加载完成")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[UI] Web 加载失败: \(error.localizedDescription)")

        // 等待服务器启动后重试
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.webView.reload()
        }
    }
}
