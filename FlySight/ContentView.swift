//
//  ContentView.swift
//  FlySight
//
//  Created by Michael Cooper on 2024-04-04.
//

import SwiftUI
import CoreBluetooth

// Define a structure to hold peripheral information
struct PeripheralInfo: Identifiable {
    let peripheral: CBPeripheral
    var name: String {
        peripheral.name ?? "Unnamed Device"
    }
    var rssi: Int
    var id: UUID {
        peripheral.identifier
    }
}

class BluetoothViewModel: NSObject, ObservableObject {
    private var centralManager: CBCentralManager?
    @Published var peripheralInfos: [PeripheralInfo] = []

    let CRS_RX_UUID = CBUUID(string: "00000002-8e22-4541-9d4c-21edae82ed19")
    let CRS_TX_UUID = CBUUID(string: "00000001-8e22-4541-9d4c-21edae82ed19")

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

    func requestDirectoryListing(forPeripheral peripheral: CBPeripheral, directory: String) {
        guard let rxCharacteristic = findCharacteristic(byUuid: CRS_RX_UUID, inPeripheral: peripheral) else {
            print("CRS_RX_UUID characteristic not found.")
            return
        }

        let directoryCommand = Data([0x05]) + directory.data(using: .utf8)!
        peripheral.writeValue(directoryCommand, for: rxCharacteristic, type: .withoutResponse)

        // Ensure you've subscribed to notifications on the CRS_TX_UUID characteristic elsewhere in your code
    }

    func findCharacteristic(byUuid uuid: CBUUID, inPeripheral peripheral: CBPeripheral) -> CBCharacteristic? {
        // First, safely unwrap `peripheral.services` to ensure it's not nil
        guard let services = peripheral.services else { return nil }

        // Then, iterate over each service's characteristics.
        // Use compactMap to safely deal with optional characteristics arrays and flatten the result.
        let characteristics = services.compactMap { $0.characteristics }.flatMap { $0 }

        // Finally, find the first characteristic that matches the UUID.
        return characteristics.first { $0.uuid == uuid }
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
        print("Connected to \(peripheral.name ?? "Unknown Device")")

        // Set this object as the delegate for the peripheral to receive peripheral delegate callbacks.
        peripheral.delegate = self

        // Optionally start discovering services or characteristics here
        peripheral.discoverServices(nil)  // Passing nil will discover all services
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "Unknown Device")")
    }
}

extension BluetoothViewModel: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("Error while updating value for characteristic \(characteristic.uuid): \(error!.localizedDescription)")
            return
        }

        // Check if this is the characteristic you're interested in
        if characteristic.uuid == CRS_TX_UUID {
            // Handle the characteristic value update
            // For example, parsing the data for a directory listing
            if let data = characteristic.value {
                // Parse the data as needed
                print("Received data from \(characteristic.uuid): \(data)")
                // Update your model/UI as appropriate
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }
        for service in services {
            // Discover characteristics for services of interest
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
                    // Subscribe to this characteristic's notifications
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject private var bluetoothViewModel = BluetoothViewModel()

    var body: some View {
        NavigationView {
            List(bluetoothViewModel.peripheralInfos) { peripheralInfo in
                NavigationLink(destination: PeripheralDetailView(peripheralInfo: peripheralInfo)) {
                    HStack {
                        Text(peripheralInfo.name)
                        Spacer()
                        Text("RSSI: \(peripheralInfo.rssi)")
                    }
                }
            }
            .navigationTitle("Peripherals")
            .toolbar {
                // Add a toolbar item for sorting
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sort") {
                        bluetoothViewModel.sortPeripheralsByRSSI()
                    }
                }
            }
        }
    }
}

struct PeripheralDetailView: View {
    var peripheralInfo: PeripheralInfo
    @EnvironmentObject var bluetoothViewModel: BluetoothViewModel // Ensure BluetoothViewModel is provided as an environment object

    var body: some View {
        VStack {
            Text(peripheralInfo.name)
            Text("RSSI: \(peripheralInfo.rssi)")
        }
        .navigationTitle(peripheralInfo.name)
        .onAppear {
            bluetoothViewModel.connect(to: peripheralInfo.peripheral)
        }
        .onDisappear {
            bluetoothViewModel.disconnect(from: peripheralInfo.peripheral)
        }
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
