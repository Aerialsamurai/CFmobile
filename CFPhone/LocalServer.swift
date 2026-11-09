import Foundation
import Network

/// Tiny loopback-only static file server. The editor and compiler pages are served from here
/// (http://127.0.0.1:<port>/) because workers + WebAssembly streaming behave best over http.
final class LocalServer {
    private var listener: NWListener?
    private let root: URL
    private let queue = DispatchQueue(label: "cfphone.localserver")

    init(root: URL) { self.root = root }

    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let l = try NWListener(using: params, on: .any)
        listener = l
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            var resumed = false
            l.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; cont.resume(returning: l.port?.rawValue ?? 0) }
                case .failed(let err):
                    if !resumed { resumed = true; cont.resume(throwing: err) }
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            l.start(queue: queue)
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil,
                  let text = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            let firstLine = text.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
                self.respond(conn, status: "405 Method Not Allowed", body: Data()); return
            }
            var path = String(parts[1])
            if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
            path = path.removingPercentEncoding ?? path
            if path.contains("..") { self.respond(conn, status: "403 Forbidden", body: Data()); return }
            if path.hasSuffix("/") { path += "index.html" }
            let file = self.root.appendingPathComponent(String(path.dropFirst()))
            self.serve(conn, file: file, headOnly: parts[0] == "HEAD")
        }
    }

    private func serve(_ conn: NWConnection, file: URL, headOnly: Bool) {
        guard let fh = try? FileHandle(forReadingFrom: file),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attrs[.size] as? UInt64 else {
            respond(conn, status: "404 Not Found", body: Data("not found".utf8)); return
        }
        let head = "HTTP/1.1 200 OK\r\nContent-Type: \(mime(file.pathExtension))\r\nContent-Length: \(size)\r\n" +
            "Cache-Control: no-cache\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] err in
            if err != nil || headOnly { try? fh.close(); conn.cancel(); return }
            self?.pump(conn, fh)
        })
    }

    private func pump(_ conn: NWConnection, _ fh: FileHandle) {
        let chunk = (try? fh.read(upToCount: 512 * 1024)) ?? Data()
        if chunk.isEmpty {
            try? fh.close()
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
            return
        }
        conn.send(content: chunk, completion: .contentProcessed { [weak self] err in
            if err != nil { try? fh.close(); conn.cancel(); return }
            self?.pump(conn, fh)
        })
    }

    private func respond(_ conn: NWConnection, status: String, body: Data) {
        let head = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, contentContext: .finalMessage, isComplete: true,
                  completion: .contentProcessed { _ in conn.cancel() })
    }

    private func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css"
        case "json": return "application/json"
        case "wasm": return "application/wasm"
        case "tar": return "application/x-tar"
        default: return "application/octet-stream"
        }
    }
}
