//
//  ContentView.swift
//  FlySight
//
//  Created by Michael Cooper on 2024-04-04.
//

import SwiftUI
import CoreBluetooth
import Foundation

// Define a structure to hold peripheral information
struct PeripheralInfo: Identifiable {
    let peripheral: CBPeripheral
    var rssi: Int
    var name: String {
        peripheral.name ?? "Unnamed Device"
    }
    var id: UUID {
        peripheral.identifier
    }
}

struct DirectoryEntry: Identifiable {
    let id = UUID()
    let size: UInt32
    let date: Date
    let attributes: String
    let name: String

    var isFolder: Bool {
        attributes.contains("d")
    }

    var isHidden: Bool {
        attributes.contains("h")
    }

    // Helper to format the date
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

class BluetoothViewModel: NSObject, ObservableObject {
    private var centralManager: CBCentralManager?
    
    @Published var peripheralInfos: [PeripheralInfo] = []
    
    let CRS_RX_UUID = CBUUID(string: "00000002-8e22-4541-9d4c-21edae82ed19")
    let CRS_TX_UUID = CBUUID(string: "00000001-8e22-4541-9d4c-21edae82ed19")
    
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    
    @Published var directoryEntries: [DirectoryEntry] = []
    
    @Published var connectedPeripheral: PeripheralInfo?

    @Published var currentPath: [String] = []  // Start with the root directory

    @Published var isAwaitingResponse = false

    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    func sortPeripheralsByRSSI() {
        DispatchQueue.main.async {
            self.peripheralInfos.sort { $0.rssi > $1.rssi }
        }
    }
    
    func connect(to peripheral: CBPeripheral) {
        centralManager?.connect(peripheral, options: nil)
    }
    
    func disconnect(from peripheral: CBPeripheral) {
        centralManager?.cancelPeripheralConnection(peripheral)
    }
    
    func parseDirectoryEntry(from data: Data) -> DirectoryEntry? {
        guard data.count == 24 else { return nil } // Ensure data length is as expected

        let size: UInt32 = data.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: UInt32.self) }
        let fdate: UInt16 = data.subdata(in: 6..<8).withUnsafeBytes { $0.load(as: UInt16.self) }
        let ftime: UInt16 = data.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self) }
        let fattrib: UInt8 = data.subdata(in: 10..<11).withUnsafeBytes { $0.load(as: UInt8.self) }

        let nameData = data.subdata(in: 11..<24) // Assuming the rest is the name
        let nameDataNullTerminated = nameData.split(separator: 0, maxSplits: 1, omittingEmptySubsequences: false).first ?? Data() // Split at the first null byte
        guard let name = String(data: nameDataNullTerminated, encoding: .utf8), !name.isEmpty else { return nil } // Check for empty name

        // Decode date and time
        let year = Int((fdate >> 9) & 0x7F) + 1980
        let month = Int((fdate >> 5) & 0x0F)
        let day = Int(fdate & 0x1F)
        let hour = Int((ftime >> 11) & 0x1F)
        let minute = Int((ftime >> 5) & 0x3F)
        let second = Int((ftime & 0x1F) * 2) // Multiply by 2 to get the actual seconds

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)) else { return nil }

        // Decode attributes
        let attributesOrder = ["r", "h", "s", "a", "d"]
        let attribText = attributesOrder.enumerated().map { index, letter in
            (fattrib & (1 << index)) != 0 ? letter : "-"
        }.joined()

        return DirectoryEntry(size: size, date: date, attributes: attribText, name: name)
    }

    func changeDirectory(to newDirectory: String) {
        guard !isAwaitingResponse else { return }

        // Append new directory to the path
        currentPath.append(newDirectory)
        loadDirectoryEntries()
    }

    func goUpOneDirectoryLevel() {
        guard !isAwaitingResponse else { return }

        // Remove the last directory in the path
        if currentPath.count > 0 {
            currentPath.removeLast()
            loadDirectoryEntries()
        }
    }

    private func loadDirectoryEntries() {
        // Reset the directory listings
        directoryEntries = []

        // Set waiting flag
        isAwaitingResponse = true

        if let peripheral = connectedPeripheral?.peripheral, let rx = rxCharacteristic {
            let directory = ([""] + currentPath).joined(separator: "/")
            let directoryCommand = Data([0x05]) + directory.data(using: .utf8)!
            peripheral.writeValue(directoryCommand, for: rx, type: .withoutResponse)
        }
    }
}

extension BluetoothViewModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            self.centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        DispatchQueue.main.async {
            if let index = self.peripheralInfos.firstIndex(where: { $0.peripheral.identifier == peripheral.identifier }) {
                // Update existing peripheral info with new RSSI
                self.peripheralInfos[index].rssi = RSSI.intValue
            } else {
                // Add new peripheral info
                let newPeripheralInfo = PeripheralInfo(peripheral: peripheral, rssi: RSSI.intValue)
                self.peripheralInfos.append(newPeripheralInfo)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "Unknown Device") (peripheral ID = \(peripheral.identifier))")

        // Set this object as the delegate for the peripheral to receive peripheral delegate callbacks.
        peripheral.delegate = self

        // Optionally start discovering services or characteristics here
        peripheral.discoverServices(nil)  // Passing nil will discover all services
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "Unknown Device") (peripheral ID = \(peripheral.identifier))")

        // Reset the characteristic references
        rxCharacteristic = nil
        txCharacteristic = nil

        // Initialize current path
        currentPath = []

        // Reset the directory listings
        directoryEntries = []

        // Optionally: Handle any UI updates or perform cleanup after disconnection
        // This might involve updating published properties or notifying the user
    }
}

extension BluetoothViewModel: CBPeripheralDelegate {
    // Assuming CRS_TX_UUID is the characteristic where directory listing data will be notified
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            isAwaitingResponse = false
            print("Error reading characteristic: \(error?.localizedDescription ?? "Unknown error")")
            return
        }

        if characteristic.uuid == CRS_TX_UUID {
            DispatchQueue.main.async {
                if let directoryEntry = self.parseDirectoryEntry(from: data) {
                    self.directoryEntries.append(directoryEntry)
                    // Sort after adding new entry
                    self.sortDirectoryEntries()
                }
                self.isAwaitingResponse = false // Unlock after processing
            }
        }
    }

    func sortDirectoryEntries() {
        directoryEntries.sort {
            if $0.isFolder != $1.isFolder {
                return $0.isFolder && !$1.isFolder
            }
            return $0.name.lowercased() < $1.name.lowercased()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            print("Error discovering characteristics: \(error!.localizedDescription)")
            return
        }

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == CRS_TX_UUID {
                    txCharacteristic = characteristic
                    
                    // Subscribe to this characteristic's notifications
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.uuid == CRS_RX_UUID {
                    rxCharacteristic = characteristic
                }
            }
            
            if let _ = txCharacteristic, let _ = rxCharacteristic {
                // Initialize directory entries
                loadDirectoryEntries()
            }
        }
    }
}

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
                    Text("RSSI: \(peripheralInfo.rssi)").font(.caption)
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

extension BinaryInteger {
    func fileSize() -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB] // Adjust based on your needs
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(self))
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
