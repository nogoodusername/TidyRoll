import Foundation

enum FileOrganizerError: Error, LocalizedError {
    case copyFailed(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let reason): return "Copy failed: \(reason)"
        case .verificationFailed(let reason): return "Verification failed: \(reason)"
        }
    }
}

enum FileOrganizer {

    /// Builds destRoot/YY-MM/<City, Country>  (or destRoot/YY-MM when locationFolder is nil).
    static func destinationFolder(root: URL, date: Date, locationFolder: String?) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy-MM"
        let monthFolder = formatter.string(from: date)

        var url = root.appendingPathComponent(monthFolder, isDirectory: true)
        if let locationFolder, !locationFolder.isEmpty {
            url = url.appendingPathComponent(sanitize(locationFolder), isDirectory: true)
        }
        return url
    }

    /// Copies sourceURL into destinationFolder, de-duplicating filenames, then verifies the
    /// copy by comparing file sizes. Returns the final destination file URL.
    static func copyAndVerify(sourceURL: URL, destinationFolder: URL, preferredName: String) throws -> URL {
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let destinationURL = uniqueDestination(folder: destinationFolder, preferredName: preferredName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw FileOrganizerError.copyFailed(error.localizedDescription)
        }

        let sourceSize = try fileSize(sourceURL)
        let destSize = try fileSize(destinationURL)
        guard sourceSize == destSize, sourceSize > 0 else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw FileOrganizerError.verificationFailed("size mismatch (\(sourceSize) vs \(destSize))")
        }

        return destinationURL
    }

    private static func uniqueDestination(folder: URL, preferredName: String) -> URL {
        var candidate = folder.appendingPathComponent(preferredName)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        var counter = 1
        repeat {
            let newName = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            candidate = folder.appendingPathComponent(newName)
            counter += 1
        } while FileManager.default.fileExists(atPath: candidate.path)

        return candidate
    }

    /// Recursively indexes existing files under root as "name|size" keys, for cheap
    /// already-backed-up detection without re-downloading from the device.
    static func buildExistingIndex(root: URL) -> Set<String> {
        var index = Set<String>()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return index
        }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            index.insert(existingIndexKey(name: fileURL.lastPathComponent, size: size))
        }
        return index
    }

    static func existingIndexKey(name: String, size: Int) -> String {
        "\(name.lowercased())|\(size)"
    }

    private static func fileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize ?? 0
    }

    private static func sanitize(_ name: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/:")
        return name.components(separatedBy: disallowed).joined(separator: "-")
    }
}
