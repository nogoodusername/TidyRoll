import Foundation
import CoreLocation

actor LocationResolver {
    static let shared = LocationResolver()

    private let geocoder = CLGeocoder()
    private var cache: [String: String?] = [:]

    /// Returns "City, Country" (or "State, Country" if city unavailable), or nil if it cannot be resolved.
    func resolveFolderName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let key = cacheKey(for: coordinate)
        if let cached = cache[key] {
            return cached
        }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var result: String?
        if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
           let placemark = placemarks.first {
            let place = placemark.locality ?? placemark.administrativeArea
            if let place, let country = placemark.country {
                result = "\(place), \(country)"
            } else if let country = placemark.country {
                result = country
            }
        }

        cache[key] = result
        return result
    }

    /// Round to ~1.1km precision so nearby photos share one geocode lookup.
    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude * 100).rounded() / 100
        let lon = (coordinate.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
    }
}
