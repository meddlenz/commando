//
//  SettingsWindowController.swift
//  Commando
//

import Cocoa
import SwiftUI

class SettingsWindowController: NSWindowController {

    private static var sharedInstance: SettingsWindowController?

    static func show() {
        sharedInstance?.close()
        sharedInstance = SettingsWindowController()
        sharedInstance?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Commando"
        window.minSize = NSSize(width: 720, height: 480)
        window.center()
        window.setFrameAutosaveName("Settings")
        window.contentViewController = NSHostingController(rootView: MainView())
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
