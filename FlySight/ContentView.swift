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
        // Handle successful connection, such as discovering services.
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Handle peripheral disconnection if needed.
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
