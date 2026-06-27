//
//  AboutWindowController.swift
//  Commando
//

import Cocoa
import SwiftUI

final class AboutWindowController: NSWindowController {

    private static var sharedInstance: AboutWindowController?

    static func show() {
        if sharedInstance == nil {
            sharedInstance = AboutWindowController()
        }
        sharedInstance?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About \(AppInfo.name)"
        window.center()
        window.setFrameAutosaveName("About")
        window.contentViewController = NSHostingController(rootView: AboutView())
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
