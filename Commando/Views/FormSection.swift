//
//  FormSection.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import SwiftUI

struct FormSection<Content: View>: View {
    let title: String
    let help: String?
    let content: Content

    init(title: String, help: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.help = help
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let help {
                    Text(help)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            content
        }
    }
}
