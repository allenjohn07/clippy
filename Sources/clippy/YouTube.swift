import Foundation

/// Recognises YouTube links and fetches their thumbnail and title.
enum YouTube {
    private static let idPattern = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_\-]{11}$"#)
    private static let hosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]

    /// The 11-character video ID if `text` is a single YouTube video link, else nil.
    static func videoID(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: { $0.isWhitespace }),
              let comps = URLComponents(string: t), let host = comps.host?.lowercased(),
              ["http", "https"].contains(comps.scheme?.lowercased() ?? "") else { return nil }

        var candidate: String?
        let parts = comps.path.split(separator: "/").map(String.init)
        if host == "youtu.be" || host == "www.youtu.be" {
            candidate = parts.first
        } else if hosts.contains(host) {
            if comps.path == "/watch" {
                candidate = comps.queryItems?.first(where: { $0.name == "v" })?.value
            } else if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) {
                candidate = parts[1]
            }
        }
        guard let id = candidate,
              idPattern.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil else { return nil }
        return id
    }

    /// No cookies or cache shared with anything else.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    /// Responses larger than this are ignored (a thumbnail is ~20–50 KB, the title JSON ~1 KB).
    private static let maxResponseBytes = 2 * 1024 * 1024

    /// Fetches the thumbnail (JPEG) and title. Either may be nil if the request fails.
    static func fetchMetadata(url: String, videoID: String) async -> (title: String?, thumbnail: Data?) {
        async let thumb: Data? = {
            guard let u = URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg"),
                  let (data, resp) = try? await session.data(from: u),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= maxResponseBytes else { return nil }
            return data
        }()
        async let title: String? = {
            var c = URLComponents(string: "https://www.youtube.com/oembed")!
            c.queryItems = [URLQueryItem(name: "url", value: url), URLQueryItem(name: "format", value: "json")]
            guard let u = c.url, let (data, resp) = try? await session.data(from: u),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= maxResponseBytes,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return (json["title"] as? String).map { String($0.prefix(300)) }
        }()
        return await (title, thumb)
    }
}
