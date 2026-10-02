import Foundation
import ImageCaptureCore

enum BackupStatus: Equatable {
    case pending
    case alreadyBackedUp
    case downloading
    case copied
    case verified
    case failed(String)

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .alreadyBackedUp: return "Already backed up"
        case .downloading: return "Downloading"
        case .copied: return "Copied"
        case .verified: return "Verified"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
}

enum DeleteStatus: Equatable {
    case notRequested
    case deleted
    case failed(String)

    var label: String? {
        switch self {
        case .notRequested: return nil
        case .deleted: return "Deleted from iPhone"
        case .failed(let reason): return "Delete failed: \(reason)"
        }
    }
}

final class BackupItem: Identifiable, ObservableObject {
    let id = UUID()
    let cameraItem: ICCameraItem
    let originalName: String
    @Published var status: BackupStatus = .pending
    @Published var destinationURL: URL?
    @Published var deleteStatus: DeleteStatus = .notRequested

    init(cameraItem: ICCameraItem) {
        self.cameraItem = cameraItem
        self.originalName = cameraItem.name ?? "unknown"
    }
}
