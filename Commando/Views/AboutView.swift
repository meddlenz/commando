//
//  AboutView.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import AppKit
import SwiftUI

struct AboutView: View {
    @State private var licenseRevision = 0

    var body: some View {
        VStack(spacing: 16) {
            appIcon
                .frame(width: 64, height: 64)

            Text(AppInfo.name)
                .font(.system(size: 22, weight: .semibold))

            Text("Version \(AppInfo.version)")
                .foregroundColor(.secondary)

            Button(action: openCompanyWebsite) {
                Text("Manticore Software")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())

            if let registeredLine = LicenseStatus.registeredLine {
                Text(registeredLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .id(licenseRevision)
            } else if AppDistribution.usesDirectLicensing {
                Button("Enter license key", action: { RegistrationWindowController.show() })
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.accentColor)
            }



            Text("Run saved terminal commands from your menu bar.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            if !AppInfo.copyright.isEmpty {
                Text(AppInfo.copyright)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }


            HStack(spacing: 12) {
                Button(action: { openURL(AppInfo.privacyURL) }) {
                    Text("Privacy Policy")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())


                Button(action: { openURL(AppInfo.termsURL) }) {
                    Text("Terms of Use")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
             }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(width: 380)
        .onReceive(NotificationCenter.default.publisher(for: .licenseDidChange)) { _ in
            licenseRevision += 1
        }

    }

    @ViewBuilder
    private var appIcon: some View {
        if let image = NSImage(named: NSImage.Name("AppIcon")) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.accentColor.opacity(0.2))
                .overlay(
                     Text("CR")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.accentColor)
                )
        }
    }

    private func openCompanyWebsite() {
        openURL(AppInfo.companyURL)
    }

    private func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
