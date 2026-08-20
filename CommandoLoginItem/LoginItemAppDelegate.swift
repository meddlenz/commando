//
//  LoginItemAppDelegate.swift
//  Commando Login Item
//  Jordan Trbuhovic 2026
//

import Cocoa

@main
final class LoginItemAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let mainAppURL = MainAppLocator.mainAppURL() else {
            NSApp.terminate(nil)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false

        NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration) { _, _ in
            NSApp.terminate(nil)
        }
    }
}
