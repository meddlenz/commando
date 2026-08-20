//
//  WarpConfigAccess.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import AppKit
import Darwin
import Foundation

enum WarpConfigAccess {

    struct SecurityScopedDirectoryAccess {
        let url: URL?
        fileprivate let didStartAccessing: Bool

        func stopAccessingIfNeeded() {
            if didStartAccessing {
                url?.stopAccessingSecurityScopedResource()
            }
        }
    }

    static func configDirectoryName(for appPath: String) -> String {
        let bundleId = Bundle(path: appPath)?.bundleIdentifier?.lowercased() ?? ""
        let displayName = TerminalAppSettings.displayName(for: appPath).lowercased()
        let pathName = (appPath as NSString).lastPathComponent.lowercased()

        if bundleId.contains("preview") || displayName.contains("preview") || pathName.contains("preview") {
            return ".warp-preview"
        }

        return ".warp"
    }

    static func defaultConfigDirectoryURL(for appPath: String) -> URL {
        realUserHomeDirectoryURL
            .appendingPathComponent(configDirectoryName(for: appPath), isDirectory: true)
    }

    static func isExpectedConfigDirectory(_ url: URL, for appPath: String) -> Bool {
        let selectedPath = url
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path


        let expectedPath = defaultConfigDirectoryURL(for: appPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path

        return selectedPath == expectedPath
    }

    static func securityScopedAccess(for appPath: String) -> SecurityScopedDirectoryAccess {
        let bookmarkKey = bookmarkKey(for: appPath)

        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return SecurityScopedDirectoryAccess(url: nil, didStartAccessing: false)
        }

        var isStale = false

        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            guard isExpectedConfigDirectory(url, for: appPath) else {
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                return SecurityScopedDirectoryAccess(url: nil, didStartAccessing: false)
            }

            if isStale {
                _ = storeSecurityScopedBookmark(for: url, appPath: appPath)
            }

            let didStart = url.startAccessingSecurityScopedResource()

            return SecurityScopedDirectoryAccess(url: url, didStartAccessing: didStart)
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)

            return SecurityScopedDirectoryAccess(url: nil, didStartAccessing: false)
        }
    }

    @discardableResult
    static func promptForAccess(for appPath: String) -> Bool {
        let directoryName = configDirectoryName(for: appPath)
        let displayPath = "~/\(directoryName)"
        let explanation = NSAlert()

        explanation.alertStyle = .informational
        explanation.messageText = "Allow access to \(displayPath)"
        explanation.informativeText = """
        Warp reads custom tab configurations from \(displayPath)/tab_configs. Commando needs one-time permission to write its commando.toml file there.

        The next dialog will automatically try to find \(displayPath) so you can select it. Select the \(directoryName) folder itself.
        """
        explanation.addButton(withTitle: "Choose \(directoryName) Folder")
        explanation.addButton(withTitle: "Cancel")

        guard explanation.runModal() == .alertFirstButtonReturn else {
            return false
        }

        let expectedURL = defaultConfigDirectoryURL(for: appPath)
        let panel = NSOpenPanel()

        panel.title = "Select \(displayPath)"
        panel.message = "Select the \(directoryName) folder."
        panel.prompt = "Select \(directoryName)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = expectedURL

        while panel.runModal() == .OK {
            guard let url = panel.url else {
                return false
            }

            guard isExpectedConfigDirectory(url, for: appPath) else {
                let wrongFolder = NSAlert()
                wrongFolder.alertStyle = .warning
                wrongFolder.messageText = "That isn't the \(directoryName) folder"
                wrongFolder.informativeText = """
                You selected:
                \(abbreviatedPath(url))

                Commando needs:
                \(displayPath)
                """
                wrongFolder.addButton(withTitle: "Try Again")
                wrongFolder.addButton(withTitle: "Cancel")

                guard wrongFolder.runModal() == .alertFirstButtonReturn else {
                    return false
                }

                panel.directoryURL = expectedURL
                continue
            }

            return storeSecurityScopedBookmark(for: url, appPath: appPath)
        }

        return false
    }

    private static func bookmarkKey(for appPath: String) -> String {
        "warpConfigSecurityScopedBookmark.\(configDirectoryName(for: appPath))"
    }

    @discardableResult
    private static func storeSecurityScopedBookmark(for url: URL, appPath: String) -> Bool {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey(for: appPath))
            
            return true 
        } catch {
            return false
        }
    }

    private static func abbreviatedPath(_ url: URL) -> String {
        let homePath = realUserHomeDirectoryURL.path
        guard url.path.hasPrefix(homePath) else {
            return url.path
        }
        
        return "~" + String(url.path.dropFirst(homePath.count))
    }

    private static var realUserHomeDirectoryURL: URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }
}
