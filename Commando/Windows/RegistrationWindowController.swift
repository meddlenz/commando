//
//  RegistrationWindowController.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Cocoa
import SwiftUI

final class RegistrationWindowController: NSWindowController, NSWindowDelegate {

    private static var sharedInstance: RegistrationWindowController?

    static func show() {
        DockIconSettings.showDockForOpenWindow()

        sharedInstance?.close()
        sharedInstance = RegistrationWindowController()
        sharedInstance?.showWindow(nil)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            sharedInstance?.window?.makeKeyAndOrderFront(nil)
        }
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Register Commando"
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: RegistrationView(
                onRegistered: { [weak self] in
                    self?.close()
                },
                onCancel: { [weak self] in
                    self?.close()
                }
            )
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        DockIconSettings.refreshAfterWindowClosed()
        
        if Self.sharedInstance === self {
            Self.sharedInstance = nil
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        window?.orderFrontRegardless()
    }
}
