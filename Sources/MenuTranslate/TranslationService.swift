import Foundation

struct Translation {
    let text: String
    let detectedSourceCode: String?
}

enum TranslationError: LocalizedError {
    case rateLimited
    case badStatus(Int)
    case unreadableResponse
    case offline

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Google is rate limiting this Mac — wait a moment."
        case .badStatus(let code):
            return "Google Translate returned HTTP \(code)."
        case .unreadableResponse:
            return "Could not read the response from Google Translate."
        case .offline:
            return "No network connection."
        }
    }
}

/// Talks to the endpoint the Google Translate website itself uses. No API key,
/// no billing account — the trade-off is that it is undocumented and rate
/// limited per IP, so keep requests debounced.
enum TranslationService {
    static let characterLimit = 5000

    private static let endpoint = URL(string: "https://translate.googleapis.com/translate_a/single")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static func translate(_ text: String, from source: String, to target: String) async throws -> Translation {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "dj", value: "1"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target),
        ]

        // The text goes in the body: a long selection would blow past URL
        // length limits as a query parameter.
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.httpBody = "q=\(formEncoded(text))".data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .cannotFindHost {
            throw TranslationError.offline
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429 ? TranslationError.rateLimited : TranslationError.badStatus(http.statusCode)
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw TranslationError.unreadableResponse
        }

        let translated = (payload.sentences ?? []).compactMap(\.trans).joined()
        return Translation(text: translated, detectedSourceCode: payload.src)
    }

    static func webURL(text: String, from source: String, to target: String) -> URL {
        var components = URLComponents(string: "https://translate.google.com/")!
        components.queryItems = [
            URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "op", value: "translate"),
        ]
        return components.url!
    }

    private struct Payload: Decodable {
        struct Sentence: Decodable {
            let trans: String?
        }

        let sentences: [Sentence]?
        let src: String?
    }

    private static func formEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
