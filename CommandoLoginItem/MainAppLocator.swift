//
//  MainAppLocator.swift
//  Commando Login Item
//  Jordan Trbuhovic 2026
//

import AppKit
import Foundation

enum MainAppLocator {
    static let mainAppBundleIdentifier = "com.manticoresw.commando"

    static func mainAppURL(helperBundleURL: URL = Bundle.main.bundleURL) -> URL? {
        if let containingApp = containingAppBundleURL(from: helperBundleURL) {
            return containingApp
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: mainAppBundleIdentifier)
    }

    static func containingAppBundleURL(from helperBundleURL: URL) -> URL? {
        var url = helperBundleURL.deletingLastPathComponent()

        while url.path != "/" {
            if url.pathExtension == "app" {
                return url
            }

            url.deleteLastPathComponent()
        }

        return nil
    }
}
