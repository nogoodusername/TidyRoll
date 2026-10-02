import Foundation
import Combine
import ImageCaptureCore

enum BackupPhase: Equatable {
    case idle
    case scanning
    case running
    case finished
    case deleting
}

@MainActor
final class BackupController: ObservableObject {
    @Published var destinationRoot: URL?
    @Published var items: [BackupItem] = []
    @Published var phase: BackupPhase = .idle
    @Published var deleteConfirmationPending = false
    @Published var lastErrorMessage: String?
    @Published var infoMessage: String?
    @Published var statusMessage: String?
    @Published var progressCompleted: Int = 0
    @Published var progressTotal: Int = 0

    let deviceManager = DeviceManager()
    private var cancellables = Set<AnyCancellable>()
    private var backupTask: Task<Void, Never>?

    private let tempDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyRoll-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var deletableItems: [BackupItem] {
        items.filter { ($0.status == .verified || $0.status == .alreadyBackedUp) && $0.deleteStatus != .deleted }
    }

    var deletableCount: Int {
        deletableItems.count
    }

    init() {
        // DeviceManager is its own ObservableObject nested inside this one; forward its
        // change notifications so SwiftUI views observing `controller` also react to
        // device connect/disconnect without needing a separate @ObservedObject.
        deviceManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        deviceManager.$connectedDevice
            .removeDuplicates { lhs, rhs in
                switch (lhs, rhs) {
                case (nil, nil): return true
                case let (l?, r?): return l === r
                default: return false
                }
            }
            .dropFirst() // ignore the initial nil emission at launch
            .sink { [weak self] device in
                if device == nil {
                    self?.handleDeviceDisconnected()
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        deviceManager.start()
    }

    func chooseDestinationRoot(_ url: URL) {
        destinationRoot = url
    }

    func scanDevice() {
        guard deviceManager.connectedDevice != nil else { return }
        phase = .scanning
        statusMessage = "Reading photo library from iPhone…"
        let files = deviceManager.mediaFiles
        let root = destinationRoot

        Task {
            if root != nil {
                statusMessage = "Checking \(files.count) photo(s) against your destination folder…"
            }

            let existingIndex: Set<String>
            if let root {
                existingIndex = await Task.detached(priority: .userInitiated) {
                    FileOrganizer.buildExistingIndex(root: root)
                }.value
            } else {
                existingIndex = []
            }

            items = files.map { file in
                let item = BackupItem(cameraItem: file)
                let key = FileOrganizer.existingIndexKey(name: file.name ?? "", size: Int(file.fileSize))
                if existingIndex.contains(key) {
                    item.status = .alreadyBackedUp
                }
                return item
            }
            statusMessage = nil
            phase = .idle
        }
    }

    var failedCount: Int {
        items.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    var alreadyBackedUpCount: Int {
        items.filter { $0.status == .alreadyBackedUp }.count
    }

    var verifiedThisSessionCount: Int {
        items.filter { $0.status == .verified }.count
    }

    func startBackup() {
        let itemsToBackup = items.filter { $0.status != .alreadyBackedUp }
        run(itemsToBackup, actionVerb: "Backing up")
    }

    func retryFailedItems() {
        let failedItems = items.filter {
            if case .failed = $0.status { return true }
            return false
        }
        for item in failedItems { item.status = .pending }
        run(failedItems, actionVerb: "Retrying")
    }

    private func run(_ itemsToProcess: [BackupItem], actionVerb: String) {
        guard let destinationRoot else {
            lastErrorMessage = "Pick a destination folder on your SSD first."
            return
        }
        guard deviceManager.connectedDevice != nil else {
            lastErrorMessage = "iPhone is not connected."
            return
        }
        guard !itemsToProcess.isEmpty else { return }

        phase = .running
        progressCompleted = 0
        progressTotal = itemsToProcess.count

        backupTask = Task {
            for item in itemsToProcess {
                guard !Task.isCancelled else { return }
                statusMessage = "\(actionVerb) \(progressCompleted + 1) of \(progressTotal): \(item.originalName)"
                await backup(item: item, into: destinationRoot)
                progressCompleted += 1
            }
            guard !Task.isCancelled else { return }
            statusMessage = nil
            phase = .finished
            if !deletableItems.isEmpty {
                deleteConfirmationPending = true
            }
        }
    }

    func requestDeleteConfirmation() {
        guard !deletableItems.isEmpty else { return }
        deleteConfirmationPending = true
    }

    func confirmDeletionFromDevice() {
        let eligibleItems = deletableItems
        let cameraItems = eligibleItems.map { $0.cameraItem }
        deleteConfirmationPending = false
        guard !cameraItems.isEmpty else { return }

        phase = .deleting
        statusMessage = "Deleting \(cameraItems.count) photo(s) from iPhone…"

        deviceManager.deleteFiles(cameraItems) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.statusMessage = nil
                self.phase = .idle

                switch result {
                case .failure(let error):
                    self.lastErrorMessage = "Delete failed: \(error.localizedDescription)"
                    for item in eligibleItems {
                        item.deleteStatus = .failed(error.localizedDescription)
                    }
                case .success(let outcome):
                    for item in eligibleItems {
                        if outcome.succeeded.contains(where: { $0 === item.cameraItem }) {
                            item.deleteStatus = .deleted
                        } else if outcome.failed.contains(where: { $0 === item.cameraItem }) {
                            item.deleteStatus = .failed("Device reported failure")
                        }
                    }
                    if outcome.failed.isEmpty {
                        self.infoMessage = "Deleted \(outcome.succeeded.count) photo(s) from iPhone."
                    } else {
                        self.infoMessage = "Deleted \(outcome.succeeded.count) photo(s); \(outcome.failed.count) could not be deleted."
                    }
                }
            }
        }
    }

    func declineDeletionFromDevice() {
        deleteConfirmationPending = false
    }

    private func handleDeviceDisconnected() {
        guard phase == .running else { return }
        backupTask?.cancel()
        backupTask = nil
        for item in items where item.status == .pending || item.status == .downloading {
            item.status = .failed("iPhone disconnected")
        }
        statusMessage = nil
        phase = .finished
        lastErrorMessage = "iPhone disconnected during backup."
    }

    private func backup(item: BackupItem, into destinationRoot: URL) async {
        guard let cameraFile = item.cameraItem as? ICCameraFile else {
            item.status = .failed("Not a downloadable file")
            return
        }

        item.status = .downloading

        let downloadedURL: URL
        do {
            downloadedURL = try await download(cameraFile)
        } catch {
            item.status = .failed(error.localizedDescription)
            return
        }

        let originalName = item.originalName
        let outcome: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let metadata = MediaMetadataReader.read(fileURL: downloadedURL)
                var locationFolder: String?
                if let coordinate = metadata.coordinate {
                    locationFolder = await LocationResolver.shared.resolveFolderName(for: coordinate)
                }
                let destinationFolder = FileOrganizer.destinationFolder(
                    root: destinationRoot,
                    date: metadata.captureDate,
                    locationFolder: locationFolder
                )
                let finalURL = try FileOrganizer.copyAndVerify(
                    sourceURL: downloadedURL,
                    destinationFolder: destinationFolder,
                    preferredName: originalName
                )
                return .success(finalURL)
            } catch {
                return .failure(error)
            }
        }.value

        switch outcome {
        case .success(let finalURL):
            item.destinationURL = finalURL
            item.status = .verified
        case .failure(let error):
            item.status = .failed(error.localizedDescription)
        }

        try? FileManager.default.removeItem(at: downloadedURL)
    }

    private func download(_ file: ICCameraFile, timeout: Duration = .seconds(90)) async throws -> URL {
        let deviceManager = deviceManager
        let tempDirectory = tempDirectory
        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    deviceManager.downloadFile(file, to: tempDirectory) { result in
                        continuation.resume(with: result)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BackupError.downloadTimedOut
            }

            do {
                let result = try await group.next()!
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                deviceManager.connectedDevice?.cancelDownload()
                throw error
            }
        }
    }
}

enum BackupError: LocalizedError {
    case downloadTimedOut

    var errorDescription: String? {
        switch self {
        case .downloadTimedOut:
            return "Download timed out after 90s (the photo may be iCloud-only and not fully downloaded on the iPhone)"
        }
    }
}
