import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var controller = BackupController()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    destinationCard
                    deviceCard

                    if controller.statusMessage != nil {
                        statusCard
                    }

                    if controller.phase == .finished {
                        summaryCard
                    }

                    itemsCard
                }
                .padding(20)
            }

            actionBar

            footerLinkBar
        }
        .frame(minWidth: 560, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { controller.start() }
        .alert("Delete \(controller.deletableCount) photo(s) from iPhone?",
               isPresented: $controller.deleteConfirmationPending) {
            Button("Delete from iPhone", role: .destructive) {
                controller.confirmDeletionFromDevice()
            }
            Button("Keep on iPhone", role: .cancel) {
                controller.declineDeletionFromDevice()
            }
        } message: {
            Text("These photos have been copied and verified on your SSD.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { controller.lastErrorMessage != nil },
                set: { if !$0 { controller.lastErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.lastErrorMessage ?? "")
        }
        .alert(
            "Done",
            isPresented: Binding(
                get: { controller.infoMessage != nil },
                set: { if !$0 { controller.infoMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.infoMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("TidyRoll")
                        .font(.title3.bold())
                    Text("iPhone → SSD backup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
            Divider()
        }
    }

    // MARK: - Destination

    private var destinationCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .font(.title2)
                    .foregroundStyle(controller.destinationRoot == nil ? Color.secondary : Color.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Destination")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(controller.destinationRoot?.path ?? "No folder selected")
                        .font(.body.weight(.medium))
                        .foregroundStyle(controller.destinationRoot == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(controller.destinationRoot == nil ? "Choose Folder…" : "Change…") {
                    pickDestination()
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
    }

    // MARK: - Device

    private var deviceCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: controller.deviceManager.deviceName == nil ? "iphone.slash" : "iphone")
                    .font(.title2)
                    .foregroundStyle(controller.deviceManager.deviceName == nil ? Color.secondary : Color.green)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("iPhone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let name = controller.deviceManager.deviceName {
                        HStack(spacing: 6) {
                            Text(name)
                                .font(.body.weight(.medium))
                            if !controller.deviceManager.isCatalogReady {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Not connected")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Scan Photos") {
                    controller.scanDevice()
                }
                .buttonStyle(.bordered)
                .disabled(
                    controller.deviceManager.connectedDevice == nil
                    || !controller.deviceManager.isCatalogReady
                    || isBusy
                )
            }
        }
    }

    // MARK: - Status (loading)

    private var statusCard: some View {
        Card {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(controller.statusMessage ?? "")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if controller.phase == .running, controller.progressTotal > 0 {
                    Text("\(controller.progressCompleted)/\(controller.progressTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if controller.phase == .running, controller.progressTotal > 0 {
                ProgressView(value: Double(controller.progressCompleted), total: Double(controller.progressTotal))
            }
        }
    }

    // MARK: - Summary (success / partial failure)

    private var summaryCard: some View {
        let failed = controller.failedCount
        let verified = controller.verifiedThisSessionCount
        let alreadyBackedUp = controller.alreadyBackedUpCount
        let isSuccess = failed == 0

        return Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(isSuccess ? .green : .orange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isSuccess ? "Backup complete" : "Backup finished with issues")
                        .font(.body.weight(.semibold))
                    Text("\(verified) verified · \(alreadyBackedUp) already backed up · \(failed) failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if failed > 0 {
                    Button("Retry Failed (\(failed))") {
                        controller.retryFailedItems()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }
            }
        }
    }

    // MARK: - Items

    private var isBusy: Bool {
        controller.phase == .scanning || controller.phase == .running || controller.phase == .deleting
    }

    private var itemsCard: some View {
        Card {
            HStack {
                Text("Photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(controller.items.count) item(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if controller.items.isEmpty {
                EmptyStateView(
                    systemImage: "photo.on.rectangle.angled",
                    title: "No photos scanned yet",
                    subtitle: "Connect your iPhone and tap Scan Photos to get started."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(controller.items) { item in
                        itemRow(item)
                        if item.id != controller.items.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: BackupItem) -> some View {
        HStack {
            Text(item.originalName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(text: item.status.label, systemImage: item.status.icon, tint: item.status.tint)
                if let deleteLabel = item.deleteStatus.label {
                    StatusPill(text: deleteLabel, systemImage: item.deleteStatus.icon, tint: item.deleteStatus.tint)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                if !controller.deletableItems.isEmpty {
                    Button("Delete Backed-Up Photos (\(controller.deletableCount))") {
                        controller.requestDeleteConfirmation()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }
                Button("Start Backup") {
                    controller.startBackup()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    controller.items.isEmpty
                    || controller.destinationRoot == nil
                    || isBusy
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private var footerLinkBar: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 4) {
                Text("TidyRoll v\(version)")
                Text("· Made by Kshitij Nagvekar ·")
                Link("imhx.top", destination: URL(string: "https://imhx.top")!)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            controller.chooseDestinationRoot(url)
        }
    }
}
