//
//  RegistrationView.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import SwiftUI
import AppKit

struct RegistrationView: View {
    var onRegistered: () -> Void
    var onCancel: () -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var key = ""
    @State private var errorMessage: String?
    @State private var didRegister = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if didRegister {
                Text("Thank you for purchasing Commando!")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                HStack {
                    Spacer()
                    Button("Close", action: onRegistered)
                    Spacer()
                }
                .padding(.top, 8)
            } else {
                registrationForm
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var registrationForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Purchase Commando") {
                NSWorkspace.shared.open(AppInfo.purchaseURL)
            }

            Text("Enter the name and email used when your license was issued. Registration keys begin with COMMANDO1. All details are case-sensitive.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            labeledField("Full name", text: $name)
            labeledField("Email", text: $email)
            labeledField("License key", text: $key)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Register", action: register)
            }
            .padding(.top, 8)
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                
            TextField(title, text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }

    private func register() {
        do {
            try LicenseStatus.register(name: name, email: email, key: key)
            errorMessage = nil
            didRegister = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
