//
//  LicenseBanCheck.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

enum LicenseBanCheck {
    static var responseOverride: Bool?
    static var checkURLOverride: URL?

    static func isBanned(token: String) -> Bool {
        if let responseOverride {
            return responseOverride
        }

        if LicenseStatus.storageDirectoryOverride != nil {
            return false
        }

        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return false
        }

        guard let url = requestURL(token: trimmed) else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let result = perform(request)

        return result ?? false
    }

    static func parseResponse(data: Data) -> Bool? {
        struct Payload: Decodable {
            var banned: Bool
        }

        return try? JSONDecoder().decode(Payload.self, from: data).banned
    }

    static func requestURL(token: String, baseURL: URL = AppInfo.licenseCheckURL) -> URL? {
        var components = URLComponents(url: checkURLOverride ?? baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
       
         return components?.url
    }

    private static func perform(_ request: URLRequest) -> Bool? {
        let semaphore = DispatchSemaphore(value: 0)
        var parsed: Bool?

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let data else {
                return
            }

            parsed = parseResponse(data: data)
        }.resume()

        _ = semaphore.wait(timeout: .now() + 10)
        return parsed
    }
}
