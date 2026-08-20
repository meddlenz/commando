//
//  UpdateWindowController.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Cocoa
import SwiftUI

final class UpdateWindowController: NSWindowController, NSWindowDelegate {
    private static var sharedInstance: UpdateWindowController?

    static func show(
        version: String,
        message: String,
        updateURL: URL?,
        required: Bool = false,
        onLater: @escaping () -> Void
    ) {
        DockIconSettings.showDockForOpenWindow()

        if !required {
            sharedInstance?.close()
        }

        sharedInstance = UpdateWindowController(
            version: version,
            message: message,
            updateURL: updateURL,
            required: required,
            onLater: onLater
        )
        sharedInstance?.showWindow(nil)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            sharedInstance?.window?.makeKeyAndOrderFront(nil)
        }
    }

    private let updateURL: URL?
    private let onLater: () -> Void
    private let required: Bool

    private init(
        version: String,
        message: String,
        updateURL: URL?,
        required: Bool,
        onLater: @escaping () -> Void
    ) {
        self.updateURL = updateURL
        self.onLater = onLater
        self.required = required

        let styleMask: NSWindow.StyleMask = required ? [.titled] : [.titled, .closable]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        window.title = required ? "Update Required" : "Update Available"
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)

        window.delegate = self
        centerTitle(required ? "Update Required" : "Update Available", in: window)
        window.contentViewController = NSHostingController(
            rootView: UpdateView(
                version: version,
                message: message,
                downloadEnabled: updateURL != nil,
                showsLaterButton: !required,
                onDownload: { [weak self] in
                    self?.downloadUpdate()
                },
                onLater: { [weak self] in
                    self?.dismissLater()
                }
            )
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        if required {
            return
        }

        if UpdateWindowController.sharedInstance === self {
            UpdateWindowController.sharedInstance = nil
        }

        DockIconSettings.refreshAfterWindowClosed()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        window?.orderFrontRegardless()
    }

    private func downloadUpdate() {
        guard let updateURL,
              UpdateChecker.isAllowedUpdateURL(updateURL) else {
            return
        }

        NSWorkspace.shared.open(updateURL)
        close()
    }

    private func dismissLater() {
        onLater()
        close()
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
