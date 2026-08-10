//
//  AboutWindowController.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Cocoa
import SwiftUI

final class AboutWindowController: NSWindowController, NSWindowDelegate {

    private static var sharedInstance: AboutWindowController?

    static func show() {
        DockIconSettings.showDockForOpenWindow()

        if sharedInstance == nil {
            sharedInstance = AboutWindowController()
        }

        sharedInstance?.showWindow(nil)
        
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            sharedInstance?.window?.makeKeyAndOrderFront(nil)
        }
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
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)

        window.delegate = self
        
        centerTitle("About", in: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        DockIconSettings.refreshAfterWindowClosed()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        window?.orderFrontRegardless()
    }

    private func centerTitle(_ title: String, in window: NSWindow) {
        window.titleVisibility = .hidden

        guard let titlebarView = window.standardWindowButton(.closeButton)?.superview else {
            return
        }

        let titleLabel = NSTextField(labelWithString: title)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titlebarView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: titlebarView.centerYAnchor),
        ])
    }
}

