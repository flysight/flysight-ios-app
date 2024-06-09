//
//  ContentView.swift
//  FlySight
//
//  Created by Michael Cooper on 2024-04-04.
//

import SwiftUI
import FlySightCore

struct ContentView: View {
    @ObservedObject private var bluetoothManager = FlySightCore.BluetoothManager()

    var body: some View {
        TabView {
            ConnectView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Connect", systemImage: "dot.radiowaves.left.and.right")
                }

            FileExplorerView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Files", systemImage: "folder")
                }

            LiveDataView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Live Data", systemImage: "waveform.path.ecg")
                }

            StartingPistolView(bluetoothManager: bluetoothManager)
                .tabItem {
                    Label("Start Pistol", systemImage: "timer")
                }
        }
    }
}

struct ConnectView: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager

    var body: some View {
        List(bluetoothManager.peripheralInfos) { peripheralInfo in
            HStack {
                VStack(alignment: .leading) {
                    Text(peripheralInfo.name)
                }
                Spacer()
                if bluetoothManager.connectedPeripheral?.id == peripheralInfo.id {
                    Button("Disconnect") {
                        bluetoothManager.disconnect(from: peripheralInfo.peripheral)
                        bluetoothManager.connectedPeripheral = nil
                    }
                    .foregroundColor(.red)
                } else {
                    Button("Connect") {
                        bluetoothManager.connect(to: peripheralInfo.peripheral)
                        bluetoothManager.connectedPeripheral = peripheralInfo
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Sort") {
                    bluetoothManager.sortPeripheralsByRSSI()
                }
            }
        }
    }
}

struct FileExplorerView: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager

    var body: some View {
        NavigationView {
            List {
                ForEach(bluetoothManager.directoryEntries.filter { !$0.isHidden }) { entry in
                    Button(action: {
                        if entry.isFolder {
                            bluetoothManager.changeDirectory(to: entry.name)
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
            bluetoothManager.goUpOneDirectoryLevel()
        }) {
            HStack {
                Image(systemName: "arrow.backward")
                Text("Back")
            }
        }
        .disabled(bluetoothManager.currentPath.count == 0)
    }

    private func currentPathDisplay() -> String {
        bluetoothManager.currentPath.joined(separator: "/")
    }
}

struct LiveDataView: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager

    var body: some View {
        Text("Live Data will be displayed here.")
            .navigationTitle("Live Data")
    }
}

struct StartingPistolView: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager

    @State private var startDate: Date?

    var body: some View {
        VStack {
            if let startDate = startDate {
                Text("Race Started At:")
                Text(dateToString(startDate))
            } else {
                Text("No start time recorded yet.")
            }

            Spacer()

            Button(action: {
                bluetoothManager.sendStartCommand()
            }) {
                Text("Start Race")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
        .onReceive(bluetoothManager.$startResultDate) { date in
            self.startDate = date
        }
        .navigationTitle("Starting Pistol")
    }

    private func dateToString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(abbreviation: "UTC")! // Set timezone to UTC
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
