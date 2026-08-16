//
//  MainView.swift
//  Commando
//  Jordan Trbuhovic 2026
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

private struct EditableSession: Identifiable, Equatable {
    let id: UUID

    var name: String
    var steps: [EditableStep]

    init(id: UUID = UUID(), name: String = "", steps: [EditableStep] = [EditableStep()]) {
        self.id = id
        self.name = name
        self.steps = steps.isEmpty ? [EditableStep()] : steps
    }
}

struct MainView: View {
    @State private var commandSets: [CommandSet] = CommandStore.commandSets
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var serverDetails = ""
    @State private var isServerConnectionEnabled = false
    @State private var editableSessions: [EditableSession] = []
    @State private var isEditing = false
    @State private var validationMessage: String?

    private var parsedServerConnection: SSHConnection? {
        SSHConnection.parse(from: SSHConnection.normaliseServerDetails(serverDetails))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailPanel
        }
         .frame(minWidth: 760, minHeight: 540)
        .onReceive(NotificationCenter.default.publisher(for: .commandSetsDidChange)) { _ in
            commandSets = CommandStore.commandSets
        }
    }

    // Sidebar

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

    // Details

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
                            Text("Use user@host or user@host:port, not the full ssh command.")
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
                    help: "Steps in a session run in order. Parallel sessions split the window or open additional windows if splitting isn't available."
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(editableSessions.enumerated()), id: \.element.id) { sessionIndex, session in
                            if sessionIndex > 0 {
                                Divider()
                                    .padding(.vertical, 8)
                            }

                            if editableSessions.count > 1 {
                                HStack {
                                    Text("Session \(sessionIndex + 1)")
                                        .foregroundColor(.secondary)
                                    TextField("Name", text: sessionNameBinding(for: session.id))
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                    
                                    Button("Remove") {
                                        removeSession(id: session.id)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .foregroundColor(.red)
                                }
                            }

                            ForEach(session.steps) { step in
                                StepRow(
                                    index: (session.steps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1,
                                    text: stepTextBinding(sessionID: session.id, stepID: step.id),
                                    onDelete: { deleteStep(sessionID: session.id, stepID: step.id) }
                                )
                                .frame(maxWidth: .infinity)
                            }

                            
                            Button(action: { addStep(to: session.id) }) {
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
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }

                        Divider()
                            .padding(.vertical, 8)

                        Button(action: addSession) {
                            HStack {
                                systemIcon("square.split.2x1", fallback: "+|")
                                .foregroundColor(.accentColor)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                                .font(.system(size: 16))
                                Text("Add Parallel Session")
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
                Button("Set Up SSH Key...", action: setUpSSHKey)
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

    // Actions

    private func setUpSSHKey() {
        guard let connection = parsedServerConnection else {
            validationMessage = "Enter a valid server (username@host) before setting up an SSH key."

            return
        }

        guard SSHKeySetupPrompt.confirm(for: connection) else {
            return
        }

        validationMessage = nil

        do {
            try SSHKeySetup.installKey(on: connection)
        } catch {
            SSHKeySetupPrompt.showError(error)
        }
    }

    private func startCreating() {
        editingID = nil
        name = ""
        serverDetails = ""
        isServerConnectionEnabled = false
        editableSessions = [EditableSession()]
        isEditing = true
        validationMessage = nil
    }

    private func editCommandSet(_ commandSet: CommandSet) {
        editingID = commandSet.id
        name = commandSet.name
        serverDetails = commandSet.serverDetails
        isServerConnectionEnabled = !commandSet.serverDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        editableSessions = commandSet.sessions.map { session in
            EditableSession(name: session.name, steps: session.steps.map { EditableStep(text: $0) })
        }

        if editableSessions.isEmpty {
            editableSessions = [EditableSession()]
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

        let trimmedServer = isServerConnectionEnabled ? SSHConnection.normaliseServerDetails(serverDetails) : ""
       
        if !trimmedServer.isEmpty && SSHConnection.parse(from: trimmedServer) == nil {
            validationMessage = "Server must be username@host or username@host:port (without ssh)."

            return
        }

        let mapped = editableSessions.map { session in
            CommandSession(name: session.name, steps: session.steps.map(\.text))
        }

        let pruned = mapped.filter { session in
            session.steps.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        let sessions = pruned.isEmpty ? [CommandSession(name: mapped.first?.name ?? "")] : pruned
        let hasCommand = sessions.contains { session in
            session.steps.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        guard hasCommand || !trimmedServer.isEmpty else {
            validationMessage = "Add at least one command step."

            return
        }

        let commandSetID = editingID ?? UUID()
        let updated = CommandSet(
            id: commandSetID,
            name: trimmedName,
            serverDetails: trimmedServer,
            sessions: sessions
        )

        if let editingID, let index = commandSets.firstIndex(where: { $0.id == editingID }) {
            commandSets[index] = updated
        } else {
            commandSets.append(updated)
        }

        CommandStore.commandSets = commandSets
        isEditing = false
        editingID = nil
        validationMessage = nil
    }

    private func cancelEditing() {
        isEditing = false
        editingID = nil
        validationMessage = nil
    }

    private func deleteStep(sessionID: UUID, stepID: UUID) {
        guard let sessionIndex = editableSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        editableSessions[sessionIndex].steps.removeAll { $0.id == stepID }

        if editableSessions[sessionIndex].steps.isEmpty {
            editableSessions[sessionIndex].steps = [EditableStep()]
        }
    }

    private func stepTextBinding(sessionID: UUID, stepID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let session = editableSessions.first(where: { $0.id == sessionID }) else {
                    return ""
                }


                return session.steps.first(where: { $0.id == stepID })?.text ?? ""
            },
            set: { newValue in
                guard let sessionIndex = editableSessions.firstIndex(where: { $0.id == sessionID }),
                      let stepIndex = editableSessions[sessionIndex].steps.firstIndex(where: { $0.id == stepID }) else {
                   
                    return
                }
                editableSessions[sessionIndex].steps[stepIndex].text = newValue
            }
        )
    }

    private func addStep(to sessionID: UUID) {
        guard let sessionIndex = editableSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        editableSessions[sessionIndex].steps.append(EditableStep())
    }

    private func sessionNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                editableSessions.first(where: { $0.id == id })?.name ?? ""
            },
            set: { newValue in
                guard let index = editableSessions.firstIndex(where: { $0.id == id }) else {
                    return
                }

                editableSessions[index].name = newValue
            }
        )
    }

    private func addSession() {
        editableSessions.append(EditableSession())
    }

    private func removeSession(id: UUID) {
        guard editableSessions.count > 1 else {
            return
        }
        
        editableSessions.removeAll { $0.id == id }
    }

    private func deleteCommandSets(at offsets: IndexSet) {
        for index in offsets {
            let id = commandSets[index].id
            ExampleCommandSet.markRemovedIfNeeded(id)
            KeychainCredentialStore.deletePassword(for: id)
        }

        commandSets.remove(atOffsets: offsets)
        CommandStore.commandSets = commandSets

        if let editingID, !commandSets.contains(where: { $0.id == editingID }) {
            cancelEditing()
        }
    }

    private func deleteEditingCommandSet() {
        guard let editingID,
              let index = commandSets.firstIndex(where: { $0.id == editingID }) else {
                return
             }

             
        ExampleCommandSet.markRemovedIfNeeded(editingID)
        KeychainCredentialStore.deletePassword(for: editingID)
        commandSets.remove(at: index)
        CommandStore.commandSets = commandSets
        
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
