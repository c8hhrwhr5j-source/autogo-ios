import UIKit

/// 脚本编辑运行界面
final class ScriptViewController: UIViewController {

    // MARK: - UI

    private let titleLabel = UILabel()
    private let codeEditor = UITextView()
    private let runButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let outputView = UITextView()
    private let infoLabel = UILabel()
    private let actionStack = UIStackView()

    private var isRunning = false
    private var runQueue = DispatchQueue(label: "autogo.ui.run")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateInfo()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)

        // Title
        titleLabel.text = "AutoGo"
        titleLabel.textColor = .systemGreen
        titleLabel.font = .boldSystemFont(ofSize: 28)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Code editor
        codeEditor.backgroundColor = UIColor(white: 0.12, alpha: 1)
        codeEditor.textColor = .white
        codeEditor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        codeEditor.text = "// 输入 JavaScript 脚本\n// 可用 API: autogo.capture(), autogo.findColor(...),\n//           autogo.tap(x, y), autogo.sleep(ms), 等\n\nautogo.captureWait(2);\nautogo.showHud(\"AutoGo Ready\");\nautogo.sleep(1000);\nautogo.hideHud();"
        codeEditor.autocorrectionType = .no
        codeEditor.autocapitalizationType = .none
        codeEditor.smartQuotesType = .no
        codeEditor.layer.cornerRadius = 6
        codeEditor.layer.borderWidth = 1
        codeEditor.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.3).cgColor
        codeEditor.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(codeEditor)

        // Run button
        runButton.setTitle("▶ 运行", for: .normal)
        runButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        runButton.backgroundColor = .systemGreen
        runButton.setTitleColor(.white, for: .normal)
        runButton.layer.cornerRadius = 8
        runButton.addTarget(self, action: #selector(runScript), for: .touchUpInside)
        runButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(runButton)

        // Stop button
        stopButton.setTitle("■ 停止", for: .normal)
        stopButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        stopButton.backgroundColor = .systemRed
        stopButton.setTitleColor(.white, for: .normal)
        stopButton.layer.cornerRadius = 8
        stopButton.isEnabled = false
        stopButton.alpha = 0.5
        stopButton.addTarget(self, action: #selector(stopScript), for: .touchUpInside)
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stopButton)

        // Quick actions
        actionStack.axis = .horizontal
        actionStack.spacing = 6
        actionStack.distribution = .fillEqually
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let actions: [(String, Selector)] = [
            ("抓屏", #selector(quickCapture)),
            ("找色", #selector(quickFindColor)),
            ("OCR", #selector(quickOCR)),
            ("信息", #selector(quickInfo)),
        ]
        for (title, sel) in actions {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            btn.backgroundColor = UIColor(white: 0.2, alpha: 1)
            btn.setTitleColor(.systemGreen, for: .normal)
            btn.layer.cornerRadius = 6
            btn.addTarget(self, action: sel, for: .touchUpInside)
            btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
            actionStack.addArrangedSubview(btn)
        }
        view.addSubview(actionStack)

        // Output
        outputView.backgroundColor = UIColor(white: 0.05, alpha: 1)
        outputView.textColor = .systemGreen
        outputView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        outputView.isEditable = false
        outputView.text = "> AutoGo Ready. 端口: 9999\n> 点击 ▶ 运行 执行脚本\n"
        outputView.layer.cornerRadius = 6
        outputView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outputView)

        // Info label
        infoLabel.textColor = UIColor(white: 0.4, alpha: 1)
        infoLabel.font = .systemFont(ofSize: 10)
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 0
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoLabel)

        // Layout
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),

            codeEditor.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            codeEditor.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            codeEditor.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            codeEditor.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.25),

            actionStack.topAnchor.constraint(equalTo: codeEditor.bottomAnchor, constant: 6),
            actionStack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            actionStack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),

            runButton.topAnchor.constraint(equalTo: actionStack.bottomAnchor, constant: 6),
            runButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            runButton.trailingAnchor.constraint(equalTo: safe.centerXAnchor, constant: -6),
            runButton.heightAnchor.constraint(equalToConstant: 40),

            stopButton.topAnchor.constraint(equalTo: actionStack.bottomAnchor, constant: 6),
            stopButton.leadingAnchor.constraint(equalTo: safe.centerXAnchor, constant: 6),
            stopButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            stopButton.heightAnchor.constraint(equalToConstant: 40),

            outputView.topAnchor.constraint(equalTo: runButton.bottomAnchor, constant: 8),
            outputView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            outputView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            outputView.bottomAnchor.constraint(equalTo: infoLabel.topAnchor, constant: -4),

            infoLabel.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8),
            infoLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            infoLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
        ])
    }

    // MARK: - Actions

    @objc private func runScript() {
        let code = codeEditor.text ?? ""
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendOutput("> 脚本为空，请先输入代码\n")
            return
        }
        isRunning = true
        runButton.isEnabled = false; runButton.alpha = 0.5
        stopButton.isEnabled = true; stopButton.alpha = 1.0
        appendOutput("> 执行中...\n")

        runQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            let result = ScriptEngine.shared.runJS(code)
            DispatchQueue.main.async {
                self.appendOutput(result.isEmpty ? "> 完成 (无输出)\n" : "\(result)\n> 完成\n")
                self.scriptFinished()
            }
        }
    }

    @objc private func stopScript() {
        isRunning = false
        appendOutput("> ⏹ 已停止\n")
        scriptFinished()
    }

    private func scriptFinished() {
        isRunning = false
        runButton.isEnabled = true; runButton.alpha = 1.0
        stopButton.isEnabled = false; stopButton.alpha = 0.5
    }

    // MARK: - Quick Actions

    @objc private func quickCapture() {
        appendOutput("> 截图...\n")
        runQueue.async { [weak self] in
            let ok = ScreenCapture.shared.captureImage() != nil
            DispatchQueue.main.async {
                self?.appendOutput(ok ? "> 截图成功\n" : "> 截图失败\n")
            }
        }
    }

    @objc private func quickFindColor() {
        appendOutput("> 找色 (红色 255,0,0)...\n")
        runQueue.async { [weak self] in
            let pts = ScreenCapture.shared.findColor(r: 255, g: 0, b: 0, tolerance: 10, maxResults: 5)
            DispatchQueue.main.async {
                if pts.isEmpty {
                    self?.appendOutput("> 未找到红色\n")
                } else {
                    self?.appendOutput("> 找到 \(pts.count) 个: \(pts.map { "(\($0.x),\($0.y))" }.joined(separator: ", "))\n")
                }
            }
        }
    }

    @objc private func quickOCR() {
        appendOutput("> OCR 识别中...\n")
        runQueue.async { [weak self] in
            let text = OCREngine.shared.recognizeSync() ?? "识别失败"
            DispatchQueue.main.async {
                self?.appendOutput("> OCR: \(text)\n")
            }
        }
    }

    @objc private func quickInfo() {
        updateInfo()
        appendOutput("> 信息已刷新\n")
    }

    // MARK: - Helpers

    private func appendOutput(_ text: String) {
        let current = outputView.text ?? ""
        outputView.text = current + text
        if outputView.text.count > 0 {
            let bottom = NSMakeRange(outputView.text.count - 1, 1)
            outputView.scrollRangeToVisible(bottom)
        }
    }

    private func updateInfo() {
        let dev = UIDevice.current
        let scr = UIScreen.main
        let streaming = ScreenCapture.shared.isStreaming
        infoLabel.text = "\(dev.model) | iOS \(dev.systemVersion) | "
            + "屏幕: \(Int(scr.bounds.width))x\(Int(scr.bounds.height)) | "
            + "流式截图: \(streaming ? "ON" : "OFF") | "
            + "端口: 9999"
    }
}
