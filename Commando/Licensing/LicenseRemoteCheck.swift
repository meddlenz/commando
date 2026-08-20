//
//  LicenseRemoteCheck.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

enum LicenseRemoteCheck {
    struct RemoteResult {
        var banned: Bool
        var ok: Bool
    }

    static var responseOverride: RemoteResult?
    static var checkURLOverride: URL?
    static var reportURLOverride: URL?
    static var skipNetwork: Bool = false

    static func refresh(token: String, version: String, reason: String = "activation") -> RemoteResult? {
        if let responseOverride {
            return responseOverride
        }

        if skipNetwork || LicenseStatus.storageDirectoryOverride != nil {
            return nil
        }

        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty, let url = requestURL(token: trimmed, version: version, reason: reason) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        return perform(request)
    }

    static func reportTamper(token: String, detail: String, version: String) {
        if skipNetwork || LicenseStatus.storageDirectoryOverride != nil {
            return
        }

        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count == 12, let url = reportURL() else {
            return
        }

        var request = URLRequest(url: url)

        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "token": trimmed,
            "reason": "integrity",
            "version": version,
            "detail": detail,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let data,
                  let report = parseReportResponse(data: data),
                  report.banned else {
                return
            }

            DispatchQueue.main.async {
                LicenseStatus.applyAutoBanFromServer()
            }
        }.resume()
    }

    private struct ReportResponse {
        var banned: Bool
    }

    private static func parseReportResponse(data: Data) -> ReportResponse? {
        struct Payload: Decodable {
            var banned: Bool?
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.banned == true else {
            return nil
        }

        return ReportResponse(banned: true)
    }

    static func parseResponse(data: Data) -> RemoteResult? {
        struct Payload: Decodable {
            var banned: Bool
            var ok: Bool?
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }

        return RemoteResult(banned: payload.banned, ok: payload.ok ?? !payload.banned)
    }

    static func requestURL(token: String, version: String, reason: String, baseURL: URL = AppInfo.licenseCheckURL) -> URL? {
        var components = URLComponents(url: checkURLOverride ?? baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "reason", value: reason),
        ]

        return components?.url
    }

    private static func reportURL() -> URL? {
        reportURLOverride ?? AppInfo.licenseReportURL
    }

    private static func perform(_ request: URLRequest) -> RemoteResult? {
        let semaphore = DispatchSemaphore(value: 0)
        var parsed: RemoteResult?

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
