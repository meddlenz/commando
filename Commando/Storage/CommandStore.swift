//
//  CommandStore.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

private let commandSetsKey = "commandSets"
private let legacyServerCommandsKey = "serverCommandsV2"
private let exampleCommandSetRemovedKey = "exampleCommandSetRemoved"
private let iCloudSyncKey = "syncCommandSetsViaiCloud"

enum ExampleCommandSet {
    static let id = UUID(uuidString: "E0000000-0000-4000-8000-C00000000001")!

    static var helloWorld: CommandSet {
        CommandSet(
            id: id,
            name: "Hello World",
            steps: ["echo 'Hello, World!'"]
        )
    }

    static func installIfNeeded() {
        let defaults = UserDefaults.standard

        guard !defaults.bool(forKey: exampleCommandSetRemovedKey) else {
        return
        }

        guard CommandStore.commandSets.isEmpty else {
            return
        }

        CommandStore.commandSets = [helloWorld]
    }

    static func markRemovedIfNeeded(_ id: UUID) {
        guard id == self.id else {
            return
        }

        UserDefaults.standard.set(true, forKey: exampleCommandSetRemovedKey)
    }
}

enum CommandStore {
    enum StoreError: LocalizedError {
        case iCloudUnavailable
        case readFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return "iCloud is not available. Sign in to iCloud in System Settings and try again."
            case .readFailed(let message):
                return message
            case .writeFailed(let message):
                return message
            }
        }
    }

    enum ImportMode {
        case merge
        case replace
    }

    static var storageDirectoryOverride: URL?

    private static let presenter = CommandSetFilePresenter()
    private static var cached: [CommandSet]?
    private static var didStart = false

    static var commandSets: [CommandSet] {
        get {
            if let cached {
                return cached
            }

            let loaded = loadFromActiveFile() ?? migrateLegacyIfNeeded()
            cached = loaded

            return loaded
        }
        set {
            cached = newValue
            do {
                try write(newValue, to: activeFileURL())
            } catch {
                return
            }
            NotificationCenter.default.post(name: .commandSetsDidChange, object: nil)
        }
    }

    static var isCloudSyncEnabled: Bool {
        storageDirectoryOverride == nil && UserDefaults.standard.bool(forKey: iCloudSyncKey)
    }

    static func start() {
        guard !didStart else {
            return
        
        }
        didStart = true

        _ = commandSets
        presenter.activate(url: try? activeFileURL())

        NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { _ in
            handleIdentityChange()
        }
    }

    static func setCloudSyncEnabled(_ enabled: Bool) throws {
        guard storageDirectoryOverride == nil else {
            return
        
        }

        if enabled {
            let cloudURL = try activeiCloudFileURL()
            let localSets = load(from: localFileURL()) ?? cached ?? []
            let cloudSets = load(from: cloudURL) ?? []
            let merged: [CommandSet]

            if cloudSets.isEmpty {
                merged = localSets
            } else if localSets.isEmpty {
                merged = cloudSets
            } else {
                merged = CommandSetDocument.merge(cloudSets, with: localSets)
            }

            try write(merged, to: cloudURL)

            UserDefaults.standard.set(true, forKey: iCloudSyncKey)
            cached = merged
        } else {
            let current = commandSets

            try write(current, to: localFileURL())
            UserDefaults.standard.set(false, forKey: iCloudSyncKey)
            cached = current
        }

        presenter.activate(url: try? activeFileURL())
        NotificationCenter.default.post(name: .commandSetsDidChange, object: nil)
    }

    static func importDocument(from url: URL, mode: ImportMode) throws {
        let accessed = url.startAccessingSecurityScopedResource()

        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let imported = try CommandSetDocument.decode(data)

        switch mode {
        case .replace:
            commandSets = imported
        case .merge:
            commandSets = CommandSetDocument.merge(commandSets, with: imported)
        }
    }

    static func exportDocument(to url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try write(commandSets, to: url)
    }

    static func resetCache() {
        cached = nil
    }

    fileprivate static func handleExternalChange() {
        let loaded = loadFromActiveFile() ?? []

        DispatchQueue.main.async {
            guard loaded != cached else {
                return
            
            }
            cached = loaded
            NotificationCenter.default.post(name: .commandSetsDidChange, object: nil)
        }
    }

    private static func handleIdentityChange() {
        cached = nil
        presenter.activate(url: try? activeFileURL())
        _ = commandSets
        NotificationCenter.default.post(name: .commandSetsDidChange, object: nil)
    }

    private static func loadFromActiveFile() -> [CommandSet]? {
        guard let url = try? activeFileURL() else {
            return nil
        
        }

        if FileManager.default.fileExists(atPath: url.path) {
            return load(from: url) ?? []
        }

        if isCloudSyncEnabled, FileManager.default.isUbiquitousItem(at: url) {
            return load(from: url) ?? []
        }

        return nil
    }

    private static func load(from url: URL) -> [CommandSet]? {
        downloadIfNeeded(url)

        var coordinatorError: NSError?
        var loaded: [CommandSet]?
        let coordinator = NSFileCoordinator(filePresenter: presenter)

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            guard FileManager.default.fileExists(atPath: readURL.path),
                  let data = try? Data(contentsOf: readURL) else {
                return
            }

            loaded = try? CommandSetDocument.decode(data)
        }

        return loaded
    }

    private static func write(_ commandSets: [CommandSet], to url: URL) throws {
        let data = try CommandSetDocument.encode(commandSets)
        try AppStoragePaths.ensureDirectory(at: url.deletingLastPathComponent())

        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: presenter)

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinatorError {
            throw StoreError.writeFailed(coordinatorError.localizedDescription)
        }

        if let writeError {
            throw StoreError.writeFailed(writeError.localizedDescription)
        }
    }

    private static func activeFileURL() throws -> URL {
        if isCloudSyncEnabled, let cloudURL = iCloudFileURL() {
            return cloudURL
        }

        return localFileURL()
    }

    private static func activeiCloudFileURL() throws -> URL {
        guard let url = iCloudFileURL() else {
            throw StoreError.iCloudUnavailable
        }

        return url
    }

    private static func localFileURL() -> URL {
        if let storageDirectoryOverride {
            return storageDirectoryOverride.appendingPathComponent(AppStoragePaths.commandSetsFileName)
        }

        return AppStoragePaths.localCommandSetsFileURL
    }

    private static func iCloudFileURL() -> URL? {
        guard storageDirectoryOverride == nil else {
            return nil
        
        }
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: AppStoragePaths.iCloudContainerIdentifier
        ) else {
            return nil
        }

        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(AppStoragePaths.commandSetsFileName)
    }

    private static func downloadIfNeeded(_ url: URL) {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        
        guard values?.isUbiquitousItem == true else {
            return
        
        }

        if values?.ubiquitousItemDownloadingStatus != URLUbiquitousItemDownloadingStatus.current {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)

            let deadline = Date().addingTimeInterval(5)


            while Date() < deadline {
                let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
                
                if status == .current {
                    break
                }

                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        }
    }

    private static func migrateLegacyIfNeeded() -> [CommandSet] {
        guard storageDirectoryOverride == nil else {
            return []
        }
        
        let defaults = UserDefaults.standard
        var migrated: [CommandSet] = []

        if let data = defaults.data(forKey: commandSetsKey),
           let commandSets = try? CommandSetDocument.decodeStoredData(data) {
            migrated = commandSets
        } else {
            migrated = decodeLegacyServerCommands()
        }

        defaults.removeObject(forKey: commandSetsKey)
        defaults.removeObject(forKey: legacyServerCommandsKey)

        if let url = try? activeFileURL() {
            try? write(migrated, to: url)
        }

        return migrated
    }

    private static func decodeLegacyServerCommands() -> [CommandSet] {
        guard let data = UserDefaults.standard.data(forKey: legacyServerCommandsKey),
              let legacyCommands = try? JSONDecoder().decode([LegacyServerCommand].self, from: data),
              !legacyCommands.isEmpty else {
            return []
        }

        return legacyCommands.map { legacy in
            CommandSet(
                name: legacy.name.isEmpty ? legacy.serverDetails : legacy.name,
                serverDetails: legacy.serverDetails,
                steps: legacy.steps.isEmpty ? [""] : legacy.steps
            )
        }
    }
}

private final class CommandSetFilePresenter: NSObject, NSFilePresenter {
    let presentedItemOperationQueue = OperationQueue()
    private(set) var presentedItemURL: URL?

    override init() {
        super.init()
        presentedItemOperationQueue.name = "Commando.CommandSetFilePresenter"
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
    }

    func activate(url: URL?) {
        if presentedItemURL != nil {
            NSFileCoordinator.removeFilePresenter(self)
        }

        presentedItemURL = url

        if url != nil {
            NSFileCoordinator.addFilePresenter(self)
        }
    }

    func presentedItemDidChange() {
        CommandStore.handleExternalChange()
    }

    func presentedItemDidMove(to newURL: URL) {
        presentedItemURL = newURL
        CommandStore.handleExternalChange()
    }
}

private struct LegacyServerCommand: Codable {
    var name: String
    var serverDetails: String
    var steps: [String]
}
