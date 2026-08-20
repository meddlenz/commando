//
//  UpdateView.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import AppKit
import SwiftUI

struct UpdateView: View {
    let version: String
    let message: String
    let downloadEnabled: Bool
    var onDownload: () -> Void
    var onLater: () -> Void

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 20)

            releaseNotesCard
                .padding(.bottom, 12)

            Button(action: { NSWorkspace.shared.open(AppInfo.newsURL) }) {
                Text("View full change log")
                    .font(.footnote)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 16)

            Divider()

            footer
                .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 440)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            appIcon
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Commando Update")
                    .font(.system(size: 15, weight: .semibold))

                Text("Version \(version)")
                    .font(.body)
                    .foregroundColor(.primary)

                Text("You're currently on version \(currentVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var releaseNotesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Release Notes")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ScrollView {
                Text(message)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 140)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Later", action: onLater)
            DefaultActionButton(
                title: UpdateChecker.updateActionTitle(),
                isEnabled: downloadEnabled,
                action: onDownload
            )
            .fixedSize()
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let image = NSImage(named: NSImage.Name("AppIcon")) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.15))
                .overlay(
                    Text("CR")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.accentColor)
                )
        }
    }
}

private struct DefaultActionButton: NSViewRepresentable {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.tapped))
        
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.sizeToFit()
        
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = title
        button.isEnabled = isEnabled
        button.sizeToFit()
    }

    final class Coordinator: NSObject {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
    }
}
