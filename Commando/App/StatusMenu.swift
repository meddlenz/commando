//
//  StatusMenu.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Cocoa

extension AppDelegate {

    func configureStatusItem() {
        if let button = statusItem.button {
            let image = statusBarImage()
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = MenuBarIconSettings.selectedOption.usesTemplateRendering
            button.image = image
        }

        constructMenu()
    }

    func constructMenu() {
        let menu = NSMenu()
        let commandSets = UserDefaults.standard.commandSets

        if commandSets.isEmpty {
            let emptyItem = NSMenuItem(title: "No command sets configured", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, commandSet) in commandSets.enumerated() {
                let title = commandSet.name.isEmpty ? commandSet.menuSubtitle : commandSet.name
                let item = NSMenuItem(
                    title: title,
                    action: #selector(runCommandSet(_:)),
                    keyEquivalent: ""
                )

                item.tag = index
                item.target = self
                item.image = playMenuIcon
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let commandSetsMenuItem = NSMenuItem(
            title: "Command Sets",
            action: #selector(openCommandSets),
            keyEquivalent: ""
        )

        commandSetsMenuItem.target = self
        menu.addItem(commandSetsMenuItem)

        let preferencesMenuItem = NSMenuItem(
            title: "Settings",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesMenuItem.target = self
        menu.addItem(preferencesMenuItem)
        menu.addItem(NSMenuItem.separator())

        let aboutMenuItem = NSMenuItem(title: "About", action: #selector(openAbout), keyEquivalent: "")
        aboutMenuItem.target = self
        menu.addItem(aboutMenuItem)

        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
    }

    private func statusBarImage() -> NSImage {
        if let image = NSImage(named: NSImage.Name(MenuBarIconSettings.selectedOption.assetName)),
            image.isValid,
            image.size.width > 0,
            image.size.height > 0 {
                return image
        }

        if let image = NSImage(named: NSImage.Name("MenuBarIcon")),
            image.isValid,
            image.size.width > 0,
            image.size.height > 0 {
                return image
        }

        if let image = NSImage(named: NSImage.Name("AppIcon")),
            image.isValid,
            image.size.width > 0,
            image.size.height > 0 {
                return image
        }

        if let image = NSApp.applicationIconImage,
            image.isValid,
            image.size.width > 0,
            image.size.height > 0 {
                return image
        }

        return Self.fallbackStatusBarImage()
    }

    private static func fallbackStatusBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        ">_".draw(
            in: NSRect(x: 0, y: 1, width: size.width, height: size.height),
            withAttributes: attributes
        )
        image.unlockFocus()

        return image
    }

    static func makePlayMenuIcon() -> NSImage? {
        if #available(macOS 11.0, *) {
            let image = NSImage(systemSymbolName: "apple.terminal.fill", accessibilityDescription: "Run")
            image?.isTemplate = true
            image?.size = NSSize(width: 12, height: 12)
            return image
        }

        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        ">".draw(in: NSRect(x: 2, y: 0, width: size.width, height: size.height), withAttributes: attributes)
        image.unlockFocus()
        image.isTemplate = true
        
        return image
    }
}
