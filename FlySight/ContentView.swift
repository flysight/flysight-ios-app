//
//  ContentView.swift
//  FlySight
//
//  Created by Michael Cooper on 2024-04-04.
//

import SwiftUI
import FlySightCore

struct ContentView: View {
    @ObservedObject var bluetoothManager: BluetoothManager // Use the direct type alias
    @State private var selectedTab: Tab = .connect // Default tab

    // Define an alias for FlySightCore.BluetoothManager for brevity if preferred
    typealias BluetoothManager = FlySightCore.BluetoothManager

    enum Tab: Hashable { // Hashable for TabView selection
        case connect, files, liveData, startPistol, update
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ConnectView(bluetoothManager: bluetoothManager)
                .tabItem { Label("Connect", systemImage: "antenna.radiowaves.left.and.right") } // Updated icon
                .tag(Tab.connect)

            FileExplorerView(bluetoothManager: bluetoothManager)
                .tabItem { Label("Files", systemImage: "folder") }
                .tag(Tab.files)
                .disabled(!isConnected())

            LiveDataView(bluetoothManager: bluetoothManager)
                .tabItem { Label("Live Data", systemImage: "waveform.path.ecg") }
                .tag(Tab.liveData)
                .disabled(!isConnected())

            StartingPistolView(bluetoothManager: bluetoothManager)
                .tabItem { Label("Start Pistol", systemImage: "timer") }
                .tag(Tab.startPistol)
                .disabled(!isConnected())

            UpdateView(bluetoothManager: bluetoothManager)
                .tabItem { Label("Update", systemImage: "arrow.down.circle") }
                .tag(Tab.update)
                .disabled(!isConnected())
        }
        .onReceive(bluetoothManager.$connectionState) { newState in
            handleConnectionStateChange(newState)
        }
        .onAppear {
            // Initial check when the view appears
            handleConnectionStateChange(bluetoothManager.connectionState)
        }
    }

    private func isConnected() -> Bool {
        if case .connected = bluetoothManager.connectionState {
            return true
        }
        return false
    }

    private func handleConnectionStateChange(_ newState: BluetoothManager.ConnectionState) {
        switch newState {
        case .connected:
            // If we just connected and were on the connect tab, or if it's an auto-connect,
            // switch to the files tab.
            if selectedTab == .connect {
                selectedTab = .files
            }
        case .idle, .scanningKnown, .scanningPairing, .connecting, .discoveringServices, .discoveringCharacteristics, .disconnecting:
            // If not fully connected and on a data tab, switch back to connect tab.
            if selectedTab == .files || selectedTab == .liveData || selectedTab == .startPistol || selectedTab == .update {
                if !isConnected() { // Double check, as some states might still imply a valid peripheral exists
                    selectedTab = .connect
                }
            }
        }
    }
}

// Preview needs adjustment if BluetoothManager cannot be simply instantiated
// For preview purposes, you might need a mock BluetoothManager or ensure it can run in preview.
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        // ContentView(bluetoothManager: FlySightCore.BluetoothManager()) // This might be problematic for preview
        // A more robust preview setup would involve a mock manager or specific preview initializers.
        // For now, let's assume the app runs on device/simulator for testing this part.
        Text("ContentView Preview (Run on simulator/device for full functionality)")
    }
}
