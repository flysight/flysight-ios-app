//
//  UpdateView.swift
//  FlySight
//
//  Created by Codex on 2026-05-14.
//

import SwiftUI
import FlySightCore
import FlySightFirmware

struct UpdateView: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager
    @StateObject private var viewModel: FirmwareUpdateViewModel
    @State private var showingInstallConfirmation = false

    init(bluetoothManager: FlySightCore.BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        _viewModel = StateObject(wrappedValue: FirmwareUpdateViewModel(bluetoothManager: bluetoothManager))
    }

    var body: some View {
        NavigationView {
            Group {
                if isConnected {
                    updateForm
                } else {
                    notConnectedView
                }
            }
            .navigationTitle("Firmware Update")
            .onReceive(bluetoothManager.$connectionState) { state in
                if !isConnected(state) {
                    viewModel.resetAfterDisconnect()
                }
            }
            .alert(isPresented: $showingInstallConfirmation) {
                installConfirmationAlert()
            }
        }
    }

    private var updateForm: some View {
        Form {
            deviceSection
            optionsSection

            if let selectedFirmware = viewModel.selectedFirmware {
                selectedFirmwareSection(selectedFirmware)
            }

            progressSection
        }
    }

    private var deviceSection: some View {
        Section(header: Text("Device")) {
            if let device = viewModel.manifest?.device {
                InfoRow(label: "Firmware", value: device.firmwareVersion)
                InfoRow(label: "Stack", value: device.stackVersionUnknown ? "Unknown" : device.stackVersion)
                InfoRow(label: "Batch", value: device.legacy ? "Legacy" : shortPubkey(device.pubkeyX))
            } else {
                InfoRow(label: "Firmware", value: bluetoothManager.flysightFirmwareVersion ?? "Not checked")
            }
        }
    }

    private var optionsSection: some View {
        Section(header: Text("Options")) {
            Toggle("Include Beta", isOn: $viewModel.includeBeta)
                .disabled(viewModel.isBusy)

            Button(action: viewModel.refreshManifest) {
                HStack {
                    if case .readingStateFile = viewModel.state {
                        ProgressView()
                    } else if case .fetchingManifest = viewModel.state {
                        ProgressView()
                    }
                    Text(viewModel.actionTitle)
                }
            }
            .disabled(viewModel.isBusy)

            if !viewModel.firmwareOptions.isEmpty {
                Picker("Version", selection: selectedVersionBinding) {
                    ForEach(viewModel.firmwareOptions, id: \.version) { firmware in
                        Text(versionLabel(firmware))
                            .tag(firmware.version)
                    }
                }
                .disabled(viewModel.isBusy)
            }
        }
    }

    private func selectedFirmwareSection(_ firmware: FirmwareOption) -> some View {
        Section(header: Text("Selected Firmware")) {
            InfoRow(label: "Version", value: firmware.version)
            InfoRow(label: "Release Date", value: firmware.releaseDate)
            InfoRow(label: "Type", value: firmware.isBeta ? "Beta" : "Release")

            if firmware.version == viewModel.manifest?.recommended.version {
                Label("Recommended", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
            }

            if firmware.stack.updateRequired {
                InfoRow(label: "Stack Update", value: firmware.stack.requiredVersion)
            } else {
                InfoRow(label: "Stack Update", value: "Not required")
            }

            Button(action: {
                showingInstallConfirmation = true
            }) {
                Label("Install Selected Firmware", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.isBusy)
        }
    }

    private var progressSection: some View {
        Section(header: Text("Progress")) {
            HStack {
                statusIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.progressTitle)
                        .font(.headline)
                    Text(viewModel.progressDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)

            if isUploading {
                ProgressView(value: Double(viewModel.uploadProgress), total: 1.0)
                Text(String(format: "%.0f%%", viewModel.uploadProgress * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if viewModel.isBusy {
                ProgressView()
            }

            if viewModel.canCancelCurrentStep {
                Button(action: viewModel.cancelCurrentStep) {
                    Label("Cancel Upload", systemImage: "xmark.circle")
                }
                .foregroundColor(.red)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }
        }
    }

    private var notConnectedView: some View {
        VStack {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 50))
                .foregroundColor(.gray)
                .padding(.bottom)
            Text("Not Connected")
                .font(.headline)
            Text("Connect to a FlySight to check for firmware updates.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }

    private var selectedVersionBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedVersion },
            set: { viewModel.selectFirmware(version: $0) }
        )
    }

    private var statusIcon: some View {
        switch viewModel.state {
        case .completed:
            return Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            return Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
        case .idle, .ready:
            return Image(systemName: "arrow.down.circle").foregroundColor(.blue)
        default:
            return Image(systemName: "clock").foregroundColor(.orange)
        }
    }

    private var isConnected: Bool {
        isConnected(bluetoothManager.connectionState)
    }

    private var isUploading: Bool {
        switch viewModel.state {
        case .uploadingStack, .uploadingFirmware:
            return true
        default:
            return false
        }
    }

    private func isConnected(_ state: FlySightCore.BluetoothManager.ConnectionState) -> Bool {
        if case .connected = state {
            return true
        }
        return false
    }

    private func versionLabel(_ firmware: FirmwareOption) -> String {
        var parts = [firmware.version]
        if firmware.version == viewModel.manifest?.recommended.version {
            parts.append("recommended")
        }
        if firmware.isBeta {
            parts.append("beta")
        }
        return parts.joined(separator: " - ")
    }

    private func shortPubkey(_ pubkey: String) -> String {
        guard pubkey.count > 12 else { return pubkey }
        return "\(pubkey.prefix(6))...\(pubkey.suffix(6))"
    }

    private func installConfirmationAlert() -> Alert {
        let version = viewModel.selectedFirmware?.version ?? "selected firmware"
        return Alert(
            title: Text("Install \(version)?"),
            message: Text("The firmware will be uploaded, then the FlySight will reset to start installation."),
            primaryButton: .default(Text("Install")) {
                viewModel.installSelectedFirmware()
            },
            secondaryButton: .cancel()
        )
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct UpdateView_Previews: PreviewProvider {
    static var previews: some View {
        UpdateView(bluetoothManager: FlySightCore.BluetoothManager())
    }
}
