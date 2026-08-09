import UIKit

/// 脚本文件列表界面
final class ScriptsViewController: UIViewController {

    // MARK: - UI

    private let headerLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private let refreshButton = UIButton(type: .system)

    // MARK: - Data

    private let scriptsDir: URL = {
        let dir = URL(fileURLWithPath: "/var/mobile/AutoLua/Scripts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }()

    private var scripts: [URL] = []
    private var selectedIndex: IndexPath?
    private var isRunning = false
    private var runQueue = DispatchQueue(label: "autolua.scripts.run")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadScripts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadScripts()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Header
        headerLabel.text = "脚本列表"
        headerLabel.textColor = .systemGreen
        headerLabel.font = .boldSystemFont(ofSize: 24)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        // Refresh button
        refreshButton.setTitle("刷新", for: .normal)
        refreshButton.titleLabel?.font = .systemFont(ofSize: 14)
        refreshButton.setTitleColor(.systemGreen, for: .normal)
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(refreshButton)

        // TableView
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ScriptCell.self, forCellReuseIdentifier: "ScriptCell")
        tableView.rowHeight = 56
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        // Empty label
        emptyLabel.text = "暂无脚本文件\n\n将 .lua 文件放入\n/var/mobile/AutoLua/Scripts/"
        emptyLabel.textColor = .systemGray
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            headerLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),

            refreshButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: safe.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])
    }

    // MARK: - Data

    private func loadScripts() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: scriptsDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            scripts = []
            emptyLabel.isHidden = false
            tableView.reloadData()
            return
        }

        scripts = items.filter {
            $0.pathExtension.lowercased() == "lua"
        }.sorted { a, b in
            // 按修改时间降序
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return da > db
        }

        emptyLabel.isHidden = !scripts.isEmpty
        tableView.reloadData()

        // 清除选中状态
        selectedIndex = nil
    }

    @objc private func refreshTapped() {
        loadScripts()
        LogManager.shared.info("脚本列表已刷新, 共 \(scripts.count) 个文件")
    }

    // MARK: - Script Execution

    private func runScript(at url: URL) {
        guard !isRunning else {
            showAlert("请先停止正在运行的脚本")
            return
        }

        isRunning = true
        tableView.reloadData()

        let name = url.lastPathComponent
        LogManager.shared.info("开始执行脚本: \(name)")

        runQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            let result = ScriptEngine.shared.runFile(path: url.path)
            DispatchQueue.main.async {
                LogManager.shared.info("脚本 \(name) 执行完成")
                if !result.isEmpty { LogManager.shared.debug("输出: \(result)") }
                self.isRunning = false
                self.tableView.reloadData()
            }
        }
    }

    private func stopScript() {
        guard isRunning else { return }
        isRunning = false
        LogManager.shared.info("脚本已手动停止")
        tableView.reloadData()
    }

    private func showScriptAction(for url: URL) {
        let name = url.lastPathComponent

        let alert = UIAlertController(
            title: name,
            message: isRunning ? "脚本正在运行中" : "选择操作",
            preferredStyle: .alert
        )

        // 运行
        alert.addAction(UIAlertAction(title: "▶ 运行", style: .default) { [weak self] _ in
            self?.runScript(at: url)
        })

        // 停止
        if isRunning {
            alert.addAction(UIAlertAction(title: "■ 停止", style: .destructive) { [weak self] _ in
                self?.stopScript()
            })
        }

        // 取消
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        present(alert, animated: true)
    }

    private func showAlert(_ msg: String) {
        let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableView

extension ScriptsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        scripts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ScriptCell", for: indexPath) as! ScriptCell
        let url = scripts[indexPath.row]
        let isSelected = (indexPath == selectedIndex)
        cell.configure(url: url, isSelected: isSelected, isRunning: isRunning)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        // 切换选中状态
        if selectedIndex == indexPath {
            selectedIndex = nil
        } else {
            selectedIndex = indexPath
        }
        tableView.reloadData()

        // 弹出操作菜单
        if selectedIndex == indexPath {
            showScriptAction(for: scripts[indexPath.row])
        }
    }
}

// MARK: - Script Cell

final class ScriptCell: UITableViewCell {

    private let iconLabel = UILabel()
    private let nameLabel = UILabel()
    private let infoLabel = UILabel()
    private let checkmark = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .secondarySystemBackground
        selectionStyle = .none

        // 图标
        iconLabel.font = .systemFont(ofSize: 22)
        iconLabel.textAlignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconLabel)

        // 文件名
        nameLabel.textColor = .label
        nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        // 文件信息
        infoLabel.textColor = .systemGray
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(infoLabel)

        // 选中标记
        checkmark.image = UIImage(systemName: "checkmark.circle.fill")
        checkmark.tintColor = .systemGreen
        checkmark.isHidden = true
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(checkmark)

        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 36),

            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            nameLabel.trailingAnchor.constraint(equalTo: checkmark.leadingAnchor, constant: -8),

            infoLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            infoLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            checkmark.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmark.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 24),
            checkmark.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    func configure(url: URL, isSelected: Bool, isRunning: Bool) {
        let ext = url.pathExtension.lowercased()
        nameLabel.text = url.lastPathComponent

        // 图标
        iconLabel.text = ext == "lua" ? "🌙" : "📜"

        // 文件信息
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: url.path) {
            let size = (attrs[.size] as? Int64) ?? 0
            let modDate = attrs[.modificationDate] as? Date
            let df = DateFormatter()
            df.dateFormat = "MM-dd HH:mm"
            let ds = modDate.map { df.string(from: $0) } ?? ""
            infoLabel.text = "\(formatBytes(Int(size))) | \(ds)"
        }

        // 选中状态
        if isSelected {
            contentView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.2)
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = UIColor.systemGreen.cgColor
            checkmark.isHidden = false
        } else if isRunning {
            // 运行中 — 轻微高亮
            contentView.backgroundColor = UIColor.systemGray6
            contentView.layer.borderWidth = 0
            checkmark.isHidden = true
        } else {
            contentView.backgroundColor = .secondarySystemBackground
            contentView.layer.borderWidth = 0
            checkmark.isHidden = true
        }
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
