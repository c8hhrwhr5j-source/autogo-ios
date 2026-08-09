import Foundation
import Network

// MARK: - 轻量级 HTTP 服务器

/// 基于 Network.framework 的嵌入式 HTTP 服务器
/// 无需第三方依赖，iOS 12+
final class HttpServer {

    static let shared = HttpServer()

    // MARK: - 数据模型

    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let params: [String: String]
        let body: Data?
    }

    struct Response: Codable {
        let statusCode: Int
        let contentType: String
        let body: String

        static func ok(_ json: [String: Any], pretty: Bool = false) -> Response {
            let data = pretty
                ? (try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted))
                : (try? JSONSerialization.data(withJSONObject: json))
            let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return Response(statusCode: 200, contentType: "application/json; charset=utf-8", body: str)
        }

        static func error(_ message: String) -> Response {
            return .ok(["success": false, "error": message])
        }

        static func json(_ dict: [String: Any]) -> Response {
            return .ok(dict)
        }

        static func html(_ html: String) -> Response {
            return Response(statusCode: 200, contentType: "text/html; charset=utf-8", body: html)
        }

        static func fileNotFound() -> Response {
            return Response(statusCode: 404, contentType: "text/plain", body: "404 Not Found")
        }

        var httpData: Data {
            var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
            response += "Content-Type: \(contentType)\r\n"
            response += "Content-Length: \(body.utf8.count)\r\n"
            response += "Access-Control-Allow-Origin: *\r\n"
            response += "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\n"
            response += "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
            response += "Connection: close\r\n"
            response += "\r\n"
            response += body
            return response.data(using: .utf8)!
        }

        private var statusText: String {
            switch statusCode {
            case 200: return "OK"
            case 201: return "Created"
            case 204: return "No Content"
            case 301: return "Moved Permanently"
            case 400: return "Bad Request"
            case 401: return "Unauthorized"
            case 403: return "Forbidden"
            case 404: return "Not Found"
            case 405: return "Method Not Allowed"
            case 500: return "Internal Server Error"
            default: return "Unknown"
            }
        }
    }

    // MARK: - 属性

    private var listener: NWListener?
    private var isRunning = false
    private var handler: ((Request) -> Response)?
    private var port: UInt16 = 8989

    // MARK: - 公开方法

    func start(port: UInt16, handler: @escaping (Request) -> Response) {
        self.port = port
        self.handler = handler
        self.isRunning = true

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.acceptLocalOnly = false

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("[HttpServer] ❌ 端口 \(port) 创建失败: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleIncoming(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[HttpServer] ✅ 服务启动在端口 \(port)")
            case .failed(let error):
                print("[HttpServer] ❌ 启动失败: \(error)")
            case .cancelled:
                print("[HttpServer] ⏹️ 服务已停止")
            default:
                break
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        isRunning = false
        listener?.cancel()
        listener = nil
    }

    // MARK: - 连接处理

    private func handleIncoming(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[HttpServer] 连接错误: \(error)")
                connection.cancel()
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(on: connection)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in

            if let error = error {
                print("[HttpServer] 接收错误: \(error)")
                connection.cancel()
                return
            }

            guard let data = data, let request = self?.parseHTTP(data) else {
                connection.cancel()
                return
            }

            // OPTIONS preflight
            if request.method == "OPTIONS" {
                let cors = HttpServer.Response(statusCode: 204, contentType: "text/plain", body: "")
                connection.send(content: cors.httpData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            // 处理请求
            let response = self?.handler?(request) ?? HttpServer.Response.fileNotFound()
            connection.send(content: response.httpData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    // MARK: - HTTP 解析

    private func parseHTTP(_ raw: Data) -> Request? {
        guard let text = String(data: raw, encoding: .utf8) else { return nil }

        let parts = text.components(separatedBy: "\r\n\r\n")
        guard let headerSection = parts.first else { return nil }

        let body = parts.count > 1 ? parts.dropFirst().joined(separator: "\r\n\r\n").data(using: .utf8) : nil

        var lines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        lines.removeFirst()

        let requestParts = requestLine.components(separatedBy: " ")
        guard requestParts.count >= 2 else { return nil }

        let method = requestParts[0]
        var fullPath = requestParts[1]

        // 解析 headers
        var headers: [String: String] = [:]
        for line in lines {
            let colonParts = line.components(separatedBy: ": ")
            if colonParts.count >= 2 {
                headers[colonParts[0].lowercased()] = colonParts.dropFirst().joined(separator: ": ")
            }
        }

        // 解析 URL 参数
        var params: [String: String] = [:]
        var pathOnly = fullPath

        if let qIndex = fullPath.firstIndex(of: "?") {
            pathOnly = String(fullPath[..<qIndex])
            let query = String(fullPath[fullPath.index(after: qIndex)...])
            for pair in query.components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    params[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                } else if kv.count == 1 {
                    params[kv[0]] = ""
                }
            }
        }

        // 尝试从 body 解析更多参数（JSON）
        var finalBody = body
        var mergedParams = params
        if let bodyData = body, let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            for (k, v) in json {
                mergedParams[k] = "\(v)"
            }
            // body 保持原始，让处理器自行解析
        } else if let bodyStr = body.flatMap({ String(data: $0, encoding: .utf8) }) {
            // URL-encoded body
            for pair in bodyStr.components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    mergedParams[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                }
            }
        }

        return Request(
            method: method,
            path: pathOnly,
            headers: headers,
            params: mergedParams,
            body: finalBody
        )
    }

    // MARK: - 静态文件服务

    static func serveFile(_ path: String) -> Response {
        let filePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let cleanPath = filePath.isEmpty ? "index.html" : filePath

        // 优先从 Bundle 读取
        if let fileURL = Bundle.main.url(forResource: "web/\(cleanPath)", withExtension: nil),
           let data = try? Data(contentsOf: fileURL) {
            return fileResponse(data, path: cleanPath)
        }

        // 尝试直接路径
        let resPath = cleanPath.hasPrefix("web/") ? cleanPath : "web/\(cleanPath)"
        if let fileURL = Bundle.main.url(forResource: resPath, withExtension: nil),
           let data = try? Data(contentsOf: fileURL) {
            return fileResponse(data, path: cleanPath)
        }

        // 默认返回内嵌 Web UI
        if cleanPath == "index.html" || cleanPath == "" || !cleanPath.contains(".") {
            return Response.html(embeddedWebUI)
        }

        return Response.fileNotFound()
    }

    private static func fileResponse(_ data: Data, path: String) -> Response {
        let mime = mimeType(for: path)
        guard let body = String(data: data, encoding: .utf8) else {
            return Response(statusCode: 200, contentType: mime, body: "")
        }
        return Response(statusCode: 200, contentType: mime, body: body)
    }

    private static func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }

    // MARK: - 内嵌 Web UI（后备）

    static var embeddedWebUI: String {
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <title>AutoGo 控制台</title>
            <style>
                * { margin:0; padding:0; box-sizing:border-box; }
                body { font-family:-apple-system,BlinkMacSystemFont,sans-serif; background:#0d1117; color:#c9d1d9; min-height:100vh; }
                .header { background:#161b22; padding:16px; border-bottom:1px solid #30363d; }
                .header h1 { font-size:20px; color:#58a6ff; }
                .status { font-size:12px; color:#8b949e; margin-top:4px; }
                .container { max-width:600px; margin:0 auto; padding:16px; }
                .card { background:#161b22; border:1px solid #30363d; border-radius:8px; padding:16px; margin-bottom:12px; }
                .card-title { font-size:14px; font-weight:600; margin-bottom:12px; color:#58a6ff; }
                .row { display:flex; gap:8px; margin-bottom:8px; }
                input, button { font-size:14px; padding:8px 12px; border-radius:6px; border:1px solid #30363d; background:#0d1117; color:#c9d1d9; }
                input { flex:1; min-width:0; }
                input:focus { outline:none; border-color:#58a6ff; }
                button { background:#238636; border-color:#2ea043; color:#fff; cursor:pointer; white-space:nowrap; }
                button:hover { background:#2ea043; }
                button.secondary { background:#21262d; border-color:#30363d; color:#c9d1d9; }
                button.danger { background:#da3633; border-color:#f85149; }
                pre { background:#0d1117; border:1px solid #30363d; border-radius:6px; padding:12px; font-size:12px; overflow-x:auto; max-height:300px; overflow-y:auto; white-space:pre-wrap; color:#7ee787; }
                .grid-2 { display:grid; grid-template-columns:1fr 1fr; gap:8px; }
                .coord-group { display:flex; gap:4px; align-items:center; }
                .coord-group label { font-size:12px; color:#8b949e; min-width:20px; }
                .coord-group input { width:70px; flex:none; }
                .label { font-size:12px; color:#8b949e; margin-bottom:4px; }
                .flex-between { display:flex; justify-content:space-between; align-items:center; }
                a { color:#58a6ff; text-decoration:none; font-size:12px; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>⚡ AutoGo 控制台</h1>
                <div class="status" id="status">连接中...</div>
            </div>
            <div class="container">
                <div class="card">
                    <div class="card-title">👆 触摸操作</div>
                    <div class="label">点击坐标</div>
                    <div class="row">
                        <input type="number" id="tapX" placeholder="X" value="200">
                        <input type="number" id="tapY" placeholder="Y" value="400">
                        <input type="number" id="tapDelay" placeholder="延迟ms" value="50" style="width:80px;flex:none">
                        <button onclick="apiTap()">点击</button>
                    </div>
                    <div class="label" style="margin-top:8px">滑动</div>
                    <div class="coord-group">
                        <label>从</label><input type="number" id="swX1" value="100"><input type="number" id="swY1" value="500">
                        <label>到</label><input type="number" id="swX2" value="100"><input type="number" id="swY2" value="200">
                        <button onclick="apiSwipe()">滑动</button>
                    </div>
                    <div class="row" style="margin-top:8px">
                        <button class="secondary" onclick="apiLongPress()">长按</button>
                        <input type="number" id="lpDuration" placeholder="时长ms" value="800" style="width:100px;flex:none">
                    </div>
                </div>

                <div class="card">
                    <div class="card-title">🎨 找色</div>
                    <div class="row">
                        <input type="text" id="colorHex" placeholder="颜色十六进制，如 FF0000" value="FF0000">
                        <input type="number" id="colorTolerance" placeholder="容差" value="5" style="width:80px;flex:none">
                        <button onclick="apiFindColor()">查找</button>
                    </div>
                </div>

                <div class="card">
                    <div class="card-title">📱 应用信息</div>
                    <div class="flex-between">
                        <span id="foregroundApp">...</span>
                        <button class="secondary" onclick="apiForeground()">刷新</button>
                    </div>
                </div>

                <div class="card">
                    <div class="card-title">📷 截图</div>
                    <button onclick="apiScreenshot()">截图</button>
                    <img id="screenshot" style="max-width:100%;margin-top:8px;display:none;border-radius:4px">
                </div>

                <div class="card">
                    <div class="card-title">🔤 OCR 文字识别</div>
                    <button onclick="apiOCR()">识别屏幕文字</button>
                    <input type="text" id="ocrKeyword" placeholder="或搜索关键字..." style="margin-top:8px">
                    <button onclick="apiFindText()" class="secondary" style="margin-top:4px">搜索文字坐标</button>
                </div>

                <div class="card">
                    <div class="card-title">📋 输出</div>
                    <pre id="output">等待操作...</pre>
                </div>
            </div>

            <script>
                const BASE = '/';
                let foregroundTimer = null;

                async function api(path, params={}) {
                    try {
                        const qs = new URLSearchParams(params).toString();
                        const url = BASE + path + (qs ? '?' + qs : '');
                        const r = await fetch(url);
                        const data = await r.json();
                        return data;
                    } catch(e) {
                        return {success:false, error:e.message};
                    }
                }

                function show(data) {
                    document.getElementById('output').textContent = JSON.stringify(data, null, 2);
                }

                async function apiTap() {
                    const x = document.getElementById('tapX').value;
                    const y = document.getElementById('tapY').value;
                    const delay = document.getElementById('tapDelay').value;
                    show(await api('touch/tap', {x,y,delay}));
                }

                async function apiSwipe() {
                    show(await api('touch/swipe', {
                        x1: document.getElementById('swX1').value,
                        y1: document.getElementById('swY1').value,
                        x2: document.getElementById('swX2').value,
                        y2: document.getElementById('swY2').value
                    }));
                }

                async function apiLongPress() {
                    show(await api('touch/longpress', {
                        x: document.getElementById('tapX').value,
                        y: document.getElementById('tapY').value,
                        duration: document.getElementById('lpDuration').value
                    }));
                }

                async function apiFindColor() {
                    const hex = document.getElementById('colorHex').value.replace('#','');
                    const tol = document.getElementById('colorTolerance').value;
                    const r = await api('screen/findcolor', {color:hex, tolerance:tol});
                    show(r);
                    if (r.found && r.best) {
                        document.getElementById('tapX').value = Math.round(r.best.x);
                        document.getElementById('tapY').value = Math.round(r.best.y);
                    }
                }

                async function apiForeground() {
                    const r = await api('app/foreground');
                    document.getElementById('foregroundApp').textContent =
                        (r.name || r.bundleID || '未知') + ' (' + (r.bundleID || '') + ')';
                }

                async function apiScreenshot() {
                    const r = await api('screen/screenshot');
                    if (r.base64) {
                        const img = document.getElementById('screenshot');
                        img.src = 'data:image/png;base64,' + r.base64;
                        img.style.display = 'block';
                        r.base64 = r.base64.substring(0,40) + '...(已截断)';
                    }
                    show(r);
                }

                async function apiOCR() {
                    document.getElementById('output').textContent = '识别中...';
                    show(await api('ocr/recognize'));
                }

                async function apiFindText() {
                    const kw = document.getElementById('ocrKeyword').value;
                    if (!kw) return;
                    const r = await api('ocr/findtext', {keyword:kw});
                    show(r);
                    if (r.found) {
                        document.getElementById('tapX').value = Math.round(r.x);
                        document.getElementById('tapY').value = Math.round(r.y);
                    }
                }

                // 定期刷新前台应用
                apiForeground();
                foregroundTimer = setInterval(apiForeground, 3000);
                document.getElementById('status').textContent = '✅ 已连接';
                api('system/info').then(d => show(d));
            </script>
        </body>
        </html>
        """
    }
}
