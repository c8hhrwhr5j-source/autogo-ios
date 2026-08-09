import UIKit

/// 设置界面 — 本机信息 + 日志查看
final class SettingsViewController: UIViewController {

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // Info section
    private let infoCard = UIView()
    private let infoTitle = UILabel()
    private let infoText = UILabel()

    // Log section
    private let logCard = UIView()
    private let logTitle = UILabel()
    private let logTextView = UITextView()
    private let logRefreshBtn = UIButton(type: .system)
    private let logClearBtn = UIButton(type: .system)

    // Log file picker
    private let filePicker = UISegmentedControl()
    private var logFiles: [URL] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateDeviceInfo()
        loadLogs()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        setupInfoCard()
        setupLogCard()

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safe.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safe.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
        ])
    }

    private func setupInfoCard() {
        // Card container
        infoCard.backgroundColor = UIColor(white: 0.12, alpha: 1)
        infoCard.layer.cornerRadius = 12
        infoCard.layer.borderWidth = 1
        infoCard.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.2).cgColor
        contentStack.addArrangedSubview(infoCard)

        infoTitle.text = "📱 本机信息"
        infoTitle.textColor = .systemGreen
        infoTitle.font = .boldSystemFont(ofSize: 16)
        infoTitle.translatesAutoresizingMaskIntoConstraints = false
        infoCard.addSubview(infoTitle)

        infoText.textColor = UIColor(white: 0.75, alpha: 1)
        infoText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        infoText.numberOfLines = 0
        infoText.translatesAutoresizingMaskIntoConstraints = false
        infoCard.addSubview(infoText)

        NSLayoutConstraint.activate([
            infoTitle.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 14),
            infoTitle.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 14),
            infoTitle.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -14),

            infoText.topAnchor.constraint(equalTo: infoTitle.bottomAnchor, constant: 10),
            infoText.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 14),
            infoText.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -14),
            infoText.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: -14),
        ])
    }

    private func setupLogCard() {
        logCard.backgroundColor = UIColor(white: 0.12, alpha: 1)
        logCard.layer.cornerRadius = 12
        logCard.layer.borderWidth = 1
        logCard.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.2).cgColor
        contentStack.addArrangedSubview(logCard)

        logTitle.text = "📋 日志"
        logTitle.textColor = .systemGreen
        logTitle.font = .boldSystemFont(ofSize: 16)
        logTitle.translatesAutoresizingMaskIntoConstraints = false
        logCard.addSubview(logTitle)

        // Refresh btn
        logRefreshBtn.setTitle("刷新", for: .normal)
        logRefreshBtn.titleLabel?.font = .systemFont(ofSize: 12)
        logRefreshBtn.setTitleColor(.systemGreen, for: .normal)
        logRefreshBtn.addTarget(self, action: #selector(refreshLogs), for: .touchUpInside)
        logRefreshBtn.translatesAutoresizingMaskIntoConstraints = false
        logCard.addSubview(logRefreshBtn)

        // Clear btn
        logClearBtn.setTitle("清空", for: .normal)
        logClearBtn.titleLabel?.font = .systemFont(ofSize: 12)
        logClearBtn.setTitleColor(.systemRed, for: .normal)
        logClearBtn.addTarget(self, action: #selector(clearLogs), for: .touchUpInside)
        logClearBtn.translatesAutoresizingMaskIntoConstraints = false
        logCard.addSubview(logClearBtn)

        // File picker
        filePicker.addTarget(self, action: #selector(fileChanged), for: .valueChanged)
        filePicker.translatesAutoresizingMaskIntoConstraints = false
        logCard.addSubview(filePicker)

        // Log text
        logTextView.backgroundColor = UIColor(white: 0.05, alpha: 1)
        logTextView.textColor = .systemGreen
        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.isEditable = false
        logTextView.layer.cornerRadius = 6
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        logCard.addSubview(logTextView)

        NSLayoutConstraint.activate([
            logTitle.topAnchor.constraint(equalTo: logCard.topAnchor, constant: 14),
            logTitle.leadingAnchor.constraint(equalTo: logCard.leadingAnchor, constant: 14),

            logClearBtn.centerYAnchor.constraint(equalTo: logTitle.centerYAnchor),
            logClearBtn.trailingAnchor.constraint(equalTo: logCard.trailingAnchor, constant: -14),

            logRefreshBtn.centerYAnchor.constraint(equalTo: logTitle.centerYAnchor),
            logRefreshBtn.trailingAnchor.constraint(equalTo: logClearBtn.leadingAnchor, constant: -10),

            filePicker.topAnchor.constraint(equalTo: logTitle.bottomAnchor, constant: 10),
            filePicker.leadingAnchor.constraint(equalTo: logCard.leadingAnchor, constant: 14),
            filePicker.trailingAnchor.constraint(equalTo: logCard.trailingAnchor, constant: -14),

            logTextView.topAnchor.constraint(equalTo: filePicker.bottomAnchor, constant: 8),
            logTextView.leadingAnchor.constraint(equalTo: logCard.leadingAnchor, constant: 10),
            logTextView.trailingAnchor.constraint(equalTo: logCard.trailingAnchor, constant: -10),
            logTextView.heightAnchor.constraint(equalToConstant: 300),
            logTextView.bottomAnchor.constraint(equalTo: logCard.bottomAnchor, constant: -10),
        ])
    }

    // MARK: - Actions

    @objc private func refreshLogs() {
        loadLogs()
        LogManager.shared.info("日志已刷新")
    }

    @objc private func clearLogs() {
        let alert = UIAlertController(
            title: "清空日志",
            message: "确定清空今天日志吗？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            try? "".write(to: LogManager.shared.todayLogFile, atomically: true, encoding: .utf8)
            self?.logTextView.text = "(日志已清空)"
            LogManager.shared.info("日志已手动清空")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func fileChanged() {
        let idx = filePicker.selectedSegmentIndex
        guard idx >= 0, idx < logFiles.count else { return }
        displayLogFile(logFiles[idx])
    }

    // MARK: - Data

    private func updateDeviceInfo() {
        let dev = UIDevice.current
        let scr = UIScreen.main
        let process = ProcessInfo.processInfo

        let info = """
        设备: \(dev.name)
        型号: \(dev.model)
        系统: \(dev.systemName) \(dev.systemVersion)
        屏幕: \(Int(scr.bounds.width)) x \(Int(scr.bounds.height)) @ \(Int(scr.scale))x
        流式截图: \(ScreenCapture.shared.isStreaming ? "ON (20fps)" : "OFF")
        TCP 端口: 9999
        内存: \(process.physicalMemory / 1024 / 1024) MB
        处理器: \(process.processorCount) 核心
        运行时间: \(formatUptime(process.systemUptime))
        Bundle: \(Bundle.main.bundleIdentifier ?? "-")
        Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
        """

        infoText.text = info
    }

    private func loadLogs() {
        logFiles = LogManager.shared.listLogFiles()

        filePicker.removeAllSegments()
        if logFiles.isEmpty {
            filePicker.insertSegment(withTitle: "今天", at: 0, animated: false)
            filePicker.selectedSegmentIndex = 0
            logTextView.text = LogManager.shared.readToday()
        } else {
            for (i, file) in logFiles.enumerated() {
                let name = file.deletingPathExtension().lastPathComponent
                let short = String(name.suffix(4)) + "/" + String(name.suffix(4).prefix(2)) + "/" + String(name.prefix(4))
                filePicker.insertSegment(withTitle: file.lastPathComponent, at: i, animated: false)
            }
            filePicker.selectedSegmentIndex = 0
            displayLogFile(logFiles[0])
        }
    }

    private func displayLogFile(_ url: URL) {
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            logTextView.text = content.isEmpty ? "(空)" : content
        } else {
            logTextView.text = "(读取失败)"
        }
        // 滚动到底部
        if logTextView.text.count > 0 {
            let bottom = NSMakeRange(logTextView.text.count - 1, 1)
            logTextView.scrollRangeToVisible(bottom)
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
