//
//  UpdateChecker.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import AppKit
import Foundation

enum UpdateChecker {
    private static let updateInfoURL = URL(string: "https://manticore.nz/commando/commando.xml")!
    private static var dismissedVersionThisSession: String?

    static func checkForUpdateIfNeeded() {
        var request = URLRequest(url: updateInfoURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode),
                  let data,
                  let updateInfo = UpdateInfoParser.parse(data),
                  let remoteVersion = updateInfo.currentMacOS,
                  let changeLog = updateInfo.currentMacOSChangeLog,
                  isVersion(remoteVersion, greaterThan: localVersion()) else {
                return
            }

            let message = decodeChangeLog(changeLog)
            guard !message.isEmpty else {
                return
            }

            guard dismissedVersionThisSession != remoteVersion else {
                return
            }

            DispatchQueue.main.async {
                showUpdateAvailable(
                    message: message,
                    remoteVersion: remoteVersion,
                    updateInfo: updateInfo
                )
            }
        }.resume()
    }

    private static func localVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func isVersion(_ remote: String, greaterThan local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").map { Int($0) ?? 0 }
        let localParts = local.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(remoteParts.count, localParts.count)

        for index in 0 ..< count {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let localValue = index < localParts.count ? localParts[index] : 0

            if remoteValue > localValue {
                return true
            }

            if remoteValue < localValue {
                return false
            }
        }

        return false
    }

    private static func decodeChangeLog(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;br&gt;", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func updateURL(_ url: URL?) -> URL? {
        guard let normalizedURL = normalizedUpdateURL(url),
              isAllowedUpdateURL(normalizedURL) else {
            return nil
        }

        return normalizedURL
    }

    static func isAllowedUpdateURL(_ url: URL?) -> Bool {
        guard let url = normalizedUpdateURL(url),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host?.lowercased() else {
            return false
        }

        return allowedUpdateHosts.contains(host)
    }

    private static func normalizedUpdateURL(_ url: URL?) -> URL? {
        guard var url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              allowedUpdateHosts.contains(host) else {
            return nil
        }

        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
            guard let upgradedURL = components.url else {
                return nil
            }

            url = upgradedURL
        }

        return url
    }

    private static let allowedUpdateHosts: Set<String> = [
        "files.mac-attic.com",
        "manticore.nz",
    ]

    private static func updateURL(for updateInfo: UpdateInfo) -> URL? {
        updateURL(updateInfo.macOSUrl)
    }

    static func updateActionTitle() -> String {
        "Download"
    }

    private static func showUpdateAvailable(message: String, remoteVersion: String, updateInfo: UpdateInfo) {
        UpdateWindowController.show(
            version: remoteVersion,
            message: message,
            updateURL: updateURL(for: updateInfo),
            onLater: {
                dismissedVersionThisSession = remoteVersion
            }
        )
    }
}

private struct UpdateInfo {
    let currentMacOS: String?
    let currentMacOSChangeLog: String?
    let macOSUrl: URL?
}

private final class UpdateInfoParser: NSObject, XMLParserDelegate {
    private var currentMacOS: String?
    private var currentMacOSChangeLog: String?
    private var macOSUrl: URL?
    private var currentText = ""

    static func parse(_ data: Data) -> UpdateInfo? {
        let parser = UpdateInfoParser()
        let xmlParser = XMLParser(data: data)

        xmlParser.delegate = parser

        guard xmlParser.parse() else {
            return nil
        }

        return UpdateInfo(
            currentMacOS: parser.currentMacOS,
            currentMacOSChangeLog: parser.currentMacOSChangeLog,
            macOSUrl: parser.macOSUrl
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "currentMacOS":
            currentMacOS = trimmed
        case "currentMacOSChangeLog":
            currentMacOSChangeLog = trimmed
        case "macOSUrl":
            macOSUrl = URL(string: trimmed)
        default:
            break
        }
    }
}
