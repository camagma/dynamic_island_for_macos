import Foundation

struct GmailNotification: Identifiable {
    let id: String
    let sender: String
    let subject: String
    let snippet: String

    var senderDisplayName: String {
        let trimmed = sender.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = trimmed.range(of: " <") {
            return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }

        return trimmed.isEmpty ? "Gmail" : trimmed
    }
}

struct GmailInboxPage {
    let messages: [GmailNotification]
    let nextPageToken: String?
}

@MainActor
final class GmailService {
    private enum Keys {
        static let isEnabled = "GmailAPI.isEnabled"
        static let accessToken = "GmailAPI.accessToken"
        static let refreshToken = "GmailAPI.refreshToken"
        static let clientID = "GmailAPI.clientID"
        static let clientSecret = "GmailAPI.clientSecret"
        static let tokenExpirationDate = "GmailAPI.tokenExpirationDate"
        static let seenMessageIDs = "GmailAPI.seenMessageIDs"
        static let didCompleteInitialScan = "GmailAPI.didCompleteInitialScan"
        static let seenInboxMessageIDs = "GmailAPI.seenInboxMessageIDs"
        static let didCompleteInboxInitialScan = "GmailAPI.didCompleteInboxInitialScan"
    }

    private struct ListResponse: Decodable {
        let messages: [MessageReference]?
        let nextPageToken: String?
    }

    private struct MessageReference: Decodable {
        let id: String
    }

    private struct MessageResponse: Decodable {
        let id: String
        let snippet: String?
        let payload: MessagePayload?

        func headerValue(named name: String) -> String? {
            payload?.headers?.first {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }?.value
        }
    }

    private struct MessagePayload: Decodable {
        let headers: [MessageHeader]?
    }

    private struct MessageHeader: Decodable {
        let name: String
        let value: String
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    var isConfigured: Bool {
        guard defaults.bool(forKey: Keys.isEnabled) else {
            return false
        }

        if !accessToken.isEmpty {
            return true
        }

        return !refreshToken.isEmpty && !clientID.isEmpty
    }

    func pollUnreadMessages() async throws -> [GmailNotification] {
        guard isConfigured else {
            return []
        }

        do {
            return try await pollUnreadMessagesWithCurrentToken()
        } catch GmailError.unauthorized {
            try await refreshAccessToken()
            return try await pollUnreadMessagesWithCurrentToken()
        }
    }

    func pollNewInboxMessages() async throws -> [GmailNotification] {
        guard isConfigured else {
            return []
        }

        do {
            return try await pollNewInboxMessagesWithCurrentToken()
        } catch GmailError.unauthorized {
            try await refreshAccessToken()
            return try await pollNewInboxMessagesWithCurrentToken()
        }
    }

    func recentUnreadMessages(limit: Int = 3) async throws -> [GmailNotification] {
        guard isConfigured else {
            return []
        }

        do {
            return try await recentUnreadMessagesWithCurrentToken(limit: limit)
        } catch GmailError.unauthorized {
            try await refreshAccessToken()
            return try await recentUnreadMessagesWithCurrentToken(limit: limit)
        }
    }

    func inboxPage(pageToken: String?, pageSize: Int = 5) async throws -> GmailInboxPage {
        guard isConfigured else {
            return GmailInboxPage(messages: [], nextPageToken: nil)
        }

        do {
            return try await inboxPageWithCurrentToken(pageToken: pageToken, pageSize: pageSize)
        } catch GmailError.unauthorized {
            try await refreshAccessToken()
            return try await inboxPageWithCurrentToken(pageToken: pageToken, pageSize: pageSize)
        }
    }

    private func pollUnreadMessagesWithCurrentToken() async throws -> [GmailNotification] {
        let token = try await validAccessToken()
        let references = try await listUnreadMessages(maxResults: 5, accessToken: token)
        let ids = references.map(\.id)
        let knownIDs = Set(defaults.stringArray(forKey: Keys.seenMessageIDs) ?? [])
        let newIDs = ids.filter { !knownIDs.contains($0) }

        defaults.set(mergedSeenIDs(newIDs: ids, knownIDs: knownIDs), forKey: Keys.seenMessageIDs)
        defaults.set(true, forKey: Keys.didCompleteInitialScan)

        return try await notifications(for: Array(newIDs.prefix(3)), accessToken: token)
    }

    private func pollNewInboxMessagesWithCurrentToken() async throws -> [GmailNotification] {
        let token = try await validAccessToken()
        let response = try await listInboxMessages(maxResults: 10, pageToken: nil, accessToken: token)
        let ids = response.messages?.map(\.id) ?? []
        let knownIDs = Set(defaults.stringArray(forKey: Keys.seenInboxMessageIDs) ?? [])
        let didCompleteInitialScan = defaults.bool(forKey: Keys.didCompleteInboxInitialScan)
        let newIDs = ids.filter { !knownIDs.contains($0) }

        defaults.set(mergedSeenIDs(newIDs: ids, knownIDs: knownIDs), forKey: Keys.seenInboxMessageIDs)
        defaults.set(true, forKey: Keys.didCompleteInboxInitialScan)

        guard didCompleteInitialScan else {
            return []
        }

        return try await notifications(for: Array(newIDs.prefix(3)), accessToken: token)
    }

    private func recentUnreadMessagesWithCurrentToken(limit: Int) async throws -> [GmailNotification] {
        let token = try await validAccessToken()
        let references = try await listUnreadMessages(maxResults: limit, accessToken: token)
        return try await notifications(for: references.map(\.id), accessToken: token)
    }

    private func inboxPageWithCurrentToken(pageToken: String?, pageSize: Int) async throws -> GmailInboxPage {
        let token = try await validAccessToken()
        let response = try await listInboxMessages(maxResults: pageSize, pageToken: pageToken, accessToken: token)

        return GmailInboxPage(
            messages: try await notifications(for: response.messages?.map(\.id) ?? [], accessToken: token),
            nextPageToken: response.nextPageToken
        )
    }

    private func notifications(for ids: [String], accessToken: String) async throws -> [GmailNotification] {
        var notifications: [GmailNotification] = []

        for id in ids {
            let message = try await getMessage(id: id, accessToken: accessToken)
            notifications.append(
                GmailNotification(
                    id: message.id,
                    sender: message.headerValue(named: "From") ?? "Gmail",
                    subject: message.headerValue(named: "Subject") ?? "New email",
                    snippet: message.snippet ?? ""
                )
            )
        }

        return notifications
    }

    private func validAccessToken() async throws -> String {
        if !accessToken.isEmpty,
           tokenExpirationDate.timeIntervalSinceNow > 60 {
            return accessToken
        }

        if !refreshToken.isEmpty && !clientID.isEmpty {
            try await refreshAccessToken()
            return accessToken
        }

        if !accessToken.isEmpty {
            return accessToken
        }

        throw GmailError.notConfigured
    }

    private func listUnreadMessages(maxResults: Int, accessToken: String) async throws -> [MessageReference] {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")
        components?.queryItems = [
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
            URLQueryItem(name: "q", value: "is:unread newer_than:1d")
        ]

        guard let url = components?.url else {
            throw GmailError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        return try decoder.decode(ListResponse.self, from: data).messages ?? []
    }

    private func listInboxMessages(maxResults: Int, pageToken: String?, accessToken: String) async throws -> ListResponse {
        var queryItems = [
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
            URLQueryItem(name: "q", value: "in:inbox")
        ]

        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw GmailError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        return try decoder.decode(ListResponse.self, from: data)
    }

    private func mergedSeenIDs(newIDs: [String], knownIDs: Set<String>) -> [String] {
        var result: [String] = []

        for id in newIDs where !result.contains(id) {
            result.append(id)
        }

        for id in knownIDs where !result.contains(id) && result.count < 80 {
            result.append(id)
        }

        return result
    }

    private func getMessage(id: String, accessToken: String) async throws -> MessageResponse {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject")
        ]

        guard let url = components?.url else {
            throw GmailError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        return try decoder.decode(MessageResponse.self, from: data)
    }

    private func refreshAccessToken() async throws {
        guard !refreshToken.isEmpty,
              !clientID.isEmpty else {
            throw GmailError.notConfigured
        }

        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GmailError.invalidURL
        }

        var fields: [String: String] = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        if !clientSecret.isEmpty {
            fields["client_secret"] = clientSecret
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(fields)

        let (data, response) = try await session.data(for: request)
        try validate(response)

        let token = try decoder.decode(TokenResponse.self, from: data)
        defaults.set(token.accessToken, forKey: Keys.accessToken)
        defaults.set(Date().addingTimeInterval(token.expiresIn ?? 3600), forKey: Keys.tokenExpirationDate)
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        if httpResponse.statusCode == 401 {
            throw GmailError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GmailError.httpStatus(httpResponse.statusCode)
        }
    }

    private func formBody(_ fields: [String: String]) -> Data {
        fields
            .map { key, value in
                "\(escape(key))=\(escape(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private var accessToken: String {
        defaults.string(forKey: Keys.accessToken) ?? ""
    }

    private var refreshToken: String {
        defaults.string(forKey: Keys.refreshToken) ?? ""
    }

    private var clientID: String {
        defaults.string(forKey: Keys.clientID) ?? ""
    }

    private var clientSecret: String {
        defaults.string(forKey: Keys.clientSecret) ?? ""
    }

    private var tokenExpirationDate: Date {
        defaults.object(forKey: Keys.tokenExpirationDate) as? Date ?? .distantPast
    }
}

private extension GmailService {
    enum GmailError: Error {
        case notConfigured
        case invalidURL
        case unauthorized
        case httpStatus(Int)
    }
}
