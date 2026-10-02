import Foundation
import ImageCaptureCore

final class DeviceManager: NSObject, ObservableObject {
    @Published var connectedDevice: ICCameraDevice?
    @Published var isCatalogReady = false
    @Published var deviceName: String?

    private let browser = ICDeviceBrowser()

    override init() {
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
    }

    func start() {
        browser.start()
    }

    func stop() {
        browser.stop()
    }

    /// All image/video files currently on the connected device.
    var mediaFiles: [ICCameraFile] {
        (connectedDevice?.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
    }

    func downloadFile(
        _ file: ICCameraFile,
        to directory: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: directory,
            .saveAsFilename: file.name ?? UUID().uuidString,
            .overwrite: true
        ]
        _ = file.requestDownload(options: options) { filename, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let filename else {
                completion(.failure(NSError(domain: "TidyRoll", code: -1, userInfo: [NSLocalizedDescriptionKey: "No filename returned from download"])))
                return
            }
            completion(.success(directory.appendingPathComponent(filename)))
        }
    }

    struct DeleteOutcome {
        let succeeded: [ICCameraItem]
        let failed: [ICCameraItem]
    }

    func deleteFiles(_ files: [ICCameraItem], completion: @escaping (Result<DeleteOutcome, Error>) -> Void) {
        guard let device = connectedDevice else {
            completion(.failure(NSError(domain: "TidyRoll", code: -2, userInfo: [NSLocalizedDescriptionKey: "No connected device"])))
            return
        }
        _ = device.requestDeleteFiles(files, deleteFailed: { _ in
            // Per-file failures are reflected in the completion's result dictionary below.
        }, completion: { result, error in
            if let error {
                completion(.failure(error))
                return
            }
            let succeeded = result[.successful] ?? []
            let failed = result[.failed] ?? []
            completion(.success(DeleteOutcome(succeeded: succeeded, failed: failed)))
        })
    }
}

extension DeviceManager: ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        DispatchQueue.main.async {
            self.connectedDevice = camera
            self.deviceName = camera.name
        }
        camera.delegate = self
        camera.requestOpenSession()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        guard device === connectedDevice else { return }
        DispatchQueue.main.async {
            self.connectedDevice = nil
            self.isCatalogReady = false
            self.deviceName = nil
        }
    }
}

extension DeviceManager: ICDeviceDelegate {
    func didRemove(_ device: ICDevice) {
        guard device === connectedDevice else { return }
        DispatchQueue.main.async {
            self.connectedDevice = nil
            self.isCatalogReady = false
            self.deviceName = nil
        }
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {}

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
}

extension DeviceManager: ICCameraDeviceDelegate {
    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        DispatchQueue.main.async {
            self.isCatalogReady = true
        }
    }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}

    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}

    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
}
