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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Commando v\(version) available")
                .font(.headline)

            ScrollView {
                Text(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 180)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Button(action: { NSWorkspace.shared.open(AppInfo.newsURL) }) {
                    Text("View full change log")
                        .font(.footnote)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())

                HStack(spacing: 12) {
                    Button("Later", action: onLater)
                    DefaultActionButton(
                        title: UpdateChecker.updateActionTitle(),
                        isEnabled: downloadEnabled,
                        action: onDownload
                    )
                    .fixedSize()
                }
            }
        }
        .padding(24)
        .frame(width: 420)
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
