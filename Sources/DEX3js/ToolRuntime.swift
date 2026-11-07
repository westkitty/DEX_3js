import Foundation

// Local-only probes: do not follow project-supplied URLs to arbitrary hosts.
enum LocalEndpoint {
    static func validated(_ raw: String) -> URL? {
        guard let parts = URLComponents(string: raw),
              parts.scheme?.lowercased() == "http",
              let host = parts.host?.lowercased(),
              host == "127.0.0.1" || host == "localhost",
              parts.user == nil, parts.password == nil,
              let url = parts.url else { return nil }
        return url
    }
}

enum ProbeState: String {
    case unknown = "Not checked"
    case checking = "Checking"
    case ready = "Reachable"
    case disconnected = "Awaiting scene"
    case stopped = "Unavailable"
    case blocked = "Invalid endpoint"
}

struct ProbeObservation {
    var state: ProbeState
    var detail: String

    static let unknown = ProbeObservation(state: .unknown, detail: "Not checked in this session")
    static let checking = ProbeObservation(state: .checking, detail: "Testing local connection")
}

private final class LocalOnlyRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum ToolProbe {
    static func check(_ raw: String?, bridge: Bool = false, session: URLSession = .shared) async -> ProbeObservation {
        guard let raw, let url = LocalEndpoint.validated(raw) else {
            return ProbeObservation(state: .blocked, detail: "Local HTTP endpoint not configured or rejected")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request, delegate: LocalOnlyRedirectGuard())
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return ProbeObservation(state: .stopped, detail: "Local service did not return HTTP success")
            }
            guard bridge else {
                return ProbeObservation(state: .ready, detail: "Local URL responding; project identity not independently verified")
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let connected = object["connected"] as? Bool else {
                return ProbeObservation(state: .disconnected, detail: "Bridge replied, scene status unverified")
            }
            return connected
                ? ProbeObservation(state: .ready, detail: "Live Three.js browser scene connected")
                : ProbeObservation(state: .disconnected, detail: "MCP bridge running; browser scene not connected")
        } catch {
            return ProbeObservation(state: .stopped, detail: "Local service is not responding")
        }
    }
}
