//
//  TerminalAppSettings.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import AppKit
import Foundation

enum TerminalAppSettings {
    static let defaultPath = "/System/Applications/Utilities/Terminal.app"
    static let supportedTerminalNames = ["Terminal", "iTerm2", "Warp", "Ghostty"]

    private static let pathKey = "terminalAppPath"
    private static let legacyKey = "terminalApplication"
    private static let bookmarkKey = "terminalAppSecurityScopedBookmark"
    private static let bookmarkPathKey = "terminalAppSecurityScopedBookmarkPath"


    struct SecurityScopedAppAccess {
        fileprivate let url: URL?
        fileprivate let didStartAccessing: Bool

        func stopAccessingIfNeeded() {
            if didStartAccessing {
                url?.stopAccessingSecurityScopedResource()
            }

        }
    }

    static var selectedAppPath: String {
        get {
            if let bookmarkedURL = resolvedBookmarkedAppURL(),
               FileManager.default.fileExists(atPath: bookmarkedURL.path) {
                return bookmarkedURL.path
            }

            if let path = UserDefaults.standard.string(forKey: pathKey),
               !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                storeSecurityScopedBookmarkIfPossible(for: URL(fileURLWithPath: path, isDirectory: true))

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
            storeSecurityScopedBookmarkIfPossible(for: URL(fileURLWithPath: newValue, isDirectory: true))
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

    static func securityScopedAccess(for appPath: String) -> SecurityScopedAppAccess {
        guard let bookmarkedURL = resolvedBookmarkedAppURL() else {
            return SecurityScopedAppAccess(url: nil, didStartAccessing: false)
        }

        let selectedPath = URL(fileURLWithPath: appPath, isDirectory: true)
            .resolvingSymlinksInPath()
            .path


        let bookmarkedPath = bookmarkedURL
            .resolvingSymlinksInPath()
            .path 


        guard selectedPath == bookmarkedPath else {
            return SecurityScopedAppAccess(url: nil, didStartAccessing: false)
        }

        let didStart = bookmarkedURL.startAccessingSecurityScopedResource()

        return SecurityScopedAppAccess(url: bookmarkedURL, didStartAccessing: didStart)
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
        storeSecurityScopedBookmarkIfPossible(for: url)
        showUnsupportedTerminalWarningIfNeeded(for: url.path)
        promptForWarpAccessIfNeeded(for: url.path)


        return url.path
    }

    private static func promptForWarpAccessIfNeeded(for appPath: String) {
        guard officiallySupportedTerminalName(for: appPath) == "Warp" else {
            return
        }
        guard WarpConfigAccess.securityScopedAccess(for: appPath).url == nil else {
            return
        }

        _ = WarpConfigAccess.promptForAccess(for: appPath)
    }

    static func isOfficiallySupportedTerminal(appPath: String) -> Bool {
        officiallySupportedTerminalName(for: appPath) != nil
    }

    static func officiallySupportedTerminalName(for appPath: String) -> String? {
        let bundle = Bundle(path: appPath)
        let bundleId = bundle?.bundleIdentifier?.lowercased() ?? ""
        let displayName = displayName(for: appPath).lowercased()
        let executableName = bundle?.executableURL?.lastPathComponent.lowercased() ?? ""
        let pathName = (appPath as NSString).lastPathComponent.lowercased()
        let combined = [bundleId, displayName, executableName, pathName].joined(separator: " ")

        if bundleId == "com.apple.terminal" || displayName == "terminal" {
            return "Terminal"
        }

        if bundleId == "com.googlecode.iterm2" || combined.contains("iterm") {
            return "iTerm2"
        }

        if combined.contains("warp") {
            return "Warp"
        }

        if combined.contains("ghostty") {
            return "Ghostty"
        }

        return nil
    }

    private static func showUnsupportedTerminalWarningIfNeeded(for appPath: String) {
        guard !isOfficiallySupportedTerminal(appPath: appPath) else { return }

        let selectedName = displayName(for: appPath)
        let alert = NSAlert()


        alert.alertStyle = .warning
        alert.messageText = "Terminal app may not be fully supported"
        alert.informativeText = "Commando officially supports \(supportedTerminalNames.joined(separator: ", ")). Commando will try a generic launch method with \(selectedName), it's unlikely to work."
        alert.addButton(withTitle: "Continue")
        alert.runModal()
    }

    private static func resolvedBookmarkedAppURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false

        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                storeSecurityScopedBookmarkIfPossible(for: url)
            }

            return url
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            UserDefaults.standard.removeObject(forKey: bookmarkPathKey)
            return nil
        }
    }

    private static func storeSecurityScopedBookmarkIfPossible(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
            UserDefaults.standard.set(url.path, forKey: bookmarkPathKey)
        } catch {
           // Nothing to do bro
        }
    }
}
