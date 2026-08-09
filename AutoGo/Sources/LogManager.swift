import Foundation

/// 本地日志管理器 — 写入 Documents/Logs/ 目录
final class LogManager {
    static let shared = LogManager()

    private let logDir: URL
    private let logFile: URL
    private let dateFormatter: DateFormatter
    private let writeQueue = DispatchQueue(label: "autogo.log", qos: .utility)

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        logDir = docs.appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: nil)

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd HH:mm:ss.SSS"

        // 每天一个日志文件
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyyMMdd"
        logFile = logDir.appendingPathComponent("autogo_\(dayFmt.string(from: Date())).log")
    }

    // MARK: - 写日志

    func info(_ msg: String) { write("INFO", msg) }
    func warn(_ msg: String) { write("WARN", msg) }
    func error(_ msg: String) { write("ERROR", msg) }
    func debug(_ msg: String) { write("DEBUG", msg) }

    private func write(_ level: String, _ msg: String) {
        let ts = dateFormatter.string(from: Date())
        let line = "[\(ts)] [\(level)] \(msg)\n"

        writeQueue.async { [weak self] in
            guard let self else { return }
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFile.path) {
                    if let fh = try? FileHandle(forWritingTo: self.logFile) {
                        fh.seekToEndOfFile()
                        fh.write(data)
                        try? fh.close()
                    }
                } else {
                    try? data.write(to: self.logFile)
                }
            }
        }

        // 同步输出到控制台（debug 用）
        print("[AutoGo][\(level)] \(msg)")
    }

    // MARK: - 读取日志

    /// 读取今天的全部日志
    func readToday() -> String {
        guard FileManager.default.fileExists(atPath: logFile.path),
              let content = try? String(contentsOf: logFile, encoding: .utf8) else {
            return "(无日志)"
        }
        return content
    }

    /// 获取所有日志文件列表
    func listLogFiles() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logDir,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return files.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// 日志目录路径
    var logDirectory: URL { logDir }

    /// 今天日志文件路径
    var todayLogFile: URL { logFile }
}
