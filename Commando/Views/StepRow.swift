//
//  StepRow.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import SwiftUI

struct StepRow: View {
    let index: Int
    @Binding var text: String
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("\(index)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .trailing)

            TextField("e.g. cd my-project", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(.body, design: .monospaced))

            if !text.isEmpty {
                Button(action: onDelete) {
                    systemIcon("minus.circle.fill", fallback: "−")
                        .foregroundColor(.red)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}
