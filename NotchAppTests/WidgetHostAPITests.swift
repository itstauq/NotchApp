import Foundation
import XCTest

@MainActor
final class WidgetHostAPITests: XCTestCase {
    func testNetworkServiceRejectsFileURLs() async {
        let service = WidgetHostNetworkService(
            makeDataTask: { _, _ in
                XCTFail("Fetch factory should not be called for rejected schemes")
                return TestNetworkDataTask()
            }
        )

        do {
            _ = try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-1",
                    url: "file:///tmp/demo.txt",
                    method: "GET",
                    headers: nil,
                    body: nil,
                    bodyEncoding: nil
                ),
                context: networkContext(kind: .fetch)
            )
            XCTFail("Expected file:// fetch to be rejected")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32010)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkServiceRejectsHTTPFetchURLs() async {
        let service = WidgetHostNetworkService(
            makeDataTask: { _, _ in
                XCTFail("Fetch factory should not be called for rejected schemes")
                return TestNetworkDataTask()
            }
        )

        do {
            _ = try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-http",
                    url: "http://example.com/data",
                    method: "GET",
                    headers: nil,
                    body: nil,
                    bodyEncoding: nil
                ),
                context: networkContext(kind: .fetch)
            )
            XCTFail("Expected http fetch to be rejected")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32010)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkServiceReturnsJSONTextPayload() async throws {
        let task = TestNetworkDataTask()
        var capturedRequest: URLRequest?
        let service = WidgetHostNetworkService(
            makeDataTask: { request, completion in
                capturedRequest = request
                task.completion = completion
                return task
            }
        )

        let fetchTask = Task {
            try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-2",
                    url: "https://example.com/data",
                    method: "POST",
                    headers: ["content-type": "application/json"],
                    body: "{\"hello\":true}",
                    bodyEncoding: "text"
                ),
                context: networkContext(kind: .fetch)
            )
        }

        await Task.yield()
        XCTAssertTrue(task.didResume)
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(String(data: capturedRequest?.httpBody ?? Data(), encoding: .utf8), "{\"hello\":true}")

        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/data")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        task.complete(data: Data("{\"ok\":true}".utf8), response: response, error: nil)

        let payload = try await fetchTask.value
        XCTAssertEqual(payload.status, 200)
        XCTAssertEqual(payload.body, "{\"ok\":true}")
        XCTAssertEqual(payload.bodyEncoding, "text")
        XCTAssertEqual(payload.headers["Content-Type"], "application/json")
    }

    func testNetworkServiceRejectsRedirectedHTTPFinalURL() async {
        let task = TestNetworkDataTask()
        let service = WidgetHostNetworkService(
            makeDataTask: { _, completion in
                task.completion = completion
                return task
            }
        )

        let fetchTask = Task {
            try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-redirect-final-http",
                    url: "https://example.com/data",
                    method: "GET",
                    headers: nil,
                    body: nil,
                    bodyEncoding: nil
                ),
                context: networkContext(kind: .fetch)
            )
        }

        await Task.yield()

        let redirectedResponse = HTTPURLResponse(
            url: URL(string: "http://example.com/data")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        )!
        task.complete(data: Data("insecure".utf8), response: redirectedResponse, error: nil)

        do {
            _ = try await fetchTask.value
            XCTFail("Expected redirected insecure final URL to be rejected")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32010)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkServiceRejectsInsecureRedirectHop() async {
        WidgetHostFetchURLProtocol.reset()
        defer { WidgetHostFetchURLProtocol.reset() }

        WidgetHostFetchURLProtocol.handler = { request in
            switch request.url?.absoluteString {
            case "https://example.com/start":
                return .redirect(
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 302,
                        httpVersion: nil,
                        headerFields: ["Location": "http://example.com/middle"]
                    )!,
                    URLRequest(url: URL(string: "http://example.com/middle")!)
                )
            case "http://example.com/middle":
                return .redirect(
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 302,
                        httpVersion: nil,
                        headerFields: ["Location": "https://example.com/final"]
                    )!,
                    URLRequest(url: URL(string: "https://example.com/final")!)
                )
            case "https://example.com/final":
                return .response(
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "text/plain"]
                    )!,
                    Data("ok".utf8)
                )
            default:
                return .failure(URLError(.badURL))
            }
        }

        let service = WidgetHostNetworkService(protocolClasses: [WidgetHostFetchURLProtocol.self])

        do {
            _ = try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-redirect-hop-http",
                    url: "https://example.com/start",
                    method: "GET",
                    headers: nil,
                    body: nil,
                    bodyEncoding: nil
                ),
                context: networkContext(kind: .fetch)
            )
            XCTFail("Expected insecure redirect hop to be rejected")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32010)
            XCTAssertEqual(WidgetHostFetchURLProtocol.requestCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkServiceCancelCancelsPendingFetchTask() async {
        let task = TestNetworkDataTask()
        let service = WidgetHostNetworkService(
            makeDataTask: { _, completion in
                task.completion = completion
                return task
            }
        )

        let fetchTask = Task {
            try await service.fetch(
                RuntimeFetchRequestParams(
                    requestId: "req-3",
                    url: "https://example.com/slow",
                    method: "GET",
                    headers: nil,
                    body: nil,
                    bodyEncoding: nil
                ),
                context: networkContext(kind: .fetch)
            )
        }

        await Task.yield()
        service.cancel(RuntimeCancelRequestParams(requestId: "req-3"))
        XCTAssertTrue(task.didCancel)

        do {
            _ = try await fetchTask.value
            XCTFail("Expected cancelled fetch to fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
    }

    func testNetworkServiceOpenRejectsTelScheme() {
        let service = WidgetHostNetworkService(openURLAction: { _ in
            XCTFail("openURLAction should not be called for rejected schemes")
            return false
        })

        XCTAssertThrowsError(
            try service.open(
                RuntimeBrowserOpenParams(url: "tel:123"),
                context: networkContext(kind: .openURL)
            )
        ) { error in
            XCTAssertEqual((error as? RuntimeTransportRPCError)?.code, -32010)
        }
    }

    func testNetworkServiceOpenRejectsHTTPURLs() {
        let service = WidgetHostNetworkService(openURLAction: { _ in
            XCTFail("openURLAction should not be called for rejected schemes")
            return false
        })

        XCTAssertThrowsError(
            try service.open(
                RuntimeBrowserOpenParams(url: "http://example.com"),
                context: networkContext(kind: .openURL)
            )
        ) { error in
            XCTAssertEqual((error as? RuntimeTransportRPCError)?.code, -32010)
        }
    }

    func testNetworkServiceOpenAcceptsHTTPS() throws {
        var openedURL: URL?
        let service = WidgetHostNetworkService(openURLAction: { url in
            openedURL = url
            return true
        })

        try service.open(
            RuntimeBrowserOpenParams(url: "https://example.com"),
            context: networkContext(kind: .openURL)
        )
        XCTAssertEqual(openedURL?.absoluteString, "https://example.com")
    }

    func testHandleRoutesStorageRPCThroughWidgetHostAPI() async throws {
        let sessionManager = WidgetSessionManager()
        let storage = TestStorageHandler(result: .object(["count": .number(1)]))
        let network = TestNetworkHandler()
        let instanceID = UUID()
        sessionManager.beginMount(instanceID: instanceID)

        let api = WidgetHostAPI(
            sessionManager: sessionManager,
            storage: storage,
            network: network,
            resolveWidgetID: { id in
                id == instanceID ? "demo.widget" : nil
            }
        )

        let response = try await api.handle(
            RuntimeTransportRequest(
                id: "1",
                method: "rpc",
                params: .object([
                    "instanceId": .string(instanceID.uuidString),
                    "sessionId": .string("session-1"),
                    "method": .string("localStorage.allItems"),
                    "params": .object([:])
                ])
            )
        )

        XCTAssertEqual(storage.lastWidgetID, "demo.widget")
        XCTAssertEqual(storage.lastInstanceID, instanceID.uuidString)
        XCTAssertEqual(storage.lastMethod, "localStorage.allItems")
        XCTAssertEqual(
            response,
            .object([
                "sessionId": .string("session-1"),
                "value": .object(["count": .number(1)])
            ])
        )
    }

    func testHandleRejectsUnknownWidgetHostRPCMethod() async {
        let sessionManager = WidgetSessionManager()
        let storage = TestStorageHandler(result: .null)
        let network = TestNetworkHandler()
        let instanceID = UUID()
        sessionManager.beginMount(instanceID: instanceID)

        let api = WidgetHostAPI(
            sessionManager: sessionManager,
            storage: storage,
            network: network,
            resolveWidgetID: { id in
                id == instanceID ? "demo.widget" : nil
            }
        )

        do {
            _ = try await api.handle(
                RuntimeTransportRequest(
                    id: "1",
                    method: "rpc",
                    params: .object([
                        "instanceId": .string(instanceID.uuidString),
                        "sessionId": .string("session-1"),
                        "method": .string("unknown.method"),
                        "params": .object([:])
                    ])
                )
            )
            XCTFail("Expected unknown method to fail")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32601)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHandleRejectsSessionMismatchBeforeDispatch() async {
        let sessionManager = WidgetSessionManager()
        let storage = TestStorageHandler(result: .null)
        let network = TestNetworkHandler()
        let instanceID = UUID()
        sessionManager.beginMount(instanceID: instanceID)
        _ = sessionManager.acceptsWorkerSession(instanceID: instanceID, sessionId: "session-1")

        let api = WidgetHostAPI(
            sessionManager: sessionManager,
            storage: storage,
            network: network,
            resolveWidgetID: { id in
                id == instanceID ? "demo.widget" : nil
            }
        )

        do {
            _ = try await api.handle(
                RuntimeTransportRequest(
                    id: "1",
                    method: "rpc",
                    params: .object([
                        "instanceId": .string(instanceID.uuidString),
                        "sessionId": .string("session-2"),
                        "method": .string("localStorage.allItems"),
                        "params": .object([:])
                    ])
                )
            )
            XCTFail("Expected session mismatch to fail")
        } catch let error as RuntimeTransportRPCError {
            XCTAssertEqual(error.code, -32004)
            XCTAssertNil(storage.lastMethod)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private func networkContext(
    kind: WidgetHostNetworkRequestKind
) -> WidgetHostNetworkContext {
    WidgetHostNetworkContext(
        widgetID: "demo.widget",
        instanceID: UUID().uuidString,
        kind: kind
    )
}

private final class TestNetworkDataTask: WidgetHostNetworkDataTask {
    var didResume = false
    var didCancel = false
    var completion: ((Data?, URLResponse?, Error?) -> Void)?

    func resume() {
        didResume = true
    }

    func cancel() {
        didCancel = true
        completion?(nil, nil, URLError(.cancelled))
    }

    func complete(data: Data?, response: URLResponse?, error: Error?) {
        completion?(data, response, error)
    }
}

private final class WidgetHostFetchURLProtocol: URLProtocol {
    enum Event {
        case response(HTTPURLResponse, Data)
        case redirect(HTTPURLResponse, URLRequest)
        case failure(Error)
    }

    static var handler: ((URLRequest) -> Event)?
    static var requestCount = 0

    static func reset() {
        handler = nil
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch handler(request) {
        case .response(let response, let data):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let response, let redirectedRequest):
            client?.urlProtocol(self, wasRedirectedTo: redirectedRequest, redirectResponse: response)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class TestStorageHandler: WidgetHostLocalStorageHandling {
    var result: RuntimeJSONValue
    var lastWidgetID: String?
    var lastInstanceID: String?
    var lastMethod: String?

    init(result: RuntimeJSONValue) {
        self.result = result
    }

    func handleRPC(widgetID: String, instanceID: String, method: String, params: RuntimeJSONValue?) throws -> RuntimeJSONValue {
        lastWidgetID = widgetID
        lastInstanceID = instanceID
        lastMethod = method
        return result
    }
}

@MainActor
private final class TestNetworkHandler: WidgetHostNetworkHandling {
    func fetch(
        _ params: RuntimeFetchRequestParams,
        context: WidgetHostNetworkContext
    ) async throws -> RuntimeFetchResponsePayload {
        _ = context
        XCTFail("Network handler should not be called in this test")
        return RuntimeFetchResponsePayload(status: 200, statusText: "ok", headers: [:], body: nil, bodyEncoding: "text")
    }

    func cancel(_ params: RuntimeCancelRequestParams) {
        XCTFail("Network handler should not be called in this test")
    }

    func open(
        _ params: RuntimeBrowserOpenParams,
        context: WidgetHostNetworkContext
    ) throws {
        _ = context
        XCTFail("Network handler should not be called in this test")
    }
}
