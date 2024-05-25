//
//  ContentView.swift
//  FlySight
//
//  Created by Michael Cooper on 2024-04-04.
//

import SwiftUI
import FlySightCore

struct ContentView: View {
    @ObservedObject private var bluetoothViewModel = BluetoothViewModel()

    var body: some View {
        TabView {
            ConnectView(bluetoothViewModel: bluetoothViewModel)
                .tabItem {
                    Label("Connect", systemImage: "dot.radiowaves.left.and.right")
                }

            FileExplorerView(bluetoothViewModel: bluetoothViewModel)
                .tabItem {
                    Label("Files", systemImage: "folder")
                }

            LiveDataView(bluetoothViewModel: bluetoothViewModel)
                .tabItem {
                    Label("Live Data", systemImage: "waveform.path.ecg")
                }

            StartingPistolView(bluetoothViewModel: bluetoothViewModel)
                .tabItem {
                    Label("Start Pistol", systemImage: "timer")
                }
        }
    }
}

struct ConnectView: View {
    @ObservedObject var bluetoothViewModel: BluetoothViewModel

    var body: some View {
        List(bluetoothViewModel.peripheralInfos) { peripheralInfo in
            HStack {
                VStack(alignment: .leading) {
                    Text(peripheralInfo.name)
                }
                Spacer()
                if bluetoothViewModel.connectedPeripheral?.id == peripheralInfo.id {
                    Button("Disconnect") {
                        bluetoothViewModel.disconnect(from: peripheralInfo.peripheral)
                        bluetoothViewModel.connectedPeripheral = nil
                    }
                    .foregroundColor(.red)
                } else {
                    Button("Connect") {
                        bluetoothViewModel.connect(to: peripheralInfo.peripheral)
                        bluetoothViewModel.connectedPeripheral = peripheralInfo
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Sort") {
                    bluetoothViewModel.sortPeripheralsByRSSI()
                }
            }
        }
    }
}

struct FileExplorerView: View {
    @ObservedObject var bluetoothViewModel: BluetoothViewModel

    var body: some View {
        NavigationView {
            List {
                ForEach(bluetoothViewModel.directoryEntries.filter { !$0.isHidden }) { entry in
                    Button(action: {
                        if entry.isFolder {
                            bluetoothViewModel.changeDirectory(to: entry.name)
                        }
                    }) {
                        HStack {
                            Image(systemName: entry.isFolder ? "folder.fill" : "doc")
                            VStack(alignment: .leading) {
                                Text(entry.name)
                                    .font(.headline)
                                    .foregroundColor(entry.isFolder ? .blue : .primary)
                                if !entry.isFolder {
                                    Text("\(entry.size.fileSize())")
                                        .font(.caption)
                                }
                            }
                            Spacer()
                            Text(entry.formattedDate)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Files")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    backButton
                }
                ToolbarItemGroup(placement: .principal) {
                    Text(currentPathDisplay())
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
    }

    private var backButton: some View {
        Button(action: {
            bluetoothViewModel.goUpOneDirectoryLevel()
        }) {
            HStack {
                Image(systemName: "arrow.backward")
                Text("Back")
            }
        }
        .disabled(bluetoothViewModel.currentPath.count == 0)
    }

    private func currentPathDisplay() -> String {
        bluetoothViewModel.currentPath.joined(separator: "/")
    }
}

struct LiveDataView: View {
    @ObservedObject var bluetoothViewModel: BluetoothViewModel

    var body: some View {
        Text("Live Data will be displayed here.")
            .navigationTitle("Live Data")
    }
}

struct StartingPistolView: View {
    @ObservedObject var bluetoothViewModel: BluetoothViewModel

    var body: some View {
        Text("Starting Pistol feature will be controlled here.")
            .navigationTitle("Starting Pistol")
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
