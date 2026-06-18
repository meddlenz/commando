//
//  ValidationBanner.swift
//  Commando
//

import SwiftUI

struct ValidationBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            systemIcon("exclamationmark.triangle.fill", fallback: "!")
            Text(message)
            Spacer()
        }
        .font(.caption)
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.85))
    }
}
