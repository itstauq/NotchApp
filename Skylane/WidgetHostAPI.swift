import AVFoundation
import AppKit
import Combine
import Foundation
import UserNotifications

private let cameraDevicePreferenceName = "cameraDeviceId"

struct RuntimeFetchRequestParams: Decodable {
    var requestId: String
    var url: String
    var method: String?
    var headers: [String: String]?
    var body: String?
    var bodyEncoding: String?
}

struct RuntimeFetchResponsePayload: Encodable, Equatable {
    var status: Int
    var statusText: String
    var headers: [String: String]
    var body: String?
    var bodyEncoding: String
}

struct RuntimeCancelRequestParams: Decodable {
    var requestId: String
}

struct RuntimeScheduleNotificationParams: Decodable {
    var id: String
    var title: String
    var body: String?
    var deliverAtMs: Double
}

struct RuntimeCancelNotificationParams: Decodable {
    var id: String
}

struct RuntimeBrowserOpenParams: Decodable {
    var url: String
}

struct RuntimeAudioPlayParams: Decodable {
    var playerId: String
    var src: String
    var loop: Bool?
    var volume: Double?
}

struct RuntimeAudioPlayerIDParams: Decodable {
    var playerId: String
}

struct RuntimeAudioSetVolumeParams: Decodable {
    var playerId: String
    var value: Double
}

struct RuntimeCameraSelectDeviceParams: Decodable {
    var id: String
}

struct RuntimeSetPreferenceValueParams: Decodable {
    var name: String
    var value: RuntimeJSONValue?
}

struct RuntimeRPCRequestParams: Decodable {
    var instanceId: String
    var sessionId: String
    var method: String
    var params: RuntimeJSONValue?
}

struct RuntimeRPCResponsePayload: Encodable {
    var sessionId: String
    var value: RuntimeJSONValue
}

protocol WidgetHostLocalStorageHandling {
    func handleRPC(
        widgetID: String,
        instanceID: String,
        method: String,
        params: RuntimeJSONValue?
    ) throws -> RuntimeJSONValue

    func setPreferenceValue(
        widgetID: String,
        instanceID: String,
        name: String,
        value: RuntimeJSONValue?
    ) throws

    func preferenceValues(
        widgetID: String,
        instanceID: String
    ) -> [String: RuntimeJSONValue]
}

extension WidgetStorageManager: WidgetHostLocalStorageHandling {}

protocol WidgetHostNetworkDataTask: AnyObject {
    func resume()
    func cancel()
}

extension URLSessionDataTask: WidgetHostNetworkDataTask {}

enum WidgetHostNetworkRequestKind {
    case fetch
    case openURL
    case image
}

struct WidgetHostNetworkContext {
    var widgetID: String
    var instanceID: String
    var kind: WidgetHostNetworkRequestKind
}

private enum WidgetHostNetworkPolicyError: Error {
    case invalidURL
    case disallowedScheme
}

enum WidgetHostNetworkPolicy {
    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        return scheme == "https"
    }

    static func validate(_ url: URL, context: WidgetHostNetworkContext) throws {
        guard allows(url) else {
            throw WidgetHostNetworkPolicyError.disallowedScheme
        }
    }

    static func validatedURL(from rawValue: String, context: WidgetHostNetworkContext) throws -> URL {
        guard let url = URL(string: rawValue) else {
            throw rpcError(for: .invalidURL, context: context)
        }

        do {
            try validate(url, context: context)
        } catch let error as WidgetHostNetworkPolicyError {
            throw rpcError(for: error, context: context)
        } catch {
            throw error
        }

        return url
    }

    static func validateResolvedURL(_ url: URL, context: WidgetHostNetworkContext) throws {
        do {
            try validate(url, context: context)
        } catch let error as WidgetHostNetworkPolicyError {
            throw rpcError(for: error, context: context)
        } catch {
            throw error
        }
    }

    private static func rpcError(
        for error: WidgetHostNetworkPolicyError,
        context: WidgetHostNetworkContext
    ) -> RuntimeTransportRPCError {
        switch error {
        case .invalidURL, .disallowedScheme:
            return RuntimeTransportRPCError(
                code: -32010,
                message: validationMessage(for: context.kind),
                data: nil
            )
        }
    }

    private static func validationMessage(for kind: WidgetHostNetworkRequestKind) -> String {
        let scope: String
        switch kind {
        case .fetch:
            scope = "fetch URLs"
        case .openURL:
            scope = "URLs can be opened"
        case .image:
            scope = "image URLs are allowed"
        }

        return "Only https \(scope)."
    }
}

@MainActor
protocol WidgetHostNetworkHandling {
    func fetch(
        _ params: RuntimeFetchRequestParams,
        context: WidgetHostNetworkContext
    ) async throws -> RuntimeFetchResponsePayload
    func cancel(_ params: RuntimeCancelRequestParams)
    func open(
        _ params: RuntimeBrowserOpenParams,
        context: WidgetHostNetworkContext
    ) throws
}

@MainActor
final class WidgetHostNetworkService: WidgetHostNetworkHandling {
    typealias DataTaskFactory = (URLRequest, @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> WidgetHostNetworkDataTask

    private let makeDataTask: DataTaskFactory?
    private let fetchLoader: WidgetHostFetchDataLoader?
    private let openURLAction: (URL) -> Bool
    private var pendingFetchTasks: [String: WidgetHostNetworkDataTask] = [:]

    init(
        makeDataTask: @escaping DataTaskFactory,
        openURLAction: @escaping (URL) -> Bool = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        self.makeDataTask = makeDataTask
        self.fetchLoader = nil
        self.openURLAction = openURLAction
    }

    init(
        protocolClasses: [AnyClass]? = nil,
        openURLAction: @escaping (URL) -> Bool = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        self.makeDataTask = nil
        self.fetchLoader = WidgetHostFetchDataLoader(protocolClasses: protocolClasses)
        self.openURLAction = openURLAction
    }

    func fetch(
        _ params: RuntimeFetchRequestParams,
        context: WidgetHostNetworkContext
    ) async throws -> RuntimeFetchResponsePayload {
        let url = try WidgetHostNetworkPolicy.validatedURL(from: params.url, context: context)

        var request = URLRequest(url: url)
        request.httpMethod = params.method?.isEmpty == false ? params.method : "GET"
        for (header, value) in params.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: header)
        }

        if let body = params.body {
            if params.bodyEncoding == "base64" {
                guard let decoded = Data(base64Encoded: body) else {
                    throw RuntimeTransportRPCError(
                        code: -32602,
                        message: "Invalid base64 fetch body.",
                        data: nil
                    )
                }
                request.httpBody = decoded
            } else {
                request.httpBody = Data(body.utf8)
            }
        }

        return try await performFetch(requestId: params.requestId, request: request, context: context)
    }

    func cancel(_ params: RuntimeCancelRequestParams) {
        pendingFetchTasks.removeValue(forKey: params.requestId)?.cancel()
    }

    func open(
        _ params: RuntimeBrowserOpenParams,
        context: WidgetHostNetworkContext
    ) throws {
        let url = try WidgetHostNetworkPolicy.validatedURL(from: params.url, context: context)

        guard openURLAction(url) else {
            throw RuntimeTransportRPCError(
                code: -32011,
                message: "Failed to open URL.",
                data: nil
            )
        }
    }

    private func performFetch(
        requestId: String,
        request: URLRequest,
        context: WidgetHostNetworkContext
    ) async throws -> RuntimeFetchResponsePayload {
        try await withCheckedThrowingContinuation { continuation in
            let completion: @Sendable (Data?, URLResponse?, Error?) -> Void = { [weak self] data, response, error in
                Task { @MainActor [weak self] in
                    self?.pendingFetchTasks.removeValue(forKey: requestId)

                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.resume(
                            throwing: RuntimeTransportRPCError(
                                code: -32012,
                                message: "Invalid fetch response.",
                                data: nil
                            )
                        )
                        return
                    }

                    do {
                        let resolvedURL = httpResponse.url ?? request.url
                        if let resolvedURL {
                            try WidgetHostNetworkPolicy.validateResolvedURL(resolvedURL, context: context)
                        }

                        let payload = try self?.makeFetchResponsePayload(
                            statusCode: httpResponse.statusCode,
                            headers: httpResponse.allHeaderFields,
                            data: data ?? Data(),
                            mimeType: httpResponse.mimeType
                        ) ?? RuntimeFetchResponsePayload(
                            status: httpResponse.statusCode,
                            statusText: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                            headers: [:],
                            body: nil,
                            bodyEncoding: "text"
                        )
                        continuation.resume(returning: payload)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            let task: WidgetHostNetworkDataTask
            if let fetchLoader {
                task = fetchLoader.dataTask(with: request, context: context, completion: completion)
            } else if let makeDataTask {
                task = makeDataTask(request, completion)
            } else {
                continuation.resume(
                    throwing: RuntimeTransportRPCError(
                        code: -32012,
                        message: "Unable to start fetch request.",
                        data: nil
                    )
                )
                return
            }

            pendingFetchTasks[requestId] = task
            task.resume()
        }
    }

    private func makeFetchResponsePayload(
        statusCode: Int,
        headers: [AnyHashable: Any],
        data: Data,
        mimeType: String?
    ) throws -> RuntimeFetchResponsePayload {
        let normalizedHeaders = headers.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String else { return }
            result[key] = String(describing: entry.value)
        }

        let isTextResponse = mimeType?.hasPrefix("text/") == true || mimeType == "application/json"
        if isTextResponse, let text = String(data: data, encoding: .utf8) {
            return RuntimeFetchResponsePayload(
                status: statusCode,
                statusText: HTTPURLResponse.localizedString(forStatusCode: statusCode),
                headers: normalizedHeaders,
                body: text,
                bodyEncoding: "text"
            )
        }

        return RuntimeFetchResponsePayload(
            status: statusCode,
            statusText: HTTPURLResponse.localizedString(forStatusCode: statusCode),
            headers: normalizedHeaders,
            body: data.isEmpty ? nil : data.base64EncodedString(),
            bodyEncoding: "base64"
        )
    }
}

private final class WidgetHostFetchDataLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Handler: @unchecked Sendable {
        let context: WidgetHostNetworkContext
        let completion: @Sendable (Data?, URLResponse?, Error?) -> Void
        var terminalError: Error?
        var data = Data()
        var response: URLResponse?

        init(
            context: WidgetHostNetworkContext,
            completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
        ) {
            self.context = context
            self.completion = completion
        }
    }

    private let stateLock = NSLock()
    private var handlers: [Int: Handler] = [:]
    private var session: URLSession!

    init(protocolClasses: [AnyClass]? = nil) {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = protocolClasses

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        super.init()
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session.sessionDescription = "Widget Host Fetch URLSession"
    }

    deinit {
        session.invalidateAndCancel()
    }

    func dataTask(
        with request: URLRequest,
        context: WidgetHostNetworkContext,
        completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> WidgetHostNetworkDataTask {
        let task = session.dataTask(with: request)

        withHandlerLock {
            handlers[task.taskIdentifier] = Handler(context: context, completion: completion)
        }

        return task
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let handler = handler(for: dataTask.taskIdentifier) else {
            completionHandler(.cancel)
            return
        }

        handler.response = response
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let handler = handler(for: dataTask.taskIdentifier) else {
            return
        }

        handler.data.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let handler = handler(for: task.taskIdentifier),
              let url = request.url else {
            completionHandler(nil)
            return
        }

        do {
            try WidgetHostNetworkPolicy.validateResolvedURL(url, context: handler.context)
            completionHandler(request)
        } catch {
            handler.terminalError = error
            task.cancel()
            completionHandler(nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let handler = removeHandler(for: task.taskIdentifier) else {
            return
        }

        handler.completion(handler.data, handler.response, handler.terminalError ?? error)
    }

    private func handler(for taskIdentifier: Int) -> Handler? {
        withHandlerLock {
            handlers[taskIdentifier]
        }
    }

    private func removeHandler(for taskIdentifier: Int) -> Handler? {
        withHandlerLock {
            handlers.removeValue(forKey: taskIdentifier)
        }
    }

    private func withHandlerLock<T>(_ work: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return work()
    }
}

enum WidgetHostMediaPlaybackState: String, Codable, Equatable {
    case playing
    case paused
    case stopped
    case unknown
}

enum WidgetHostMediaAction: String, Codable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    case openSourceApp
}

enum WidgetHostMediaSourceKind: String, Codable {
    case application
    case unknown
}

struct WidgetHostMediaSource: Codable, Equatable {
    var id: String
    var name: String?
    var bundleIdentifier: String?
    var kind: WidgetHostMediaSourceKind
}

struct WidgetHostMediaItem: Codable, Equatable {
    var id: String?
    var title: String?
    var artist: String?
    var album: String?
}

struct WidgetHostMediaTimeline: Codable, Equatable {
    var positionSeconds: Double?
    var durationSeconds: Double?
}

struct WidgetHostMediaArtwork: Codable, Equatable {
    var src: String?
    var width: Double?
    var height: Double?
}

struct WidgetHostMediaState: Codable, Equatable {
    var source: WidgetHostMediaSource?
    var playbackState: WidgetHostMediaPlaybackState
    var item: WidgetHostMediaItem?
    var timeline: WidgetHostMediaTimeline?
    var artwork: WidgetHostMediaArtwork?
    var availableActions: [WidgetHostMediaAction]

    static let empty = WidgetHostMediaState(
        source: nil,
        playbackState: .stopped,
        item: nil,
        timeline: nil,
        artwork: nil,
        availableActions: []
    )
}

struct WidgetHostMediaAdapterResources {
    var scriptURL: URL
    var frameworkURL: URL
    var testClientURL: URL?
}

struct WidgetHostMediaAdapterSnapshot: Codable {
    var processIdentifier: Int?
    var bundleIdentifier: String?
    var parentApplicationBundleIdentifier: String?
    var playing: Bool?
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsedTime: Double?
    var elapsedTimeNow: Double?
    var timestamp: String?
    var playbackRate: Double?
    var prohibitsSkip: Bool?
    var uniqueIdentifier: String?
    var contentItemIdentifier: String?
    var artworkMimeType: String?
    var artworkData: Data?

    var hasKnownSession: Bool {
        if processIdentifier != nil || effectiveBundleIdentifier != nil {
            return true
        }

        if let uniqueIdentifier,
           !uniqueIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let contentItemIdentifier,
           !contentItemIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let artist,
           !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let album,
           !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        return playing != nil
    }

    var effectiveBundleIdentifier: String? {
        let candidate = parentApplicationBundleIdentifier ?? bundleIdentifier
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum WidgetHostMediaAdapterPatchField<Value> {
    case missing
    case null
    case value(Value)
}

private struct WidgetHostMediaAdapterSnapshotPatch: Decodable {
    var processIdentifier: WidgetHostMediaAdapterPatchField<Int>
    var bundleIdentifier: WidgetHostMediaAdapterPatchField<String>
    var parentApplicationBundleIdentifier: WidgetHostMediaAdapterPatchField<String>
    var playing: WidgetHostMediaAdapterPatchField<Bool>
    var title: WidgetHostMediaAdapterPatchField<String>
    var artist: WidgetHostMediaAdapterPatchField<String>
    var album: WidgetHostMediaAdapterPatchField<String>
    var duration: WidgetHostMediaAdapterPatchField<Double>
    var elapsedTime: WidgetHostMediaAdapterPatchField<Double>
    var elapsedTimeNow: WidgetHostMediaAdapterPatchField<Double>
    var timestamp: WidgetHostMediaAdapterPatchField<String>
    var playbackRate: WidgetHostMediaAdapterPatchField<Double>
    var prohibitsSkip: WidgetHostMediaAdapterPatchField<Bool>
    var uniqueIdentifier: WidgetHostMediaAdapterPatchField<String>
    var contentItemIdentifier: WidgetHostMediaAdapterPatchField<String>
    var artworkMimeType: WidgetHostMediaAdapterPatchField<String>
    var artworkData: WidgetHostMediaAdapterPatchField<Data>

    private enum CodingKeys: String, CodingKey {
        case processIdentifier
        case bundleIdentifier
        case parentApplicationBundleIdentifier
        case playing
        case title
        case artist
        case album
        case duration
        case elapsedTime
        case elapsedTimeNow
        case timestamp
        case playbackRate
        case prohibitsSkip
        case uniqueIdentifier
        case contentItemIdentifier
        case artworkMimeType
        case artworkData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        processIdentifier = try Self.decodeField(Int.self, forKey: .processIdentifier, in: container)
        bundleIdentifier = try Self.decodeField(String.self, forKey: .bundleIdentifier, in: container)
        parentApplicationBundleIdentifier = try Self.decodeField(String.self, forKey: .parentApplicationBundleIdentifier, in: container)
        playing = try Self.decodeField(Bool.self, forKey: .playing, in: container)
        title = try Self.decodeField(String.self, forKey: .title, in: container)
        artist = try Self.decodeField(String.self, forKey: .artist, in: container)
        album = try Self.decodeField(String.self, forKey: .album, in: container)
        duration = try Self.decodeField(Double.self, forKey: .duration, in: container)
        elapsedTime = try Self.decodeField(Double.self, forKey: .elapsedTime, in: container)
        elapsedTimeNow = try Self.decodeField(Double.self, forKey: .elapsedTimeNow, in: container)
        timestamp = try Self.decodeField(String.self, forKey: .timestamp, in: container)
        playbackRate = try Self.decodeField(Double.self, forKey: .playbackRate, in: container)
        prohibitsSkip = try Self.decodeField(Bool.self, forKey: .prohibitsSkip, in: container)
        uniqueIdentifier = try Self.decodeField(String.self, forKey: .uniqueIdentifier, in: container)
        contentItemIdentifier = try Self.decodeField(String.self, forKey: .contentItemIdentifier, in: container)
        artworkMimeType = try Self.decodeField(String.self, forKey: .artworkMimeType, in: container)
        artworkData = try Self.decodeField(Data.self, forKey: .artworkData, in: container)
    }

    init(snapshot: WidgetHostMediaAdapterSnapshot) {
        processIdentifier = Self.field(from: snapshot.processIdentifier)
        bundleIdentifier = Self.field(from: snapshot.bundleIdentifier)
        parentApplicationBundleIdentifier = Self.field(from: snapshot.parentApplicationBundleIdentifier)
        playing = Self.field(from: snapshot.playing)
        title = Self.field(from: snapshot.title)
        artist = Self.field(from: snapshot.artist)
        album = Self.field(from: snapshot.album)
        duration = Self.field(from: snapshot.duration)
        elapsedTime = Self.field(from: snapshot.elapsedTime)
        elapsedTimeNow = Self.field(from: snapshot.elapsedTimeNow)
        timestamp = Self.field(from: snapshot.timestamp)
        playbackRate = Self.field(from: snapshot.playbackRate)
        prohibitsSkip = Self.field(from: snapshot.prohibitsSkip)
        uniqueIdentifier = Self.field(from: snapshot.uniqueIdentifier)
        contentItemIdentifier = Self.field(from: snapshot.contentItemIdentifier)
        artworkMimeType = Self.field(from: snapshot.artworkMimeType)
        artworkData = Self.field(from: snapshot.artworkData)
    }

    func merged(with baseline: WidgetHostMediaAdapterSnapshot?) -> WidgetHostMediaAdapterSnapshot {
        var merged = WidgetHostMediaAdapterSnapshot(
            processIdentifier: Self.resolve(processIdentifier, fallback: baseline?.processIdentifier),
            bundleIdentifier: Self.resolve(bundleIdentifier, fallback: baseline?.bundleIdentifier),
            parentApplicationBundleIdentifier: Self.resolve(parentApplicationBundleIdentifier, fallback: baseline?.parentApplicationBundleIdentifier),
            playing: Self.resolve(playing, fallback: baseline?.playing),
            title: Self.resolve(title, fallback: baseline?.title),
            artist: Self.resolve(artist, fallback: baseline?.artist),
            album: Self.resolve(album, fallback: baseline?.album),
            duration: Self.resolve(duration, fallback: baseline?.duration),
            elapsedTime: Self.resolve(elapsedTime, fallback: baseline?.elapsedTime),
            elapsedTimeNow: Self.resolve(elapsedTimeNow, fallback: baseline?.elapsedTimeNow),
            timestamp: Self.resolve(timestamp, fallback: baseline?.timestamp),
            playbackRate: Self.resolve(playbackRate, fallback: baseline?.playbackRate),
            prohibitsSkip: Self.resolve(prohibitsSkip, fallback: baseline?.prohibitsSkip),
            uniqueIdentifier: Self.resolve(uniqueIdentifier, fallback: baseline?.uniqueIdentifier),
            contentItemIdentifier: Self.resolve(contentItemIdentifier, fallback: baseline?.contentItemIdentifier),
            artworkMimeType: Self.resolve(artworkMimeType, fallback: baseline?.artworkMimeType),
            artworkData: Self.resolve(artworkData, fallback: baseline?.artworkData)
        )

        if hasExplicitElapsedTime,
           case .missing = elapsedTimeNow {
            merged.elapsedTimeNow = nil
        }

        if (hasExplicitElapsedTime || hasExplicitElapsedTimeNow),
           case .missing = timestamp {
            merged.timestamp = nil
        }

        if shouldClearInheritedArtwork(from: baseline, merged: merged) {
            if case .missing = artworkMimeType {
                merged.artworkMimeType = nil
            }

            if case .missing = artworkData {
                merged.artworkData = nil
            }
        }

        return merged
    }

    private static func decodeField<T: Decodable>(
        _ type: T.Type,
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> WidgetHostMediaAdapterPatchField<T> {
        guard container.contains(key) else {
            return .missing
        }

        if try container.decodeNil(forKey: key) {
            return .null
        }

        return .value(try container.decode(type, forKey: key))
    }

    private static func field<T>(from value: T?) -> WidgetHostMediaAdapterPatchField<T> {
        if let value {
            return .value(value)
        }

        return .missing
    }

    private static func resolve<T>(
        _ field: WidgetHostMediaAdapterPatchField<T>,
        fallback: T?
    ) -> T? {
        switch field {
        case .missing:
            return fallback
        case .null:
            return nil
        case .value(let value):
            return value
        }
    }

    private func shouldClearInheritedArtwork(
        from baseline: WidgetHostMediaAdapterSnapshot?,
        merged: WidgetHostMediaAdapterSnapshot
    ) -> Bool {
        guard let baseline, baseline.artworkData != nil else {
            return false
        }

        guard !hasExplicitArtworkUpdate else {
            return false
        }

        return Self.artworkIdentitiesConflict(baseline: baseline, merged: merged)
    }

    fileprivate var hasExplicitArtworkUpdate: Bool {
        if case .missing = artworkMimeType,
           case .missing = artworkData {
            return false
        }

        return true
    }

    private var hasExplicitElapsedTime: Bool {
        if case .missing = elapsedTime {
            return false
        }

        return true
    }

    private var hasExplicitElapsedTimeNow: Bool {
        if case .missing = elapsedTimeNow {
            return false
        }

        return true
    }

    /// Compares track identity across snapshots to decide whether inherited
    /// artwork should be cleared.
    ///
    /// `uniqueIdentifier` is authoritative — if both snapshots have one, its
    /// verdict is final. `contentItemIdentifier` can be unstable (e.g. Chrome
    /// generates a fresh value per state event), so a mismatch there falls
    /// through to title comparison rather than immediately declaring a conflict.
    fileprivate static func artworkIdentitiesConflict(
        baseline: WidgetHostMediaAdapterSnapshot,
        merged: WidgetHostMediaAdapterSnapshot
    ) -> Bool {
        if let baseUID = normalizedIdentityValue(baseline.uniqueIdentifier),
           let mergedUID = normalizedIdentityValue(merged.uniqueIdentifier) {
            return baseUID != mergedUID
        }

        if let baseCID = normalizedIdentityValue(baseline.contentItemIdentifier),
           let mergedCID = normalizedIdentityValue(merged.contentItemIdentifier),
           baseCID == mergedCID {
            return false
        }

        // contentItemIdentifier was missing or changed — fall through to title,
        // which is the most broadly stable identifier across sources.
        if let baseTitle = normalizedIdentityValue(baseline.title),
           let mergedTitle = normalizedIdentityValue(merged.title) {
            let baseSource = normalizedIdentityValue(baseline.effectiveBundleIdentifier) ?? "unknown"
            let mergedSource = normalizedIdentityValue(merged.effectiveBundleIdentifier) ?? "unknown"
            return baseTitle != mergedTitle || baseSource != mergedSource
        }

        return false
    }

    private static func normalizedIdentityValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct WidgetHostMediaAdapterStreamEnvelope: Decodable {
    var type: String?
    var diff: Bool?
    var payload: WidgetHostMediaAdapterSnapshotPatch
}

private enum WidgetHostMediaServiceError: Error {
    case missingResources
    case invalidOutput
    case commandFailed(String)
}

extension WidgetHostMediaServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingResources:
            return "Bundled media adapter resources are missing."
        case .invalidOutput:
            return "The media adapter returned malformed output."
        case .commandFailed(let message):
            return message
        }
    }
}

private enum WidgetHostMediaSystem {
    static func defaultResources() throws -> WidgetHostMediaAdapterResources {
        guard let runtimeRoot = Bundle.main.resourceURL?.appendingPathComponent("WidgetRuntime", isDirectory: true) else {
            throw WidgetHostMediaServiceError.missingResources
        }

        let adapterRoot = runtimeRoot.appendingPathComponent("mediaremote-adapter", isDirectory: true)
        let scriptURL = adapterRoot.appendingPathComponent("mediaremote-adapter.pl")
        let frameworkURL = adapterRoot.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        let testClientURL = adapterRoot.appendingPathComponent("MediaRemoteAdapterTestClient")

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: scriptURL.path),
              fileManager.fileExists(atPath: frameworkURL.path) else {
            throw WidgetHostMediaServiceError.missingResources
        }

        return WidgetHostMediaAdapterResources(
            scriptURL: scriptURL,
            frameworkURL: frameworkURL,
            testClientURL: fileManager.fileExists(atPath: testClientURL.path) ? testClientURL : nil
        )
    }

    static func defaultOpenApplication(bundleIdentifier: String) -> Bool {
        if let runningApplication = runningApplication(for: bundleIdentifier) {
            return runningApplication.activate()
        }

        return false
    }

    static func hasRunningApplication(bundleIdentifier: String) -> Bool {
        runningApplication(for: bundleIdentifier) != nil
    }

    static func runningApplication(for bundleIdentifier: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }
}

@MainActor
private final class WidgetHostMediaAdapterClient {
    typealias ResolveResources = @MainActor () throws -> WidgetHostMediaAdapterResources
    typealias RunAdapterCommand = @MainActor ([String]) async throws -> String

    private let resolveResources: ResolveResources
    private let runAdapterCommand: RunAdapterCommand?
    private let log: (String) -> Void
    private let jsonDecoder = JSONDecoder()

    private var streamProcess: Process?
    private var streamStdoutHandle: FileHandle?
    private var streamStderrHandle: FileHandle?
    private var streamStdoutBuffer = Data()
    private var streamStderrBuffer = Data()
    private var onStreamOutputLine: ((String) -> Void)?

    init(
        resolveResources: @escaping ResolveResources,
        runAdapterCommand: RunAdapterCommand?,
        log: @escaping (String) -> Void
    ) {
        self.resolveResources = resolveResources
        self.runAdapterCommand = runAdapterCommand
        self.log = log
    }

    deinit {
        if streamProcess?.isRunning == true {
            streamProcess?.terminate()
        }
    }

    func ensureStreamStarted(onOutputLine: @escaping (String) -> Void) throws {
        onStreamOutputLine = onOutputLine
        if streamProcess?.isRunning == true {
            return
        }

        cleanupStreamReaders()
        streamProcess = nil

        let resources = try resolveResources()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        var arguments = [
            resources.scriptURL.path,
            resources.frameworkURL.path,
            "stream",
        ]
        if let testClientURL = resources.testClientURL {
            arguments.insert(testClientURL.path, at: 2)
        }
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] terminatedProcess in
            let exitCode = terminatedProcess.terminationStatus
            Task { @MainActor [weak self] in
                self?.handleStreamTermination(exitCode: exitCode)
            }
        }

        do {
            try process.run()
        } catch {
            throw WidgetHostMediaServiceError.commandFailed("Failed to launch the bundled media adapter.")
        }

        streamProcess = process
        streamStdoutHandle = stdoutPipe.fileHandleForReading
        streamStderrHandle = stderrPipe.fileHandleForReading

        streamStdoutHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }

            Task { @MainActor [weak self] in
                self?.appendStreamStdout(data)
            }
        }
        streamStderrHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }

            Task { @MainActor [weak self] in
                self?.appendStreamStderr(data)
            }
        }
    }

    func fetchSnapshotUsingGet() async throws -> WidgetHostMediaAdapterSnapshot? {
        let output = try await runAdapter(arguments: ["get", "--now"])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WidgetHostMediaServiceError.invalidOutput
        }

        if trimmed == "null" {
            return nil
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw WidgetHostMediaServiceError.invalidOutput
        }

        do {
            let snapshot = try jsonDecoder.decode(WidgetHostMediaAdapterSnapshot.self, from: data)
            return snapshot.hasKnownSession ? snapshot : nil
        } catch {
            throw WidgetHostMediaServiceError.invalidOutput
        }
    }

    func sendCommand(id: Int) async throws {
        _ = try await runAdapter(arguments: ["send", String(id)])
    }

    private func cleanupStreamReaders() {
        streamStdoutHandle?.readabilityHandler = nil
        streamStderrHandle?.readabilityHandler = nil
        streamStdoutHandle = nil
        streamStderrHandle = nil
        streamStdoutBuffer.removeAll(keepingCapacity: false)
        streamStderrBuffer.removeAll(keepingCapacity: false)
    }

    private func appendStreamStdout(_ data: Data) {
        streamStdoutBuffer.append(data)
        drainStreamBuffer(&streamStdoutBuffer) { [weak self] line in
            self?.onStreamOutputLine?(line)
        }
    }

    private func appendStreamStderr(_ data: Data) {
        streamStderrBuffer.append(data)
        drainStreamBuffer(&streamStderrBuffer) { [weak self] line in
            self?.log("Widget media adapter stderr: \(line)")
        }
    }

    private func drainStreamBuffer(_ buffer: inout Data, consumeLine: (String) -> Void) {
        while let range = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0...range.lowerBound)
            guard !lineData.isEmpty else {
                continue
            }

            let line = String(decoding: lineData, as: UTF8.self)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            consumeLine(trimmed)
        }
    }

    private func handleStreamTermination(exitCode: Int32) {
        cleanupStreamReaders()
        if exitCode != 0 {
            log("Widget media stream exited with code \(exitCode).")
        }

        streamProcess = nil
    }

    private func runAdapter(arguments: [String]) async throws -> String {
        if let runAdapterCommand {
            return try await runAdapterCommand(arguments)
        }

        let resources = try resolveResources()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        var commandArguments = [resources.scriptURL.path, resources.frameworkURL.path]
        if let testClientURL = resources.testClientURL {
            commandArguments.append(testClientURL.path)
        }
        commandArguments.append(contentsOf: arguments)
        process.arguments = commandArguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw WidgetHostMediaServiceError.commandFailed("Failed to launch the bundled media adapter.")
        }

        async let stdoutData = Task.detached(priority: .utility) {
            try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
        }.value
        async let stderrData = Task.detached(priority: .utility) {
            try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
        }.value
        let exitCode = await Task.detached(priority: .utility) {
            process.waitUntilExit()
            return process.terminationStatus
        }.value

        let output = String(
            data: try await stdoutData,
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: try await stderrData,
            encoding: .utf8
        ) ?? ""

        if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for line in stderr.split(whereSeparator: \.isNewline) {
                log("Widget media adapter stderr: \(line)")
            }
        }

        guard exitCode == 0 else {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let failureMessage = message.isEmpty
                ? "The media adapter command failed."
                : message
            throw WidgetHostMediaServiceError.commandFailed(failureMessage)
        }

        return output
    }
}

@MainActor
private final class WidgetHostMediaSessionStore {
    private let timestampFormatter = ISO8601DateFormatter()

    private var latestSnapshot: WidgetHostMediaAdapterSnapshot?
    private var hasReceivedStreamUpdate = false
    private var lastPublishedState: WidgetHostMediaState?

    var hasStreamUpdate: Bool {
        hasReceivedStreamUpdate
    }

    func currentState() -> WidgetHostMediaState {
        makeMediaState(from: latestSnapshot)
    }

    func recordSnapshotFromGet(_ snapshot: WidgetHostMediaAdapterSnapshot?) -> WidgetHostMediaState? {
        latestSnapshot = normalizedSnapshot(snapshot)
        return takePublishedStateIfChanged()
    }

    func applyStreamUpdate(
        _ patch: WidgetHostMediaAdapterSnapshotPatch,
        diff: Bool
    ) -> WidgetHostMediaState? {
        latestSnapshot = normalizedSnapshot(mergeSnapshotPatch(patch, isDiff: diff))
        hasReceivedStreamUpdate = true
        return takePublishedStateIfChanged()
    }

    func ingestSnapshotForTesting(_ snapshot: WidgetHostMediaAdapterSnapshot?) {
        latestSnapshot = normalizedSnapshot(snapshot)
        hasReceivedStreamUpdate = true
        lastPublishedState = currentState()
    }

    func ingestStreamSnapshotForTesting(_ snapshot: WidgetHostMediaAdapterSnapshot, diff: Bool = false) {
        latestSnapshot = normalizedSnapshot(
            mergeSnapshotPatch(WidgetHostMediaAdapterSnapshotPatch(snapshot: snapshot), isDiff: diff)
        )
        hasReceivedStreamUpdate = true
        lastPublishedState = currentState()
    }

    private func takePublishedStateIfChanged() -> WidgetHostMediaState? {
        let state = currentState()
        guard state != lastPublishedState else {
            return nil
        }

        lastPublishedState = state
        return state
    }

    private func mergeSnapshotPatch(
        _ patch: WidgetHostMediaAdapterSnapshotPatch,
        isDiff: Bool
    ) -> WidgetHostMediaAdapterSnapshot? {
        if isDiff {
            return patch.merged(with: latestSnapshot)
        }

        var merged = patch.merged(with: nil)

        // Non-diff stream updates typically omit large binary artwork data even
        // when the track hasn't changed. Carry forward artwork from the previous
        // snapshot when the patch has no explicit artwork and the track identity
        // is unchanged.
        if let baseline = latestSnapshot,
           baseline.artworkData != nil,
           !patch.hasExplicitArtworkUpdate,
           !Self.artworkIdentityChanged(from: baseline, to: merged) {
            merged.artworkData = baseline.artworkData
            merged.artworkMimeType = baseline.artworkMimeType
        }

        return merged
    }

    private static func artworkIdentityChanged(
        from baseline: WidgetHostMediaAdapterSnapshot,
        to merged: WidgetHostMediaAdapterSnapshot
    ) -> Bool {
        WidgetHostMediaAdapterSnapshotPatch.artworkIdentitiesConflict(baseline: baseline, merged: merged)
    }

    private func normalizedSnapshot(_ snapshot: WidgetHostMediaAdapterSnapshot?) -> WidgetHostMediaAdapterSnapshot? {
        guard let snapshot, snapshot.hasKnownSession else {
            return nil
        }

        return snapshot
    }

    private func makeMediaState(from snapshot: WidgetHostMediaAdapterSnapshot?) -> WidgetHostMediaState {
        guard let snapshot, snapshot.hasKnownSession else {
            return .empty
        }

        let source = resolveSource(from: snapshot)
        let item = WidgetHostMediaItem(
            id: snapshot.uniqueIdentifier ?? snapshot.contentItemIdentifier,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album
        )
        let timeline = WidgetHostMediaTimeline(
            positionSeconds: estimatedPosition(for: snapshot),
            durationSeconds: snapshot.duration
        )

        var availableActions: [WidgetHostMediaAction] = [.togglePlayPause]
        switch snapshot.playing {
        case true:
            availableActions.append(.pause)
        case false:
            availableActions.append(.play)
        default:
            break
        }

        if snapshot.prohibitsSkip != true {
            availableActions.append(.nextTrack)
            availableActions.append(.previousTrack)
        }

        if let bundleIdentifier = source?.bundleIdentifier,
           WidgetHostMediaSystem.hasRunningApplication(bundleIdentifier: bundleIdentifier) {
            availableActions.append(.openSourceApp)
        }

        let playbackState: WidgetHostMediaPlaybackState
        switch snapshot.playing {
        case true:
            playbackState = .playing
        case false:
            playbackState = .paused
        default:
            playbackState = .unknown
        }

        return WidgetHostMediaState(
            source: source,
            playbackState: playbackState,
            item: item,
            timeline: timeline,
            artwork: resolveArtwork(from: snapshot),
            availableActions: availableActions
        )
    }

    private func resolveArtwork(from snapshot: WidgetHostMediaAdapterSnapshot) -> WidgetHostMediaArtwork? {
        guard let artworkData = snapshot.artworkData,
              !artworkData.isEmpty,
              let reference = WidgetImagePipeline.registerHostImage(
                data: artworkData,
                mimeType: snapshot.artworkMimeType
              ) else {
            return nil
        }

        return WidgetHostMediaArtwork(
            src: reference.src,
            width: reference.width,
            height: reference.height
        )
    }

    private func resolveSource(from snapshot: WidgetHostMediaAdapterSnapshot) -> WidgetHostMediaSource? {
        if let bundleIdentifier = snapshot.effectiveBundleIdentifier {
            let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            let applicationBundle = applicationURL.flatMap(Bundle.init(url:))
            let name = (applicationBundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (applicationBundle?.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
                ?? applicationURL?.deletingPathExtension().lastPathComponent

            return WidgetHostMediaSource(
                id: bundleIdentifier,
                name: name,
                bundleIdentifier: bundleIdentifier,
                kind: .application
            )
        }

        if let processIdentifier = snapshot.processIdentifier {
            return WidgetHostMediaSource(
                id: "process:\(processIdentifier)",
                name: nil,
                bundleIdentifier: nil,
                kind: .unknown
            )
        }

        return nil
    }

    private func estimatedPosition(for snapshot: WidgetHostMediaAdapterSnapshot) -> Double? {
        let basePosition = snapshot.elapsedTimeNow ?? snapshot.elapsedTime
        guard let basePosition else {
            return nil
        }

        guard snapshot.playing == true,
              snapshot.elapsedTimeNow == nil,
              let timestamp = snapshot.timestamp,
              let lastUpdate = timestampFormatter.date(from: timestamp) else {
            return clampPosition(basePosition, duration: snapshot.duration)
        }

        let playbackRate = max(snapshot.playbackRate ?? 1, 0)
        let advancedPosition = basePosition + max(Date().timeIntervalSince(lastUpdate), 0) * playbackRate
        return clampPosition(advancedPosition, duration: snapshot.duration)
    }

    private func clampPosition(_ position: Double, duration: Double?) -> Double {
        let lowerBound = max(position, 0)
        guard let duration else {
            return lowerBound
        }

        return min(lowerBound, duration)
    }
}

@MainActor
protocol WidgetHostMediaHandling {
    func getState() async throws -> WidgetHostMediaState
    func play() async throws
    func pause() async throws
    func togglePlayPause() async throws
    func nextTrack() async throws
    func previousTrack() async throws
    func openSourceApp() async throws
}

@MainActor
final class WidgetHostMediaService: WidgetHostMediaHandling {
    typealias ResolveResources = @MainActor () throws -> WidgetHostMediaAdapterResources
    typealias OpenApplicationAction = @MainActor (String) -> Bool
    typealias RunAdapterCommand = @MainActor ([String]) async throws -> String
    typealias StateChangeHandler = @MainActor (WidgetHostMediaState) -> Void

    private let adapterClient: WidgetHostMediaAdapterClient
    private let sessionStore = WidgetHostMediaSessionStore()
    private let openApplication: OpenApplicationAction
    private let onStateChange: StateChangeHandler?
    private let log: (String) -> Void
    private let jsonDecoder = JSONDecoder()

    init(
        resolveResources: @escaping ResolveResources = WidgetHostMediaSystem.defaultResources,
        openApplication: @escaping OpenApplicationAction = WidgetHostMediaSystem.defaultOpenApplication,
        runAdapterCommand: RunAdapterCommand? = nil,
        onStateChange: StateChangeHandler? = nil,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.adapterClient = WidgetHostMediaAdapterClient(
            resolveResources: resolveResources,
            runAdapterCommand: runAdapterCommand,
            log: log
        )
        self.openApplication = openApplication
        self.onStateChange = onStateChange
        self.log = log
    }

    func getState() async throws -> WidgetHostMediaState {
        do {
            try ensureStreamStarted()
        } catch {
            log("Widget media stream failed to start: \(error.localizedDescription)")
        }

        do {
            let snapshot = try await adapterClient.fetchSnapshotUsingGet()
            publishIfNeeded(sessionStore.recordSnapshotFromGet(snapshot))
            return sessionStore.currentState()
        } catch {
            if sessionStore.hasStreamUpdate {
                return sessionStore.currentState()
            }

            throw error
        }
    }

    func play() async throws {
        try await performCommand(id: 0)
    }

    func pause() async throws {
        try await performCommand(id: 1)
    }

    func togglePlayPause() async throws {
        try await performCommand(id: 2)
    }

    func nextTrack() async throws {
        try await performCommand(id: 4)
    }

    func previousTrack() async throws {
        try await performCommand(id: 5)
    }

    func openSourceApp() async throws {
        let state = try await getState()
        guard let bundleIdentifier = state.source?.bundleIdentifier else {
            return
        }

        _ = openApplication(bundleIdentifier)
    }

    func ingestSnapshotForTesting(_ snapshot: WidgetHostMediaAdapterSnapshot?) {
        sessionStore.ingestSnapshotForTesting(snapshot)
    }

    func ingestStreamSnapshotForTesting(_ snapshot: WidgetHostMediaAdapterSnapshot, diff: Bool = false) {
        sessionStore.ingestStreamSnapshotForTesting(snapshot, diff: diff)
    }

    func ingestStreamOutputLineForTesting(_ line: String) {
        consumeStreamOutputLine(line)
    }

    func currentMediaStateForTesting() -> WidgetHostMediaState {
        sessionStore.currentState()
    }

    private func performCommand(id: Int) async throws {
        try await adapterClient.sendCommand(id: id)
    }

    private func ensureStreamStarted() throws {
        try adapterClient.ensureStreamStarted(onOutputLine: { [weak self] line in
            self?.consumeStreamOutputLine(line)
        })
    }

    private func consumeStreamOutputLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            return
        }

        do {
            let envelope = try jsonDecoder.decode(WidgetHostMediaAdapterStreamEnvelope.self, from: data)
            guard envelope.type == nil || envelope.type == "data" else {
                return
            }
            publishIfNeeded(sessionStore.applyStreamUpdate(envelope.payload, diff: envelope.diff ?? false))
        } catch {
            log("Widget media stream decode failed: \(error.localizedDescription)")
        }
    }

    private func publishIfNeeded(_ state: WidgetHostMediaState?) {
        guard let state else {
            return
        }

        onStateChange?(state)
    }
}

enum WidgetHostAudioPlaybackState: String, Codable, Equatable {
    case playing
    case paused
    case stopped
}

struct WidgetHostAudioPlayerState: Codable, Equatable {
    var id: String
    var src: String
    var playbackState: WidgetHostAudioPlaybackState
    var volume: Double
    var loop: Bool
}

struct WidgetHostAudioState: Codable, Equatable {
    var playbackState: WidgetHostAudioPlaybackState
    var players: [WidgetHostAudioPlayerState]

    static let empty = WidgetHostAudioState(
        playbackState: .stopped,
        players: []
    )
}

protocol WidgetHostAudioPlayerType: AnyObject {
    var volume: Float { get set }
    var numberOfLoops: Int { get set }
    var isPlaying: Bool { get }
    var onPlaybackFinished: (() -> Void)? { get set }

    func prepareToPlay() -> Bool
    @discardableResult func play() -> Bool
    func pause()
    func stop()
}

private final class WidgetHostAudioPlayer: NSObject, WidgetHostAudioPlayerType, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer

    var onPlaybackFinished: (() -> Void)?

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    var numberOfLoops: Int {
        get { player.numberOfLoops }
        set { player.numberOfLoops = newValue }
    }

    var isPlaying: Bool {
        player.isPlaying
    }

    init(contentsOf url: URL) throws {
        self.player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
    }

    func prepareToPlay() -> Bool {
        player.prepareToPlay()
    }

    @discardableResult
    func play() -> Bool {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.stop()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onPlaybackFinished?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        onPlaybackFinished?()
    }
}

private final class WidgetHostAudioSessionPlayer {
    let player: WidgetHostAudioPlayerType
    var state: WidgetHostAudioPlayerState

    init(player: WidgetHostAudioPlayerType, state: WidgetHostAudioPlayerState) {
        self.player = player
        self.state = state
    }
}

private final class WidgetHostAudioSession {
    var players: [String: WidgetHostAudioSessionPlayer] = [:]
    var lastPublishedState: WidgetHostAudioState?
}

@MainActor
protocol WidgetHostAudioHandling {
    func getState(instanceID: UUID) -> WidgetHostAudioState
    func play(
        widgetID: String,
        instanceID: UUID,
        widgetDefinition: WidgetDefinition?,
        params: RuntimeAudioPlayParams
    ) throws
    func pause(instanceID: UUID, params: RuntimeAudioPlayerIDParams) throws
    func togglePlayPause(instanceID: UUID, params: RuntimeAudioPlayerIDParams) throws
    func stop(instanceID: UUID, params: RuntimeAudioPlayerIDParams) throws
    func setVolume(instanceID: UUID, params: RuntimeAudioSetVolumeParams) throws
    func pauseAll(instanceID: UUID) throws
    func resumeAll(instanceID: UUID) throws
    func stopAll(instanceID: UUID)
    func removeAllPlayers(instanceID: UUID)
}

@MainActor
final class WidgetHostAudioService: WidgetHostAudioHandling {
    typealias PlayerFactory = @MainActor (URL) throws -> WidgetHostAudioPlayerType
    typealias StateChangeHandler = @MainActor (UUID, WidgetHostAudioState) -> Void

    private let makePlayer: PlayerFactory
    private let fileManager: FileManager
    private let onStateChange: StateChangeHandler?
    private let log: (String) -> Void
    private var sessions: [UUID: WidgetHostAudioSession] = [:]

    init(
        makePlayer: @escaping PlayerFactory = { try WidgetHostAudioPlayer(contentsOf: $0) },
        fileManager: FileManager = .default,
        onStateChange: StateChangeHandler? = nil,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.makePlayer = makePlayer
        self.fileManager = fileManager
        self.onStateChange = onStateChange
        self.log = log
    }

    func getState(instanceID: UUID) -> WidgetHostAudioState {
        state(for: sessions[instanceID])
    }

    func play(
        widgetID: String,
        instanceID: UUID,
        widgetDefinition: WidgetDefinition?,
        params: RuntimeAudioPlayParams
    ) throws {
        let playerID = try normalizedPlayerID(params.playerId)
        let src = try normalizedSource(params.src)
        let volume = clampedVolume(params.volume)
        let loop = params.loop == true
        let assetURL = try resolvedAssetURL(
            widgetID: widgetID,
            widgetDefinition: widgetDefinition,
            source: src
        )

        let session = session(for: instanceID)
        if let existing = session.players[playerID],
           existing.state.src != src {
            existing.player.onPlaybackFinished = nil
            existing.player.stop()
            session.players.removeValue(forKey: playerID)
        }

        if let existing = session.players[playerID] {
            configure(existing, src: src, volume: volume, loop: loop)
            attachPlaybackFinishHandler(to: existing.player, instanceID: instanceID, playerID: playerID)
            guard existing.player.isPlaying || existing.player.play() else {
                throw playbackStartError(for: playerID)
            }
            existing.state.playbackState = .playing
            publishIfNeeded(instanceID)
            return
        }

        let player = try makePlayer(assetURL)
        _ = player.prepareToPlay()
        player.volume = Float(volume)
        player.numberOfLoops = loop ? -1 : 0
        attachPlaybackFinishHandler(to: player, instanceID: instanceID, playerID: playerID)
        guard player.play() else {
            throw playbackStartError(for: playerID)
        }

        session.players[playerID] = WidgetHostAudioSessionPlayer(
            player: player,
            state: WidgetHostAudioPlayerState(
                id: playerID,
                src: src,
                playbackState: .playing,
                volume: volume,
                loop: loop
            )
        )
        publishIfNeeded(instanceID)
    }

    func pause(instanceID: UUID, params: RuntimeAudioPlayerIDParams) throws {
        let playerID = try normalizedPlayerID(params.playerId)
        guard let sessionPlayer = sessions[instanceID]?.players[playerID] else {
            return
        }

        sessionPlayer.player.pause()
        sessionPlayer.state.playbackState = .paused
        publishIfNeeded(instanceID)
    }

    func togglePlayPause(instanceID: UUID, params: RuntimeAudioPlayerIDParams) throws {
        let playerID = try normalizedPlayerID(params.playerId)
        guard let sessionPlayer = sessions[instanceID]?.players[playerID] else {
            return
        }

        if sessionPlayer.state.playbackState == .playing {
            sessionPlayer.player.pause()
            sessionPlayer.state.playbackState = .paused
        } else {
            guard sessionPlayer.player.play() else {
                throw playbackStartError(for: playerID)
            }
            sessionPlayer.state.playbackState = .playing
        }

        publishIfNeeded(instanceID)
    }

    func stop(instanceID: UUID, params: RuntimeAudioPlayerIDParams) throws {
        let playerID = try normalizedPlayerID(params.playerId)
        guard let session = sessions[instanceID],
              let sessionPlayer = session.players.removeValue(forKey: playerID) else {
            return
        }

        sessionPlayer.player.onPlaybackFinished = nil
        sessionPlayer.player.stop()
        publishIfNeeded(instanceID)
        pruneSessionIfEmpty(instanceID)
    }

    func setVolume(instanceID: UUID, params: RuntimeAudioSetVolumeParams) throws {
        let playerID = try normalizedPlayerID(params.playerId)
        guard let sessionPlayer = sessions[instanceID]?.players[playerID] else {
            return
        }

        let volume = clampedVolume(params.value)
        sessionPlayer.player.volume = Float(volume)
        sessionPlayer.state.volume = volume
        publishIfNeeded(instanceID)
    }

    func pauseAll(instanceID: UUID) throws {
        guard let session = sessions[instanceID] else {
            return
        }

        for sessionPlayer in session.players.values {
            sessionPlayer.player.pause()
            sessionPlayer.state.playbackState = .paused
        }

        publishIfNeeded(instanceID)
    }

    func resumeAll(instanceID: UUID) throws {
        guard let session = sessions[instanceID] else {
            return
        }

        for (playerID, sessionPlayer) in session.players {
            if sessionPlayer.state.playbackState == .playing {
                continue
            }

            guard sessionPlayer.player.play() else {
                throw playbackStartError(for: playerID)
            }
            sessionPlayer.state.playbackState = .playing
        }

        publishIfNeeded(instanceID)
    }

    func stopAll(instanceID: UUID) {
        guard let session = sessions[instanceID] else {
            return
        }

        for sessionPlayer in session.players.values {
            sessionPlayer.player.onPlaybackFinished = nil
            sessionPlayer.player.stop()
        }
        session.players.removeAll()
        publishIfNeeded(instanceID)
        sessions.removeValue(forKey: instanceID)
    }

    func removeAllPlayers(instanceID: UUID) {
        guard let session = sessions.removeValue(forKey: instanceID) else {
            return
        }

        for sessionPlayer in session.players.values {
            sessionPlayer.player.onPlaybackFinished = nil
            sessionPlayer.player.stop()
        }
    }

    private func session(for instanceID: UUID) -> WidgetHostAudioSession {
        if let session = sessions[instanceID] {
            return session
        }

        let session = WidgetHostAudioSession()
        sessions[instanceID] = session
        return session
    }

    private func configure(
        _ sessionPlayer: WidgetHostAudioSessionPlayer,
        src: String,
        volume: Double,
        loop: Bool
    ) {
        sessionPlayer.player.volume = Float(volume)
        sessionPlayer.player.numberOfLoops = loop ? -1 : 0
        sessionPlayer.state.src = src
        sessionPlayer.state.volume = volume
        sessionPlayer.state.loop = loop
    }

    private func attachPlaybackFinishHandler(
        to player: WidgetHostAudioPlayerType,
        instanceID: UUID,
        playerID: String
    ) {
        player.onPlaybackFinished = { [weak self] in
            Task { @MainActor in
                self?.handlePlaybackFinished(instanceID: instanceID, playerID: playerID)
            }
        }
    }

    private func state(for session: WidgetHostAudioSession?) -> WidgetHostAudioState {
        guard let session, !session.players.isEmpty else {
            return .empty
        }

        let players = session.players.values
            .map(\.state)
            .sorted { $0.id < $1.id }
        let playbackState: WidgetHostAudioPlaybackState
        if players.contains(where: { $0.playbackState == .playing }) {
            playbackState = .playing
        } else {
            playbackState = .paused
        }

        return WidgetHostAudioState(
            playbackState: playbackState,
            players: players
        )
    }

    private func publishIfNeeded(_ instanceID: UUID) {
        let nextState = state(for: sessions[instanceID])
        if sessions[instanceID]?.lastPublishedState == nextState {
            return
        }

        sessions[instanceID]?.lastPublishedState = nextState
        onStateChange?(instanceID, nextState)
    }

    private func handlePlaybackFinished(instanceID: UUID, playerID: String) {
        guard let session = sessions[instanceID],
              let sessionPlayer = session.players.removeValue(forKey: playerID) else {
            return
        }

        sessionPlayer.player.onPlaybackFinished = nil
        publishIfNeeded(instanceID)
        pruneSessionIfEmpty(instanceID)
    }

    private func pruneSessionIfEmpty(_ instanceID: UUID) {
        if sessions[instanceID]?.players.isEmpty == true {
            sessions.removeValue(forKey: instanceID)
        }
    }

    private func normalizedPlayerID(_ rawValue: String) throws -> String {
        let playerID = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !playerID.isEmpty else {
            throw RuntimeTransportRPCError(
                code: -32602,
                message: "Audio playerId must be a non-empty string.",
                data: nil
            )
        }

        return playerID
    }

    private func normalizedSource(_ rawValue: String) throws -> String {
        let source = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            throw RuntimeTransportRPCError(
                code: -32602,
                message: "Audio src must be a non-empty string.",
                data: nil
            )
        }

        return source
    }

    private func resolvedAssetURL(
        widgetID: String,
        widgetDefinition: WidgetDefinition?,
        source: String
    ) throws -> URL {
        guard let widgetDefinition else {
            throw RuntimeTransportRPCError(
                code: -32000,
                message: "Widget definition for '\(widgetID)' is unavailable.",
                data: nil
            )
        }

        guard let assetURL = widgetDefinition.assetURL(for: source) else {
            throw RuntimeTransportRPCError(
                code: -32602,
                message: "Audio src must be a widget-relative asset path.",
                data: nil
            )
        }

        guard fileManager.fileExists(atPath: assetURL.path) else {
            throw RuntimeTransportRPCError(
                code: -32602,
                message: "Audio asset '\(source)' was not found in the widget build output.",
                data: nil
            )
        }

        return assetURL
    }

    private func clampedVolume(_ value: Double?) -> Double {
        clampedVolume(value ?? 1)
    }

    private func clampedVolume(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func playbackStartError(for playerID: String) -> RuntimeTransportRPCError {
        RuntimeTransportRPCError(
            code: -32031,
            message: "Failed to start audio playback for player '\(playerID)'.",
            data: nil
        )
    }
}

@MainActor
struct WidgetHostNotificationRequest: Equatable {
    var widgetID: String
    var instanceID: String
    var notificationID: String
    var title: String
    var body: String?
    var deliverAt: Date
}

enum WidgetNotificationAuthorizationStatus: String {
    case notDetermined
    case denied
    case authorized

    var description: String {
        switch self {
        case .notDetermined:
            return "Skylane will request notification permission the first time a widget tries to notify you."
        case .denied:
            return "Notifications are currently denied. Enable them for Skylane in System Settings > Notifications."
        case .authorized:
            return "Skylane can deliver widget notifications through macOS."
        }
    }

    var canDeliverNotifications: Bool {
        self == .authorized
    }
}

@MainActor
protocol WidgetHostNotificationHandling: AnyObject {
    var authorizationStatus: WidgetNotificationAuthorizationStatus { get }
    func refreshAuthorizationStatus() async
    func schedule(_ request: WidgetHostNotificationRequest) async throws
    func cancel(widgetID: String, instanceID: String, notificationID: String) async
    func cancelAllNotifications(widgetID: String, instanceID: String) async
    func cancelAllManagedNotifications() async
}

protocol WidgetUserNotificationCenterHandling: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }
    func notificationAuthorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func deliveredNotifications() async -> [UNNotification]
}

extension UNUserNotificationCenter: WidgetUserNotificationCenterHandling {
    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    func deliveredNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
    }
}

@MainActor
final class WidgetNotificationService: NSObject, ObservableObject, WidgetHostNotificationHandling, UNUserNotificationCenterDelegate {
    static let shared = WidgetNotificationService()

    @Published private(set) var authorizationStatus: WidgetNotificationAuthorizationStatus = .notDetermined

    private let center: WidgetUserNotificationCenterHandling
    private let log: (String) -> Void
    private var preferencesObserver: NSObjectProtocol?
    private var appDidBecomeActiveObserver: NSObjectProtocol?

    var openWidget: (UUID?) -> Void
    var isWidgetVisible: (UUID) -> Bool

    private static let identifierPrefix = "skylane.widget."
    private static let userInfoInstanceIDKey = "widgetInstanceId"
    private static let userInfoWidgetIDKey = "widgetId"
    private static let userInfoNotificationIDKey = "notificationId"

    init(
        center: WidgetUserNotificationCenterHandling = UNUserNotificationCenter.current(),
        log: @escaping (String) -> Void = { FileLog().write($0) },
        openWidget: @escaping (UUID?) -> Void = { _ in },
        isWidgetVisible: @escaping (UUID) -> Bool = { _ in false }
    ) {
        self.center = center
        self.log = log
        self.openWidget = openWidget
        self.isWidgetVisible = isWidgetVisible
        super.init()

        center.delegate = self
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: .widgetNotificationsPreferenceDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !Preferences.widgetNotificationsEnabled {
                    await self.cancelAllManagedNotifications()
                }
            }
        }

        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAuthorizationStatus()
            }
        }

        Task { @MainActor [weak self] in
            await self?.synchronizeWithSystemState()
        }
    }

    deinit {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
        if let appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = mappedAuthorizationStatus(from: await center.notificationAuthorizationStatus())
    }

    func schedule(_ request: WidgetHostNotificationRequest) async throws {
        let authorizationStatus = try await ensureAuthorizationForDelivery()
        guard authorizationStatus.canDeliverNotifications else {
            log("Widget notifications: skipped scheduling \(request.widgetID)/\(request.instanceID) because authorization is \(authorizationStatus.rawValue).")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = request.title
        if let body = request.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            content.body = body
        }
        content.userInfo = [
            Self.userInfoInstanceIDKey: request.instanceID,
            Self.userInfoWidgetIDKey: request.widgetID,
            Self.userInfoNotificationIDKey: request.notificationID
        ]

        let notificationRequest = UNNotificationRequest(
            identifier: notificationRequestIdentifier(
                instanceID: request.instanceID,
                notificationID: request.notificationID
            ),
            content: content,
            trigger: notificationTrigger(for: request.deliverAt)
        )
        try await center.add(notificationRequest)
    }

    func cancel(widgetID: String, instanceID: String, notificationID: String) async {
        let identifier = notificationRequestIdentifier(instanceID: instanceID, notificationID: notificationID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAllNotifications(widgetID: String, instanceID: String) async {
        let identifiers = await managedNotificationIdentifiers(instanceID: instanceID)
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func cancelAllManagedNotifications() async {
        let identifiers = await managedNotificationIdentifiers(instanceID: nil)
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func synchronizeWithSystemState() async {
        await refreshAuthorizationStatus()
        if !Preferences.widgetNotificationsEnabled {
            await cancelAllManagedNotifications()
        }
    }

    private func ensureAuthorizationForDelivery() async throws -> WidgetNotificationAuthorizationStatus {
        let currentStatus = mappedAuthorizationStatus(from: await center.notificationAuthorizationStatus())
        authorizationStatus = currentStatus

        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        do {
            _ = try await center.requestAuthorization(options: [.alert])
        } catch {
            log("Widget notifications: authorization request failed: \(error.localizedDescription)")
        }

        await refreshAuthorizationStatus()
        return authorizationStatus
    }

    private func notificationRequestIdentifier(instanceID: String, notificationID: String) -> String {
        "\(Self.identifierPrefix)\(instanceID)|\(notificationID)"
    }

    private func notificationTrigger(for deliverAt: Date) -> UNNotificationTrigger {
        let interval = deliverAt.timeIntervalSinceNow
        if interval <= 1 {
            return UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: deliverAt
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private func managedNotificationIdentifiers(instanceID: String?) async -> [String] {
        let pending = (await center.pendingNotificationRequests()).map(\.identifier)
        let delivered = (await center.deliveredNotifications()).map(\.request.identifier)
        let allIdentifiers = Set(pending + delivered)

        return Array(allIdentifiers.filter { identifier in
            guard identifier.hasPrefix(Self.identifierPrefix) else {
                return false
            }
            guard let instanceID else {
                return true
            }
            return identifier.hasPrefix("\(Self.identifierPrefix)\(instanceID)|")
        })
    }

    private func mappedAuthorizationStatus(from status: UNAuthorizationStatus) -> WidgetNotificationAuthorizationStatus {
        switch status {
        case .authorized, .ephemeral, .provisional:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    private func instanceID(from notification: UNNotification) -> UUID? {
        guard let instanceID = notification.request.content.userInfo[Self.userInfoInstanceIDKey] as? String else {
            return nil
        }
        return UUID(uuidString: instanceID)
    }

    func presentationOptions(
        for instanceID: UUID?,
        appIsActive: Bool? = nil
    ) -> UNNotificationPresentationOptions {
        let appIsCurrentlyActive = appIsActive ?? NSApp.isActive

        guard let instanceID else {
            return [.banner, .list]
        }

        guard !(appIsCurrentlyActive && isWidgetVisible(instanceID)) else {
            return []
        }

        return [.banner, .list]
    }

    func handleNotificationActivation(instanceID: UUID?) {
        openWidget(instanceID)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        presentationOptions(for: instanceID(from: notification))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        handleNotificationActivation(instanceID: instanceID(from: response.notification))
    }
}

@MainActor
final class WidgetHostAPI {
    private let sessionManager: WidgetSessionManager
    private let storage: WidgetHostLocalStorageHandling
    private let network: WidgetHostNetworkHandling
    private let media: WidgetHostMediaHandling
    private let audio: WidgetHostAudioHandling
    private let notifications: WidgetHostNotificationHandling?
    private let resolveWidgetID: (UUID) -> String?
    private let resolveWidgetDefinition: (UUID) -> WidgetDefinition?
    private let log: (String) -> Void
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    init(
        sessionManager: WidgetSessionManager,
        storage: WidgetHostLocalStorageHandling,
        network: WidgetHostNetworkHandling,
        media: WidgetHostMediaHandling? = nil,
        audio: WidgetHostAudioHandling? = nil,
        notifications: WidgetHostNotificationHandling? = nil,
        resolveWidgetID: @escaping (UUID) -> String?,
        resolveWidgetDefinition: @escaping (UUID) -> WidgetDefinition? = { _ in nil },
        log: @escaping (String) -> Void = { _ in }
    ) {
        let resolvedMedia = media ?? WidgetHostMediaService(log: log)
        let resolvedAudio = audio ?? WidgetHostAudioService(log: log)
        self.sessionManager = sessionManager
        self.storage = storage
        self.network = network
        self.media = resolvedMedia
        self.audio = resolvedAudio
        self.notifications = notifications
        self.resolveWidgetID = resolveWidgetID
        self.resolveWidgetDefinition = resolveWidgetDefinition
        self.log = log
    }

    func handle(_ request: RuntimeTransportRequest) async throws -> RuntimeJSONValue? {
        guard request.method == "rpc" else {
            throw RuntimeTransportRPCError(
                code: -32601,
                message: "Unsupported runtime request '\(request.method)'.",
                data: nil
            )
        }

        let rpcRequest: RuntimeRPCRequestParams
        do {
            rpcRequest = try decode(request.params, as: RuntimeRPCRequestParams.self)
        } catch {
            throw RuntimeTransportRPCError(
                code: -32602,
                message: "Invalid runtime RPC params: \(error.localizedDescription)",
                data: nil
            )
        }

        guard let instanceID = UUID(uuidString: rpcRequest.instanceId) else {
            throw RuntimeTransportRPCError(
                code: -32001,
                message: "Unknown widget instance '\(rpcRequest.instanceId)'.",
                data: nil
            )
        }

        guard let widgetID = resolveWidgetID(instanceID) else {
            throw RuntimeTransportRPCError(
                code: -32001,
                message: "Unknown widget instance '\(rpcRequest.instanceId)'.",
                data: nil
            )
        }

        guard sessionManager.acceptsWorkerSession(instanceID: instanceID, sessionId: rpcRequest.sessionId) else {
            throw RuntimeTransportRPCError(
                code: -32004,
                message: "Session mismatch for instance '\(rpcRequest.instanceId)'.",
                data: nil
            )
        }

        let value: RuntimeJSONValue
        do {
            let widgetDefinition = resolveWidgetDefinition(instanceID)
            value = try await route(
                widgetDefinition: widgetDefinition,
                widgetID: widgetID,
                instanceID: instanceID,
                method: rpcRequest.method,
                params: rpcRequest.params
            )
        } catch let rpcError as RuntimeTransportRPCError {
            throw rpcError
        } catch {
            log("Widget host API: \(rpcRequest.method) failed for \(rpcRequest.instanceId): \(error.localizedDescription)")
            throw RuntimeTransportRPCError(
                code: -32000,
                message: error.localizedDescription,
                data: nil
            )
        }

        return try encodeRuntimeJSONValue(
            RuntimeRPCResponsePayload(
                sessionId: rpcRequest.sessionId,
                value: value
            )
        )
    }

    private func route(
        widgetDefinition: WidgetDefinition?,
        widgetID: String,
        instanceID: UUID,
        method: String,
        params: RuntimeJSONValue?
    ) async throws -> RuntimeJSONValue {
        switch method {
        case "localStorage.allItems", "localStorage.setItem", "localStorage.removeItem":
            return try storage.handleRPC(
                widgetID: widgetID,
                instanceID: instanceID.uuidString,
                method: method,
                params: params
            )
        case "network.fetch":
            let fetchParams = try decode(params, as: RuntimeFetchRequestParams.self)
            let context = WidgetHostNetworkContext(
                widgetID: widgetID,
                instanceID: instanceID.uuidString,
                kind: .fetch
            )
            return try encodeRuntimeJSONValue(try await network.fetch(fetchParams, context: context))
        case "request.cancel":
            let cancelParams = try decode(params, as: RuntimeCancelRequestParams.self)
            network.cancel(cancelParams)
            return .null
        case "browser.open":
            let openParams = try decode(params, as: RuntimeBrowserOpenParams.self)
            let context = WidgetHostNetworkContext(
                widgetID: widgetID,
                instanceID: instanceID.uuidString,
                kind: .openURL
            )
            try network.open(openParams, context: context)
            return .null
        case "preferences.setValue":
            let preferenceParams = try decode(params, as: RuntimeSetPreferenceValueParams.self)
            try storage.setPreferenceValue(
                widgetID: widgetID,
                instanceID: instanceID.uuidString,
                name: preferenceParams.name,
                value: preferenceParams.value
            )
            NotificationCenter.default.post(
                name: .widgetPreferencesDidChange,
                object: WidgetPreferencesDidChangePayload(instanceID: instanceID)
            )
            return .null
        case "camera.listDevices":
            let selectedCameraID = resolvedPreferenceValues(
                widgetID: widgetID,
                instanceID: instanceID.uuidString
            )[cameraDevicePreferenceName]?.stringValue
            return try encodeRuntimeJSONValue(
                WidgetCameraRegistry.shared.availableDevices(selectedDeviceID: selectedCameraID)
            )
        case "camera.selectDevice":
            let cameraParams = try decode(params, as: RuntimeCameraSelectDeviceParams.self)
            try storage.setPreferenceValue(
                widgetID: widgetID,
                instanceID: instanceID.uuidString,
                name: cameraDevicePreferenceName,
                value: RuntimeJSONValue.string(cameraParams.id)
            )
            NotificationCenter.default.post(
                name: .widgetPreferencesDidChange,
                object: WidgetPreferencesDidChangePayload(instanceID: instanceID)
            )
            return .null
        case "media.getState":
            return try encodeRuntimeJSONValue(try await media.getState())
        case "media.play":
            try await media.play()
            return .null
        case "media.pause":
            try await media.pause()
            return .null
        case "media.togglePlayPause":
            try await media.togglePlayPause()
            return .null
        case "media.nextTrack":
            try await media.nextTrack()
            return .null
        case "media.previousTrack":
            try await media.previousTrack()
            return .null
        case "media.openSourceApp":
            try await media.openSourceApp()
            return .null
        case "audio.getState":
            try requireAudioCapability(
                for: widgetID,
                widgetDefinition: widgetDefinition
            )
            return try encodeRuntimeJSONValue(audio.getState(instanceID: instanceID))
        case "audio.play":
            try requireAudioCapability(
                for: widgetID,
                widgetDefinition: widgetDefinition
            )
            let audioParams = try decode(params, as: RuntimeAudioPlayParams.self)
            try audio.play(
                widgetID: widgetID,
                instanceID: instanceID,
                widgetDefinition: widgetDefinition,
                params: audioParams
            )
            return .null
        case "audio.pause":
            try requireAudioCapability(
                for: widgetID,
                widgetDefinition: widgetDefinition
            )
            let audioParams = try decode(params, as: RuntimeAudioPlayerIDParams.self)
            try audio.pause(instanceID: instanceID, params: audioParams)
            return .null
        case "audio.togglePlayPause":
            try requireAudioCapability(
                for: widgetID,
                widgetDefinition: widgetDefinition
            )
            let audioParams = try decode(params, as: RuntimeAudioPlayerIDParams.self)
            try audio.togglePlayPause(instanceID: instanceID, params: audioParams)
            return .null
        case "audio.stop":
            try requireAudioCapability(
                for: widgetID,
                widgetDefinition: widgetDefinition
            )
            let audioParams = try decode(params, as: RuntimeAudioPlayerIDParams.self)
            try audio.stop(instanceID: instanceID, params: audioParams)
            return .null
        case "audio.setVolume":
            try requireAudioCapability(
                for: widgetID,
                widgetDefinition: widgetDefinition
            )
            let audioParams = try decode(params, as: RuntimeAudioSetVolumeParams.self)
            try audio.setVolume(instanceID: instanceID, params: audioParams)
            return .null
        case "audio.pauseAll":
            try requireAudioCapability(
                for: widgetID,
                widgetDefinition: widgetDefinition
            )
            try audio.pauseAll(instanceID: instanceID)
            return .null
        case "audio.resumeAll":
            try requireAudioCapability(
                for: widgetID,
                widgetDefinition: widgetDefinition
            )
            try audio.resumeAll(instanceID: instanceID)
            return .null
        case "audio.stopAll":
            try requireAudioCapability(
                for: widgetID,
                widgetDefinition: widgetDefinition
            )
            audio.stopAll(instanceID: instanceID)
            return .null
        case "notifications.schedule":
            guard let notifications else {
                throw RuntimeTransportRPCError(
                    code: -32000,
                    message: "Widget notifications are unavailable.",
                    data: nil
                )
            }
            try requireNotificationCapability(
                for: widgetID,
                widgetDefinition: widgetDefinition
            )
            let notificationParams = try decode(params, as: RuntimeScheduleNotificationParams.self)

            guard Preferences.widgetNotificationsEnabled else {
                log("Widget notifications: skipped scheduling for \(widgetID)/\(instanceID) because global delivery is disabled.")
                return .null
            }

            guard notificationsEnabled(
                widgetID: widgetID,
                instanceID: instanceID.uuidString
            ) else {
                log("Widget notifications: skipped scheduling for \(widgetID)/\(instanceID) because this widget instance has notifications disabled.")
                await notifications.cancelAllNotifications(widgetID: widgetID, instanceID: instanceID.uuidString)
                return .null
            }

            try await notifications.schedule(
                notificationRequest(
                    widgetID: widgetID,
                    instanceID: instanceID.uuidString,
                    params: notificationParams
                )
            )
            return .null
        case "notifications.cancel":
            guard let notifications else {
                throw RuntimeTransportRPCError(
                    code: -32000,
                    message: "Widget notifications are unavailable.",
                    data: nil
                )
            }
            try requireNotificationCapability(
                for: widgetID,
                widgetDefinition: widgetDefinition
            )
            let notificationParams = try decode(params, as: RuntimeCancelNotificationParams.self)
            await notifications.cancel(
                widgetID: widgetID,
                instanceID: instanceID.uuidString,
                notificationID: notificationParams.id
            )
            return .null
        default:
            throw RuntimeTransportRPCError(
                code: -32601,
                message: "Unsupported widget host RPC '\(method)'.",
                data: nil
            )
        }
    }

    private func decode<Result: Decodable>(_ value: RuntimeJSONValue?, as type: Result.Type) throws -> Result {
        let data = try jsonEncoder.encode(value ?? .null)
        return try jsonDecoder.decode(type, from: data)
    }

    private func encodeRuntimeJSONValue<Result: Encodable>(_ value: Result) throws -> RuntimeJSONValue {
        let data = try jsonEncoder.encode(value)
        return try jsonDecoder.decode(RuntimeJSONValue.self, from: data)
    }

    private func resolvedPreferenceValues(
        widgetID: String,
        instanceID: String
    ) -> [String: RuntimeJSONValue] {
        guard let storage = storage as? WidgetStorageManager else {
            return storage.preferenceValues(widgetID: widgetID, instanceID: instanceID)
        }

        let viewManager = ViewManager()
        let preferences = viewManager.definition(for: widgetID)?.preferences ?? []
        let storagePreferences = preferences.map {
            WidgetStoragePreferenceDefinition(
                name: $0.name,
                kind: storagePreferenceKind(for: $0.type),
                isRequired: $0.isRequired,
                defaultValue: $0.defaultValue
            )
        }

        return storage.resolvedPreferenceValues(
            widgetID: widgetID,
            preferences: storagePreferences,
            instanceID: instanceID
        )
    }

    private func storagePreferenceKind(for type: WidgetPreferenceType) -> WidgetStoragePreferenceKind {
        switch type {
        case .textfield:
            return .text
        case .password:
            return .password
        case .checkbox:
            return .checkbox
        case .dropdown:
            return .dropdown
        case .camera:
            return .camera
        }
    }

    private func requireNotificationCapability(
        for widgetID: String,
        widgetDefinition: WidgetDefinition?
    ) throws {
        if widgetDefinition?.supportsNotifications == true {
            return
        }

        throw RuntimeTransportRPCError(
            code: -32030,
            message: "Widget '\(widgetID)' does not declare notification support.",
            data: nil
        )
    }

    private func requireAudioCapability(
        for widgetID: String,
        widgetDefinition: WidgetDefinition?
    ) throws {
        if widgetDefinition?.supportsAudio == true {
            return
        }

        throw RuntimeTransportRPCError(
            code: -32030,
            message: "Widget '\(widgetID)' does not declare audio support.",
            data: nil
        )
    }

    private func notificationsEnabled(
        widgetID: String,
        instanceID: String
    ) -> Bool {
        guard let storage = storage as? WidgetStorageManager else {
            return true
        }

        return storage.notificationsEnabled(
            widgetID: widgetID,
            instanceID: instanceID,
            defaultValue: true
        )
    }

    private func notificationRequest(
        widgetID: String,
        instanceID: String,
        params: RuntimeScheduleNotificationParams
    ) throws -> WidgetHostNotificationRequest {
        let notificationID = params.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = params.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notificationID.isEmpty else {
            throw RuntimeTransportRPCError(
                code: -32602,
                message: "Notification id must be a non-empty string.",
                data: nil
            )
        }
        guard !title.isEmpty else {
            throw RuntimeTransportRPCError(
                code: -32602,
                message: "Notification title must be a non-empty string.",
                data: nil
            )
        }
        guard params.deliverAtMs.isFinite else {
            throw RuntimeTransportRPCError(
                code: -32602,
                message: "Notification deliverAtMs must be a finite timestamp.",
                data: nil
            )
        }

        let body = params.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WidgetHostNotificationRequest(
            widgetID: widgetID,
            instanceID: instanceID,
            notificationID: notificationID,
            title: title,
            body: body?.isEmpty == false ? body : nil,
            deliverAt: Date(timeIntervalSince1970: params.deliverAtMs / 1000)
        )
    }

    func removeInstance(_ instanceID: UUID) {
        audio.removeAllPlayers(instanceID: instanceID)
    }
}
