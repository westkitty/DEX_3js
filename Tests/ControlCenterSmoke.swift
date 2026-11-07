import Foundation

final class MockHTTP: URLProtocol {
    static var code = 200
    static var payload = "{}"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: MockHTTP.code, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(MockHTTP.payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ControlCenterSmoke {
    static func main() async {
        let accepted = [
            "http://127.0.0.1:5173/",
            "http://localhost:4000/health",
            "http://127.0.0.1:9222/__devtools_status"
        ]
        let rejected = [
            "https://github.com/",
            "file:///etc/passwd",
            "http://127.0.0.1.evil.test:5173/",
            "http://127.0.0.1@evil.test:5173/",
            "http://user:pass@localhost:5173/",
            "javascript:alert(1)",
            "https://localhost:5173/"
        ]
        for value in accepted { precondition(LocalEndpoint.validated(value) != nil, "Expected allowed: \(value)") }
        for value in rejected { precondition(LocalEndpoint.validated(value) == nil, "Expected rejection: \(value)") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTTP.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        MockHTTP.payload = #"{"connected":true}"#
        let connected = await ToolProbe.check("http://127.0.0.1:9222/__devtools_status", bridge: true, session: session)
        precondition(connected.state == .ready, "Expected scene bridge connected")
        MockHTTP.payload = #"{"connected":false}"#
        let waiting = await ToolProbe.check("http://127.0.0.1:9222/__devtools_status", bridge: true, session: session)
        precondition(waiting.state == .disconnected, "Expected bridge awaiting scene")
        MockHTTP.payload = "invalid json"
        let invalid = await ToolProbe.check("http://127.0.0.1:9222/__devtools_status", bridge: true, session: session)
        precondition(invalid.state == .disconnected, "Expected unverified response")
        let prohibited = await ToolProbe.check("https://example.com/", session: session)
        precondition(prohibited.state == .blocked, "Remote endpoint must be blocked")
        MockHTTP.code = 404
        let unavailable = await ToolProbe.check("http://127.0.0.1:4000/health", session: session)
        precondition(unavailable.state == .stopped, "HTTP failure must not count as reachable")
        print("PASS: loopback allowlist, positive/negative bridge status, malformed status, blocked remote and HTTP error")
    }
}
