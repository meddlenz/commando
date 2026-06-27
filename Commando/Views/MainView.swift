//
//  MainView.swift
//  Commando
//

import AppKit
import SwiftUI

private struct EditableStep: Identifiable, Equatable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }
}

struct MainView: View {
    @State private var commandSets: [CommandSet] = UserDefaults.standard.commandSets
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var serverDetails = ""
    @State private var isServerConnectionEnabled = false
    @State private var editableSteps: [EditableStep] = []
    @State private var isEditing = false
    @State private var validationMessage: String?
    @State private var sshKeySetupMessage: String?

    private var parsedServerConnection: SSHConnection? {
        SSHConnection.parse(from: SSHConnection.normalizeServerDetails(serverDetails))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailPanel
        }
        .frame(minWidth: 760, minHeight: 540)
        .onReceive(NotificationCenter.default.publisher(for: .commandSetsDidChange)) { _ in
            commandSets = UserDefaults.standard.commandSets
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Command Sets")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            List {
                Button(action: startCreating) {
                    SidebarActionRow(
                        icon: "plus.circle",
                        fallback: "+",
                        title: "Add New"
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .listRowBackground(Color.clear)

                if commandSets.isEmpty {
                    Text("No command sets yet")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(commandSets) { commandSet in
                        CommandSetSidebarRow(
                            commandSet: commandSet,
                            isSelected: editingID == commandSet.id && isEditing,
                            onSelect: { editCommandSet(commandSet) },
                            onRun: { runCommandSet(commandSet) }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: deleteCommandSets)
                }
            }
            .listStyle(PlainListStyle())

            Divider()

            Button(action: { PreferencesWindowController.show() }) {
                SidebarActionRow(
                    icon: "gear",
                    fallback: "⚙",
                    title: "Settings",
                    iconColor: .secondary
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        }
        .frame(width: 260)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Detail

    private var detailPanel: some View {
        VStack(spacing: 0) {
            if let validationMessage {
                ValidationBanner(message: validationMessage)
            }

            Group {
                if isEditing {
                    editorForm
                } else {
                    emptyDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isEditing {
                Divider()
                editorToolbar
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            systemIcon("terminal.fill", fallback: ">_")
                .font(.system(size: 44))
                .foregroundColor(Color.secondary.opacity(0.6))
            Text("Select a command set")
                .font(.system(size: 20, weight: .medium))
            Text("Choose one from the list, or create a new command set to run from the menu bar.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 320)
            Button("Create Command Set", action: startCreating)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FormSection(title: "Name", help: "Shown in the menu bar when you run this set.") {
                    TextField("My Command Set", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                FormSection(title: "SSH") {
                    Toggle("Connect to a remote server", isOn: $isServerConnectionEnabled)

                    if isServerConnectionEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Optional. Use user@host or user@host:port, not the full ssh command.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextField("admin@256.256.256.256", text: $serverDetails)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(.body, design: .monospaced))

                            if parsedServerConnection != nil {
                                remoteServerOptions
                            }
                        }
                    }
                }

                FormSection(
                    title: "Commands",
                    help: "Command steps are run in order and wait for the previous to finish."
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(editableSteps) { step in
                            StepRow(
                                index: (editableSteps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1,
                                text: stepTextBinding(for: step.id),
                                onDelete: { deleteStep(id: step.id) }
                            )
                            .frame(maxWidth: .infinity)
                        }

                        Button(action: addStep) {
                            HStack {
                                systemIcon("plus.circle", fallback: "+")
                                .foregroundColor(.accentColor)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                                .font(.system(size: 16))
                                Text("Add Step")
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity, alignment: .center)

                    }
                }
            }
            .padding(24)
        }
    }

    private var remoteServerOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack {
                Button("Set Up SSH Key…", action: setUpSSHKey)
                if SSHKeySetup.hasLocalKey() {
                    HStack(spacing: 4) {
                        systemIcon("checkmark.circle.fill", fallback: "✓")
                        Text("Local key found")
                    }
                    .font(.caption)
                    .foregroundColor(.green)
                }
            }

            Text("Set up an SSH key once to connect without entering a password.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let sshKeySetupMessage {
                Text(sshKeySetupMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var editorToolbar: some View {
        HStack {
            if editingID != nil {
                Button("Delete Command Set", action: deleteEditingCommandSet)
                    .foregroundColor(.red)
            }
            Spacer()
            Button("Cancel", action: cancelEditing)
            saveButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var saveButton: some View {
        Group {
            if #available(macOS 11.0, *) {
                Button("Save", action: saveCommandSet)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Save", action: saveCommandSet)
            }
        }
    }

    // MARK: - Actions

    private func setUpSSHKey() {
        guard let connection = parsedServerConnection else {
            validationMessage = "Enter a valid server (username@host) before setting up an SSH key."
            return
        }

        guard let password = SSHKeySetupPrompt.prompt(for: connection) else {
            return
        }

        sshKeySetupMessage = "Installing SSH key on \(connection.username)@\(connection.host)…"
        validationMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try SSHKeySetup.installKey(on: connection, password: password)
                DispatchQueue.main.async {
                    sshKeySetupMessage = "SSH key installed on \(connection.username)@\(connection.host)."
                    SSHKeySetupPrompt.showSuccess(for: connection)
                }
            } catch {
                DispatchQueue.main.async {
                    sshKeySetupMessage = nil
                    SSHKeySetupPrompt.showError(error)
                }
            }
        }
    }

    private func startCreating() {
        editingID = nil
        name = ""
        serverDetails = ""
        isServerConnectionEnabled = false
        editableSteps = [EditableStep()]
        isEditing = true
        validationMessage = nil
        sshKeySetupMessage = nil
    }

    private func editCommandSet(_ commandSet: CommandSet) {
        editingID = commandSet.id
        name = commandSet.name
        serverDetails = commandSet.serverDetails
        isServerConnectionEnabled = !commandSet.serverDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        editableSteps = commandSet.steps.map { EditableStep(text: $0) }
        if editableSteps.isEmpty {
            editableSteps = [EditableStep()]
        }
        isEditing = true
        validationMessage = nil
    }

    private func saveCommandSet() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Name is required."
            return
        }

        let trimmedServer = isServerConnectionEnabled ? SSHConnection.normalizeServerDetails(serverDetails) : ""
        if !trimmedServer.isEmpty && SSHConnection.parse(from: trimmedServer) == nil {
            validationMessage = "Server must be username@host or username@host:port (without ssh)."
            return
        }
        let stepTexts = editableSteps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonEmptySteps = stepTexts.filter { !$0.isEmpty }
        guard !nonEmptySteps.isEmpty || !trimmedServer.isEmpty else {
            validationMessage = "Add at least one command step."
            return
        }

        let commandSetID = editingID ?? UUID()
        let updated = CommandSet(
            id: commandSetID,
            name: trimmedName,
            serverDetails: trimmedServer,
            steps: editableSteps.map(\.text)
        )

        if let editingID, let index = commandSets.firstIndex(where: { $0.id == editingID }) {
            commandSets[index] = updated
        } else {
            commandSets.append(updated)
        }

        UserDefaults.standard.commandSets = commandSets
        isEditing = false
        editingID = nil
        validationMessage = nil
    }

    private func cancelEditing() {
        isEditing = false
        editingID = nil
        validationMessage = nil
        sshKeySetupMessage = nil
    }

    private func deleteStep(id: UUID) {
        editableSteps.removeAll { $0.id == id }
        if editableSteps.isEmpty {
            editableSteps = [EditableStep()]
        }
    }

    private func stepTextBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                editableSteps.first(where: { $0.id == id })?.text ?? ""
            },
            set: { newValue in
                guard let index = editableSteps.firstIndex(where: { $0.id == id }) else { return }
                editableSteps[index].text = newValue
            }
        )
    }

    private func addStep() {
        editableSteps.append(EditableStep())
    }

    private func deleteCommandSets(at offsets: IndexSet) {
        for index in offsets {
            let id = commandSets[index].id
            ExampleCommandSet.markRemovedIfNeeded(id)
            KeychainCredentialStore.deletePassword(for: id)
        }
        commandSets.remove(atOffsets: offsets)
        UserDefaults.standard.commandSets = commandSets

        if let editingID, !commandSets.contains(where: { $0.id == editingID }) {
            cancelEditing()
        }
    }

    private func deleteEditingCommandSet() {
        guard let editingID,
              let index = commandSets.firstIndex(where: { $0.id == editingID }) else { return }
        ExampleCommandSet.markRemovedIfNeeded(editingID)
        KeychainCredentialStore.deletePassword(for: editingID)
        commandSets.remove(at: index)
        UserDefaults.standard.commandSets = commandSets
        cancelEditing()
    }

    private func runCommandSet(_ commandSet: CommandSet) {
        do {
            try CommandExecutor.run(commandSet)
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

private struct SidebarActionRow: View {
    let icon: String
    let fallback: String
    let title: String
    var iconColor: Color = .accentColor

    var body: some View {
        HStack(spacing: 10) {
            systemIcon(icon, fallback: fallback)
                .foregroundColor(iconColor)
                .frame(width: 18)
                .font(.system(size: 16))

            Text(title)
                .fontWeight(.regular)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
