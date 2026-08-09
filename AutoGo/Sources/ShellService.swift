import Foundation
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
                switch state {
                case .ready:
                    print("ShellService listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    print("ShellService failed: \(error)")
                default:
                    break
                }
            }
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: .global(qos: .background))
        } catch {
            print("ShellService start error: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
    }

    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveData(from: connection)
            case .failed, .cancelled:
                if let idx = self?.connections.firstIndex(where: { $0 === connection }) {
                    self?.connections.remove(at: idx)
                }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .background))
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let error = error {
                print("Receive error: \(error)")
                return
            }
            if let data = data, let command = String(data: data, encoding: .utf8) {
                self?.executeCommand(command.trimmingCharacters(in: .whitespacesAndNewlines), connection: connection)
            }
            if connection.state == .ready {
                self?.receiveData(from: connection)
            }
        }
    }

    private func executeCommand(_ cmd: String, connection: NWConnection) {
        var result = ""

        switch {
        case cmd == "exit":
            sendResponse("Bye", connection: connection)
            connection.cancel()
            return

        case cmd.hasPrefix("lua:"):
            let script = String(cmd.dropFirst(4))
            result = scriptEngine.runLua(script)

        case cmd.hasPrefix("js:"):
            let script = String(cmd.dropFirst(3))
            result = scriptEngine.runJS(script)

        case cmd.hasPrefix("ocr"):
            result = performOCR()

        case cmd.hasPrefix("capture"):
            result = captureScreen()

        case cmd == "help":
            result = """
            AutoGo Shell Commands:
              lua:<script>  - Run Lua script
              js:<script>   - Run JavaScript
              ocr           - OCR screen content
              capture       - Take screenshot (base64)
              info          - Device information
              exit          - Close connection
            """

        case cmd == "info":
            let device = UIDevice.current
            result = """
            Model: \(device.model)
            System: \(device.systemName) \(device.systemVersion)
            Name: \(device.name)
            """

        default:
            result = "Unknown command: \(cmd)\nType 'help' for available commands."
        }

        sendResponse(result + "\n", connection: connection)
    }

    private func sendResponse(_ text: String, connection: NWConnection) {
        guard let data = text.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed({ _ in }))
    }

    // MARK: - Actions

    private func performOCR() -> String {
        return OCREngine.shared.recognizeSync() ?? "OCR failed or no text found"
    }

    private func captureScreen() -> String {
        guard let image = ScreenCapture.shared.capture() else {
            return "Capture failed"
        }
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            return "Encode failed"
        }
        return data.base64EncodedString()
    }
}

import UIKit
