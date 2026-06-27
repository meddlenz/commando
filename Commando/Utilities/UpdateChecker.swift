//
//  UpdateChecker.swift
//  Commando
//

import AppKit
import Foundation
import UserNotifications

private enum UpdateNotificationKeys {
    static let downloadURL = "downloadURL"
}

enum UpdateChecker {
    private static let updateInfoURL = URL(string: "https://manticore.nz/commando/commando.xml")!

    static func checkForUpdateIfNeeded() {
        UpdateNotificationDelegate.installIfNeeded()

        var request = URLRequest(url: updateInfoURL)
        request.timeoutInterval = 15

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
            guard !message.isEmpty else { return }

            DispatchQueue.main.async {
                showUpdateNotification(message: message, downloadURL: updateInfo.macOSUrl)
            }
        }.resume()
    }

    private static func localVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static func appDisplayName() -> String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }

        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }

        return "Commando"
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

    private static func showUpdateNotification(message: String, downloadURL: URL?) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        DispatchQueue.main.async {
                            guard granted else { return }
                            deliverUpdateNotification(message: message, downloadURL: downloadURL)
                        }
                    }
                case .authorized, .provisional, .ephemeral:
                    deliverUpdateNotification(message: message, downloadURL: downloadURL)
                default:
                    break
                }
            }
        }
    }

    private static func deliverUpdateNotification(message: String, downloadURL: URL?) {
        let displayMessage = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !displayMessage.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = appDisplayName()
        content.body = displayMessage
        content.sound = .default
        content.threadIdentifier = "software-update"

        if let downloadURL {
            content.userInfo = [UpdateNotificationKeys.downloadURL: downloadURL.absoluteString]
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }
}

private final class UpdateNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UpdateNotificationDelegate()

    static func installIfNeeded() {
        let center = UNUserNotificationCenter.current()
        guard center.delegate !== shared else { return }
        center.delegate = shared
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 12.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        openDownloadURL(from: response.notification.request.content.userInfo)
    }

    private func openDownloadURL(from userInfo: [AnyHashable: Any]) {
        guard let urlString = userInfo[UpdateNotificationKeys.downloadURL] as? String,
              let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
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
