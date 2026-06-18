//
//  TerminalAppSettings.swift
//  Commando
//

import AppKit
import Foundation

enum TerminalAppSettings {
    static let defaultPath = "/System/Applications/Utilities/Terminal.app"
    private static let pathKey = "terminalAppPath"
    private static let legacyKey = "terminalApplication"

    static var selectedAppPath: String {
        get {
            if let path = UserDefaults.standard.string(forKey: pathKey),
               !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                return path
            }

            if let legacy = UserDefaults.standard.string(forKey: legacyKey) {
                switch legacy {
                case "iTerm":
                    let itermPath = "/Applications/iTerm.app"
                    if FileManager.default.fileExists(atPath: itermPath) {
                        return itermPath
                    }
                default:
                    break
                }
            }

            return defaultPath
        }
        set {
            UserDefaults.standard.set(newValue, forKey: pathKey)
            NotificationCenter.default.post(name: .commandSetsDidChange, object: nil)
        }
    }

    static var selectedAppName: String {
        displayName(for: selectedAppPath)
    }

    static var selectedBundleIdentifier: String? {
        Bundle(path: selectedAppPath)?.bundleIdentifier
    }

    static func displayName(for appPath: String) -> String {
        if let bundle = Bundle(path: appPath),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }

    @discardableResult
    static func promptForApplication() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Choose Terminal Application"
        panel.message = "Select the terminal app Commando should use to run commands."
        panel.allowedFileTypes = ["app"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        selectedAppPath = url.path
        return url.path
    }
}
