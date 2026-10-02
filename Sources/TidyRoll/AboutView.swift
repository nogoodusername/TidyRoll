import SwiftUI
import AppKit

struct AboutView: View {
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)

            Text("TidyRoll")
                .font(.title2.bold())
            Text(versionString)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Backs up iPhone photos to an external drive, organized by date and location.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            Divider()
                .padding(.vertical, 6)

            VStack(spacing: 4) {
                Text("Made by Kshitij Nagvekar")
                    .font(.callout.weight(.medium))
                Link("imhx.top", destination: URL(string: "https://imhx.top")!)
                    .font(.callout)
            }
        }
        .padding(28)
        .frame(width: 280)
    }
}
