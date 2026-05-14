//
//  FirmwareUpdateViewModel.swift
//  FlySight
//
//  Created by Codex on 2026-05-14.
//

import Foundation
import FlySightCore
import FlySightFirmware

@MainActor
final class FirmwareUpdateViewModel: ObservableObject {
    @Published var includeBeta = false
    @Published private(set) var manifest: FirmwareManifest?
    @Published private(set) var selectedFirmware: FirmwareOption?
    @Published private(set) var state: FirmwareUpdateState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var completedResult: FirmwareUpdateResult?
    @Published private(set) var isPreparingIdleMode = false

    private let bluetoothManager: FlySightCore.BluetoothManager
    private var coordinator: FirmwareUpdateCoordinator!
    private var activeTask: Task<Void, Never>?

    init(bluetoothManager: FlySightCore.BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        self.coordinator = makeCoordinator()
    }

    var firmwareOptions: [FirmwareOption] {
        manifest?.firmwares ?? []
    }

    var selectedVersion: String {
        selectedFirmware?.version ?? ""
    }

    var isBusy: Bool {
        if isPreparingIdleMode {
            return true
        }

        switch state {
        case .readingStateFile, .fetchingManifest, .downloadingStack, .downloadingFirmware,
             .creatingFirmwareDirectory, .uploadingStack, .uploadingFirmware,
             .verifyingStack, .verifyingFirmware, .requestingInstall:
            return true
        default:
            return false
        }
    }

    var canCancelCurrentStep: Bool {
        switch state {
        case .uploadingStack, .uploadingFirmware:
            return true
        default:
            return false
        }
    }

    var actionTitle: String {
        if isPreparingIdleMode {
            return "Switching to Idle"
        }

        switch state {
        case .idle:
            return "Check for Updates"
        case .ready, .failed, .completed:
            return "Refresh"
        default:
            return "Working..."
        }
    }

    var progressTitle: String {
        if isPreparingIdleMode {
            return "Switching to Idle"
        }

        switch state {
        case .idle:
            return "Ready"
        case .readingStateFile:
            return "Reading FLYSIGHT.TXT"
        case .fetchingManifest:
            return "Checking Firmware"
        case .ready:
            return "Ready to Install"
        case .downloadingStack:
            return "Downloading Stack"
        case .downloadingFirmware:
            return "Downloading Firmware"
        case .creatingFirmwareDirectory:
            return "Preparing FlySight"
        case .uploadingStack:
            return "Uploading Stack"
        case .uploadingFirmware:
            return "Uploading Firmware"
        case .verifyingStack:
            return "Verifying Stack"
        case .verifyingFirmware:
            return "Verifying Firmware"
        case .requestingInstall:
            return "Requesting Install"
        case .completed:
            return "Install Started"
        case .failed:
            return "Update Failed"
        }
    }

    var progressDetail: String {
        if isPreparingIdleMode {
            return "Requesting idle mode so firmware files can be read and written safely."
        }

        switch state {
        case .idle:
            return "Connect to a FlySight and check for compatible firmware."
        case .readingStateFile:
            return "Reading device identity from the root of the FlySight."
        case .fetchingManifest(let includeBeta):
            return includeBeta ? "Requesting release and beta firmware options." : "Requesting release firmware options."
        case .ready(_, let selectedFirmware):
            return "\(selectedFirmware.version) is selected."
        case .downloadingStack(let file), .uploadingStack(let file):
            return file.targetPath
        case .downloadingFirmware(let file), .uploadingFirmware(let file):
            return file.targetPath
        case .verifyingStack(let file), .verifyingFirmware(let file):
            return "Reading back \(file.targetPath) and checking SHA-256."
        case .creatingFirmwareDirectory:
            return "Creating or reusing the FW folder."
        case .requestingInstall:
            return "The FlySight may disconnect and reset."
        case .completed(let result):
            return "\(result.firmwareVersion) was uploaded and install was requested."
        case .failed(let message):
            return message
        }
    }

    var uploadProgress: Float {
        bluetoothManager.uploadProgress
    }

    var downloadProgress: Float {
        bluetoothManager.downloadProgress
    }

    func readDeviceModeForFirmwareUpdate() async -> FlySightCore.DeviceMode? {
        guard !isBusy else { return nil }

        completedResult = nil
        errorMessage = nil

        do {
            return try await bluetoothManager.readDeviceMode()
        } catch {
            let message = displayMessage(for: error)
            errorMessage = message
            state = .failed(message: message)
            return nil
        }
    }

    func ensureIdleModeForFirmwareUpdate() async -> Bool {
        guard !isBusy else { return false }

        completedResult = nil
        errorMessage = nil
        isPreparingIdleMode = true
        defer { isPreparingIdleMode = false }

        do {
            try await bluetoothManager.ensureIdleModeForFirmwareUpdate()
            return true
        } catch {
            let message = displayMessage(for: error)
            errorMessage = message
            state = .failed(message: message)
            return false
        }
    }

    func refreshManifest() {
        guard !isBusy else { return }
        resetForNewOperation()
        coordinator = makeCoordinator()
        activeTask = Task {
            do {
                let loadedManifest = try await coordinator.loadManifest(includeBeta: includeBeta)
                manifest = loadedManifest
                selectedFirmware = loadedManifest.recommended
            } catch {
                errorMessage = displayMessage(for: error)
            }
            activeTask = nil
        }
    }

    func selectFirmware(version: String) {
        guard !isBusy else { return }

        do {
            selectedFirmware = try coordinator.selectFirmware(version: version)
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func installSelectedFirmware() {
        guard !isBusy else { return }
        guard selectedFirmware != nil else {
            errorMessage = "Choose a firmware version first."
            return
        }

        completedResult = nil
        errorMessage = nil
        activeTask = Task {
            do {
                completedResult = try await coordinator.installSelectedFirmware()
            } catch {
                errorMessage = displayMessage(for: error)
            }
            activeTask = nil
        }
    }

    func cancelCurrentStep() {
        guard canCancelCurrentStep else { return }
        bluetoothManager.cancelUpload()
        activeTask?.cancel()
    }

    func resetAfterDisconnect() {
        activeTask?.cancel()
        activeTask = nil
        coordinator = makeCoordinator()
        manifest = nil
        selectedFirmware = nil
        completedResult = nil
        errorMessage = nil
        isPreparingIdleMode = false
        state = .idle
    }

    private func makeCoordinator() -> FirmwareUpdateCoordinator {
        FirmwareUpdateCoordinator(bleTransport: bluetoothManager) { [weak self] newState in
            Task { @MainActor in
                self?.apply(newState)
            }
        }
    }

    private func apply(_ newState: FirmwareUpdateState) {
        state = newState

        switch newState {
        case .ready(let manifest, let selectedFirmware):
            self.manifest = manifest
            self.selectedFirmware = selectedFirmware
            errorMessage = nil
        case .completed(let result):
            completedResult = result
            errorMessage = nil
        case .failed(let message):
            errorMessage = message
        default:
            break
        }
    }

    private func resetForNewOperation() {
        activeTask?.cancel()
        activeTask = nil
        manifest = nil
        selectedFirmware = nil
        completedResult = nil
        errorMessage = nil
        isPreparingIdleMode = false
        state = .idle
    }

    private func displayMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}
