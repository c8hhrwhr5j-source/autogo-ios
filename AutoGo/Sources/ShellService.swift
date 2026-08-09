import UIKit
import Network

class ShellService {
    private var listener: NWListener?
    private let port: UInt16 = 9999
    private var connections: [NWConnection] = []
    private let scriptEngine = ScriptEngine()

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    print("AutoGo listening on port \(self.port)")
                case .failed(let error):
                    print("Listener failed: \(error)")
                default: break
                }
            }
            listener?.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            listener?.start(queue: .global(qos: .background))
        } catch {
            print("Start error: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func handleConnection(_ conn: NWConnection) {
        connections.append(conn)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receive(from: conn)
            case .failed, .cancelled:
                self?.connections.removeAll(where: { $0 === conn })
            default: break
            }
        }
        conn.start(queue: .global(qos: .background))
    }

    private func receive(from conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if error != nil { return }
            if let d = data, let cmd = String(data: d, encoding: .utf8) {
                self?.execute(cmd.trimmingCharacters(in: .whitespacesAndNewlines), conn: conn)
            }
            if conn.state == .ready { self?.receive(from: conn) }
        }
    }

    private func execute(_ cmd: String, conn: NWConnection) {
        var result: String

        if cmd == "exit" {
            send("Bye\n", conn: conn)
            conn.cancel()
            return
        } else if cmd.hasPrefix("lua:") {
            result = scriptEngine.runLua(String(cmd.dropFirst(4)))
        } else if cmd.hasPrefix("js:") {
            result = scriptEngine.runJS(String(cmd.dropFirst(3)))
        } else if cmd.hasPrefix("ocr") {
            result = OCREngine.shared.recognizeSync() ?? "OCR failed"
        } else if cmd.hasPrefix("capture") {
            if let img = ScreenCapture.shared.capture(),
               let d = img.jpegData(compressionQuality: 0.7) {
                result = d.base64EncodedString()
            } else { result = "Capture failed" }
        } else if cmd == "help" {
            result = "lua:<s> js:<s> ocr capture info exit"
        } else if cmd == "info" {
            let dev = UIDevice.current
            result = "Model: \(dev.model)\nSystem: \(dev.systemName) \(dev.systemVersion)\nName: \(dev.name)"
        } else {
            result = "Unknown: \(cmd)\nType help"
        }
        send(result + "\n", conn: conn)
    }

    private func send(_ text: String, conn: NWConnection) {
        guard let d = text.data(using: .utf8) else { return }
        conn.send(content: d, completion: .contentProcessed({ _ in }))
    }
}
