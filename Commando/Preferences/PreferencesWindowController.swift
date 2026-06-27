//
//  PreferencesWindowController.swift
//  Commando
//

import AppKit

final class PreferencesWindowController: NSWindowController {

    private static var sharedInstance: PreferencesWindowController?

    static func show() {
        sharedInstance?.close()
        sharedInstance = PreferencesWindowController()
        sharedInstance?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.backgroundColor = .preferencesPanelBackground
        window.center()
        window.setFrameAutosaveName("Settings")
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]

        if #available(macOS 13.0, *) {
            window.toolbarStyle = .preference
        }

        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        window?.orderFrontRegardless()
    }

    private func buildContent() {
        guard let window else { return }
        window.contentViewController = PreferencesTabViewController(hostWindow: window)
    }
}

// MARK: - Tabs

private final class PreferencesTabViewController: NSTabViewController {
    private weak var hostWindow: NSWindow?

    init(hostWindow: NSWindow) {
        self.hostWindow = hostWindow
        super.init(nibName: nil, bundle: nil)

        if #available(macOS 11.0, *) {
            tabStyle = .toolbar
        }

        let general = NSTabViewItem(viewController: GeneralPreferencesViewController())
        general.label = "General"
        if #available(macOS 11.0, *) {
            general.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: nil)
        }

        let terminal = NSTabViewItem(viewController: TerminalPreferencesViewController())
        terminal.label = "Terminal"
        if #available(macOS 11.0, *) {
            terminal.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        }

        tabViewItems = [general, terminal]

        hostWindow.setContentSize(NSSize(width: 420, height: 260))
        hostWindow.minSize = NSSize(width: 420, height: 220)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateWindowHeight(animated: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        updateWindowHeight(animated: true)
    }

    private func updateWindowHeight(animated: Bool) {
        guard let window = hostWindow else { return }
        guard let contentView = window.contentView else { return }

        contentView.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()

        let width: CGFloat = 420
        let selectedViewController = tabView.selectedTabViewItem?.viewController
        let preferredHeight: CGFloat

        if let sizable = selectedViewController as? PreferencesSizable {
            preferredHeight = sizable.preferredContentHeight
        } else {
            preferredHeight = selectedViewController?.view.fittingSize.height ?? view.fittingSize.height
        }

        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 80
        let height = min(max(220, preferredHeight), maxHeight)
        let newSize = NSSize(width: width, height: height)

        if animated {
            window.animator().setContentSize(newSize)
        } else {
            window.setContentSize(newSize)
        }
    }
}

private protocol PreferencesSizable {
    var preferredContentHeight: CGFloat { get }
}

// MARK: - General

private final class GeneralPreferencesViewController: NSViewController, PreferencesSizable {
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let hideDockIconCheckbox = NSButton(checkboxWithTitle: "Hide dock icon", target: nil, action: nil)
    private let menuBarIconLabel = NSTextField(labelWithString: "Menu bar icon:")
    private let menuBarIconPreview = NSImageView()
    private let menuBarIconPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let menuBarIconStack = NSStackView()
    private let helpLabel = NSTextField(labelWithString: "When hidden, Commando runs from the menu bar only.")
    private let stack = NSStackView()

    override func loadView() {
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.preferencesPanelBackground.cgColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        stack.addArrangedSubview(launchAtLoginCheckbox)

        hideDockIconCheckbox.target = self
        hideDockIconCheckbox.action = #selector(toggleHideDockIcon)
        stack.addArrangedSubview(hideDockIconCheckbox)

        helpLabel.font = .systemFont(ofSize: 11)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.lineBreakMode = .byWordWrapping
        helpLabel.maximumNumberOfLines = 0
        helpLabel.preferredMaxLayoutWidth = 360
        stack.addArrangedSubview(helpLabel)

        menuBarIconLabel.alignment = .right
        menuBarIconLabel.setContentHuggingPriority(.required, for: .horizontal)

        menuBarIconPopup.target = self
        menuBarIconPopup.action = #selector(changeMenuBarIcon)
        menuBarIconPopup.removeAllItems()
        MenuBarIconSettings.Option.allCases.forEach { option in
            menuBarIconPopup.addItem(withTitle: option.title)
            menuBarIconPopup.lastItem?.representedObject = option.rawValue
        }

        menuBarIconPreview.imageScaling = .scaleProportionallyUpOrDown
        menuBarIconPreview.translatesAutoresizingMaskIntoConstraints = false

        menuBarIconStack.orientation = .horizontal
        menuBarIconStack.alignment = .centerY
        menuBarIconStack.distribution = .fill
        menuBarIconStack.spacing = 8
        menuBarIconStack.translatesAutoresizingMaskIntoConstraints = false
        menuBarIconStack.addArrangedSubview(menuBarIconLabel)
        menuBarIconStack.addArrangedSubview(menuBarIconPreview)
        menuBarIconStack.addArrangedSubview(menuBarIconPopup)
        stack.addArrangedSubview(menuBarIconStack)

        view = content

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
            menuBarIconLabel.widthAnchor.constraint(equalToConstant: 90),
            menuBarIconPreview.widthAnchor.constraint(equalToConstant: 18),
            menuBarIconPreview.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    var preferredContentHeight: CGFloat {
        view.layoutSubtreeIfNeeded()
        return stack.fittingSize.height + 36
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        sync()
    }

    private func sync() {
        launchAtLoginCheckbox.state = LaunchAtLoginSettings.isEnabled ? .on : .off
        hideDockIconCheckbox.state = DockIconSettings.isHidden ? .on : .off

        let selectedOption = MenuBarIconSettings.selectedOption
        menuBarIconPopup.selectItem(withTitle: selectedOption.title)
        menuBarIconPreview.image = MenuBarIconSettings.previewImage(for: selectedOption)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLoginSettings.setEnabled(launchAtLoginCheckbox.state == .on)
        } catch {
            NSSound.beep()
            presentPreferenceError(error)
        }
        sync()
    }

    @objc private func toggleHideDockIcon() {
        DockIconSettings.setHidden(hideDockIconCheckbox.state == .on)
        sync()
    }

    @objc private func changeMenuBarIcon() {
        guard let rawValue = menuBarIconPopup.selectedItem?.representedObject as? String,
              let option = MenuBarIconSettings.Option(rawValue: rawValue) else {
            sync()
            return
        }

        MenuBarIconSettings.selectedOption = option
        sync()
    }

    private func presentPreferenceError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Unable to update preference"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: view.window!)
    }
}

// MARK: - Terminal

private final class TerminalPreferencesViewController: NSViewController, PreferencesSizable {
    private let helpLabel = NSTextField(labelWithString: "Commands open in this application.")
    private let appIconView = NSImageView()
    private let appNameLabel = NSTextField(labelWithString: "")
    private let appPathLabel = NSTextField(labelWithString: "")
    private let chooseButton = NSButton(title: "Choose…", target: nil, action: nil)
    private let stack = NSStackView()
    private let appStack = NSStackView()
    private let appTextStack = NSStackView()

    override func loadView() {
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.preferencesPanelBackground.cgColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        helpLabel.font = .systemFont(ofSize: 11)
        helpLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(helpLabel)

        appIconView.imageScaling = .scaleProportionallyUpOrDown
        appIconView.translatesAutoresizingMaskIntoConstraints = false

        appTextStack.orientation = .vertical
        appTextStack.alignment = .leading
        appTextStack.distribution = .fill
        appTextStack.spacing = 2
        appTextStack.translatesAutoresizingMaskIntoConstraints = false

        appNameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        appNameLabel.lineBreakMode = .byTruncatingMiddle
        appTextStack.addArrangedSubview(appNameLabel)

        appPathLabel.font = .systemFont(ofSize: 11)
        appPathLabel.textColor = .secondaryLabelColor
        appPathLabel.lineBreakMode = .byTruncatingMiddle
        appTextStack.addArrangedSubview(appPathLabel)

        appStack.orientation = .horizontal
        appStack.alignment = .centerY
        appStack.distribution = .fill
        appStack.spacing = 10
        appStack.translatesAutoresizingMaskIntoConstraints = false
        appStack.addArrangedSubview(appIconView)
        appStack.addArrangedSubview(appTextStack)
        stack.addArrangedSubview(appStack)

        chooseButton.target = self
        chooseButton.action = #selector(chooseTerminalApp)
        stack.addArrangedSubview(chooseButton)

        view = content

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
            appIconView.widthAnchor.constraint(equalToConstant: 32),
            appIconView.heightAnchor.constraint(equalToConstant: 32),
            appNameLabel.widthAnchor.constraint(equalToConstant: 318),
            appPathLabel.widthAnchor.constraint(equalToConstant: 318)
        ])
    }

    var preferredContentHeight: CGFloat {
        view.layoutSubtreeIfNeeded()
        return stack.fittingSize.height + 36
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        sync()
    }

    private func sync() {
        appIconView.image = NSWorkspace.shared.icon(forFile: TerminalAppSettings.selectedAppPath)
        appNameLabel.stringValue = TerminalAppSettings.selectedAppName
        appPathLabel.stringValue = TerminalAppSettings.selectedAppPath
    }

    @objc private func chooseTerminalApp() {
        if TerminalAppSettings.promptForApplication() != nil {
            sync()
        }
    }
}

// MARK: - Colors

extension NSColor {
    static var preferencesPanelBackground: NSColor {
        namedPreferencesColor(
            light: NSColor(calibratedWhite: 0.90, alpha: 1),
            dark: NSColor(calibratedWhite: 0.18, alpha: 1)
        )
    }

    private static func namedPreferencesColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}
