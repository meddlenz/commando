//
//  SettingsWindowController.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Cocoa
import SwiftUI

class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private static var sharedInstance: SettingsWindowController?

    static func show() {
        if DockIconSettings.isHidden {
            NSApp.setActivationPolicy(.regular)
            }
            
        if let instance = sharedInstance, let window = instance.window, window.isVisible {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }

            instance.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            return
        }

        sharedInstance?.close()
        sharedInstance = SettingsWindowController()
        sharedInstance?.showWindow(nil)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            sharedInstance?.window?.makeKeyAndOrderFront(nil)
        }
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
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentViewController = NSHostingController(rootView: MainView())
        super.init(window: window)

        window.delegate = self
        centerTitle("Commando", in: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        if DockIconSettings.isHidden {
            DockIconSettings.applyPolicy()
        }
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

