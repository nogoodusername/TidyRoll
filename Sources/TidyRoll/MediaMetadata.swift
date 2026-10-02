import Foundation
import ImageIO
import AVFoundation
import CoreLocation

struct MediaMetadata {
    let captureDate: Date
    let coordinate: CLLocationCoordinate2D?
}

enum MediaMetadataReader {

    static func read(fileURL: URL) -> MediaMetadata {
        if let imageMeta = readImageMetadata(fileURL: fileURL) {
            return imageMeta
        }
        if let videoMeta = readVideoMetadata(fileURL: fileURL) {
            return videoMeta
        }
        let fallbackDate = fileDate(fileURL: fileURL)
        return MediaMetadata(captureDate: fallbackDate, coordinate: nil)
    }

    private static func readImageMetadata(fileURL: URL) -> MediaMetadata? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }

        var date: Date?
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            date = parseExifDate(dateString)
        }
        if date == nil, let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let dateString = tiff[kCGImagePropertyTIFFDateTime] as? String {
            date = parseExifDate(dateString)
        }

        var coordinate: CLLocationCoordinate2D?
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            coordinate = gpsCoordinate(from: gps)
        }

        guard let resolvedDate = date else {
            return coordinate != nil ? MediaMetadata(captureDate: fileDate(fileURL: fileURL), coordinate: coordinate) : nil
        }
        return MediaMetadata(captureDate: resolvedDate, coordinate: coordinate)
    }

    private static func readVideoMetadata(fileURL: URL) -> MediaMetadata? {
        let ext = fileURL.pathExtension.lowercased()
        guard ["mov", "mp4", "m4v"].contains(ext) else { return nil }

        let asset = AVURLAsset(url: fileURL)
        var coordinate: CLLocationCoordinate2D?
        var date: Date?

        for item in asset.commonMetadata {
            if item.commonKey == .commonKeyLocation, let stringValue = item.stringValue {
                coordinate = parseISO6709(stringValue)
            }
            if item.commonKey == .commonKeyCreationDate {
                if let dateValue = item.dateValue {
                    date = dateValue
                } else if let stringValue = item.stringValue {
                    date = ISO8601DateFormatter().date(from: stringValue)
                }
            }
        }

        let resolvedDate = date ?? fileDate(fileURL: fileURL)
        return MediaMetadata(captureDate: resolvedDate, coordinate: coordinate)
    }

    private static func fileDate(fileURL: URL) -> Date {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? Date()
    }

    private static func parseExifDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }

    private static func gpsCoordinate(from gps: [CFString: Any]) -> CLLocationCoordinate2D? {
        guard let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
              let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
        else {
            return nil
        }
        let signedLat = latRef.uppercased() == "S" ? -lat : lat
        let signedLon = lonRef.uppercased() == "W" ? -lon : lon
        return CLLocationCoordinate2D(latitude: signedLat, longitude: signedLon)
    }

    // ISO 6709 format e.g. "+37.3318-122.0312+000.000/"
    private static func parseISO6709(_ string: String) -> CLLocationCoordinate2D? {
        let pattern = #"^([+-][0-9.]+)([+-][0-9.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let latRange = Range(match.range(at: 1), in: string),
              let lonRange = Range(match.range(at: 2), in: string),
              let lat = Double(string[latRange]),
              let lon = Double(string[lonRange])
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
