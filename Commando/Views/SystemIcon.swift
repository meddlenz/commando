//
//  SystemIcon.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import SwiftUI

@ViewBuilder
func systemIcon(_ name: String, fallback: String = "•") -> some View {
    if #available(macOS 11.0, *) {
        Image(systemName: name)
    } else {
        Text(fallback)
            .font(.system(size: 12, weight: .medium))
    }
}
