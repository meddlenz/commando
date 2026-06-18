//
//  CommandSetSidebarRow.swift
//  Commando
//

import SwiftUI

struct CommandSetSidebarRow: View {
    let commandSet: CommandSet
    let isSelected: Bool
    let onSelect: () -> Void
    let onRun: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            systemIcon(commandSet.isRemote ? "externaldrive" : "apple.terminal", fallback: commandSet.isRemote ? "S" : ">")
                .foregroundColor(.accentColor)
                .frame(width: 18)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(commandSet.name.isEmpty ? "Untitled" : commandSet.name)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                Text(commandSet.menuSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: onRun) {
                systemIcon("play.circle", fallback: "▶")
                    .foregroundColor(.accentColor)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .font(.system(size: 16))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
