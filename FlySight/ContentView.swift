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
    var rssi: Int
    var name: String {
        peripheral.name ?? "Unnamed Device"
    }
    var id: UUID {
        peripheral.identifier
    }
}

class BluetoothViewModel: NSObject, ObservableObject {
    private var centralManager: CBCentralManager?

    @Published var peripheralInfos: [PeripheralInfo] = []

    let CRS_RX_UUID = CBUUID(string: "00000002-8e22-4541-9d4c-21edae82ed19")
    let CRS_TX_UUID = CBUUID(string: "00000001-8e22-4541-9d4c-21edae82ed19")

    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?

    @Published var txData: String? = nil

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

        // Reset the TX data
        txData = nil

        // Optionally: Handle any UI updates or perform cleanup after disconnection
        // This might involve updating published properties or notifying the user
    }
}

extension BluetoothViewModel: CBPeripheralDelegate {
    // Assuming CRS_TX_UUID is the characteristic where directory listing data will be notified
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("Error reading characteristic: \(error?.localizedDescription ?? "Unknown error")")
            return
        }

        if characteristic.uuid == CRS_TX_UUID {
            if let data = characteristic.value {
                let hexString = data.map { String(format: "%02X", $0) }.joined()
                DispatchQueue.main.async {
                    self.txData = hexString // Ensure txData is of type String in your ViewModel
                }
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
            
            if let tx = txCharacteristic, let rx = rxCharacteristic {
                let directory = "/"
                let directoryCommand = Data([0x05]) + directory.data(using: .utf8)!
                peripheral.writeValue(directoryCommand, for: rx, type: .withoutResponse)
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
    @EnvironmentObject var bluetoothViewModel: BluetoothViewModel

    var body: some View {
        VStack {
            if let txData = bluetoothViewModel.txData {
                Text("TX data: \(txData)")
            } else {
                Text("TX data: nil")
            }
        }
        .navigationTitle(peripheralInfo.name)
        .onAppear {
            // Ensure we're connected to the correct peripheral
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
