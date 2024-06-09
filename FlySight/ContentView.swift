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

class StartingPistolViewModel: ObservableObject {
    @Published public var recentStartDates: [Date] = []
    private let recentStartDatesKey = "recentStartDates"

    init() {
        loadRecentStartDates()
    }

    private func saveRecentStartDates() {
        let datesData = recentStartDates.map { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(datesData, forKey: recentStartDatesKey)
    }

    private func loadRecentStartDates() {
        if let datesData = UserDefaults.standard.array(forKey: recentStartDatesKey) as? [TimeInterval] {
            recentStartDates = datesData.map { Date(timeIntervalSince1970: $0) }
        }
    }

    func clearRecentStartDates() {
        recentStartDates.removeAll()
        saveRecentStartDates()
    }

    func addNewStartDate(_ date: Date) {
        recentStartDates.append(date)
        saveRecentStartDates()
    }
}

struct StartingPistolView: View {
    @ObservedObject var bluetoothManager: FlySightCore.BluetoothManager
    @StateObject private var viewModel = StartingPistolViewModel()
    @State private var showingClearAlert = false
    @State private var copiedRow: Date?

    var body: some View {
        VStack {
            Text("Recent Start Times")
                .font(.headline)
                .padding(.top)

            if viewModel.recentStartDates.isEmpty {
                Text("No start times recorded yet.")
                    .padding()
            } else {
                List {
                    ForEach(viewModel.recentStartDates.sorted(by: >), id: \.self) { date in
                        HStack {
                            Text(dateToString(date))
                                .font(.system(.body, design: .monospaced))
                                .padding(.vertical, 2)
                            Spacer()
                            Button(action: {
                                UIPasteboard.general.string = dateToString(date)
                                copiedRow = date
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    copiedRow = nil
                                }
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                        .background(copiedRow == date ? Color.green.opacity(0.3) : Color.clear)
                        .animation(.default, value: copiedRow)
                    }
                    .listRowBackground(Color.white)
                }
                .listStyle(PlainListStyle())
                .background(Color(UIColor.systemGray6))
            }

            Spacer()

            HStack {
                Button(action: {
                    bluetoothManager.sendStartCommand()
                }) {
                    Text("Start")
                        .padding()
                        .background(bluetoothManager.state == .idle ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(bluetoothManager.state != .idle)
                .padding(.horizontal)

                Button(action: {
                    bluetoothManager.sendCancelCommand()
                }) {
                    Text("Cancel")
                        .padding()
                        .background(bluetoothManager.state == .counting ? Color.red : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(bluetoothManager.state != .counting)
                .padding(.horizontal)

                Button(action: {
                    showingClearAlert = true
                }) {
                    Text("Clear")
                        .padding()
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .alert(isPresented: $showingClearAlert) {
                    Alert(
                        title: Text("Clear Recent Start Times"),
                        message: Text("Are you sure you want to clear all recent start times?"),
                        primaryButton: .destructive(Text("Clear")) {
                            viewModel.clearRecentStartDates()
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Starting Pistol")
        .onReceive(bluetoothManager.$startResultDate) { date in
            if let date = date {
                viewModel.addNewStartDate(date)
            }
        }
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
