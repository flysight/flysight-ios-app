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

    @State private var isDownloading = false
    @State private var isUploading = false
    @State private var showFileImporter = false
    @State private var selectedFileURL: URL?

    var body: some View {
        NavigationView {
            List {
                ForEach(bluetoothManager.directoryEntries.filter { !$0.isHidden }) { entry in
                    Button(action: {
                        if entry.isFolder {
                            bluetoothManager.changeDirectory(to: entry.name)
                        } else {
                            downloadFile(entry)
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
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(action: {
                        showFileImporter = true
                    }) {
                        Text("Upload")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        selectedFileURL = url
                        uploadFile()
                    }
                case .failure(let error):
                    print("Failed to select file: \(error.localizedDescription)")
                }
            }
            .overlay(
                VStack {
                    if isDownloading {
                        DownloadProgressView(isShowing: $isDownloading, progress: $bluetoothManager.downloadProgress, cancelAction: cancelDownload)
                            .padding()
                    }
                    if isUploading {
                        UploadProgressView(isShowing: $isUploading, progress: $bluetoothManager.uploadProgress, cancelAction: cancelUpload)
                            .padding()
                    }
                }
            )
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

    private func downloadFile(_ entry: FlySightCore.DirectoryEntry) {
        isDownloading = true
        let fullPath = (bluetoothManager.currentPath + [entry.name]).joined(separator: "/")
        bluetoothManager.downloadFile(named: fullPath) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    // Save the file locally
                    saveFile(data: data, name: entry.name)
                case .failure(let error):
                    print("Failed to download file: \(error.localizedDescription)")
                }
                isDownloading = false
            }
        }
    }

    private func uploadFile() {
        guard let fileURL = selectedFileURL else { return }
        isUploading = true
        let destinationPath = "/" + (bluetoothManager.currentPath + [fileURL.lastPathComponent]).joined(separator: "/")

        // Access the security-scoped resource
        guard fileURL.startAccessingSecurityScopedResource() else {
            print("Failed to access security-scoped resource")
            isUploading = false
            return
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        // Read data from the file
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            print("Failed to read file data: \(error.localizedDescription)")
            isUploading = false
            return
        }

        // Call the uploadFile method with corrected argument labels and proper handling
        bluetoothManager.uploadFile(fileData: fileData, remotePath: destinationPath) { result in
            DispatchQueue.main.async {
                isUploading = false
                switch result {
                case .success:
                    print("File uploaded successfully")
                    bluetoothManager.loadDirectoryEntries()
                case .failure(let error):
                    print("Failed to upload file: \(error.localizedDescription)")
                }
            }
        }
    }

    private func saveFile(data: Data, name: String) {
        // Save the data to the phone
        let fileManager = FileManager.default
        if let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentDirectory.appendingPathComponent(name)
            do {
                try data.write(to: fileURL)
                print("File saved to \(fileURL.path)")
                presentShareSheet(fileURL: fileURL)
            } catch {
                print("Failed to save file: \(error.localizedDescription)")
            }
        }
    }

    private func presentShareSheet(fileURL: URL) {
        let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let topController = UIApplication.shared.windows.first?.rootViewController {
            topController.present(activityViewController, animated: true, completion: nil)
        }
    }

    private func cancelDownload() {
        bluetoothManager.cancelDownload()
        isDownloading = false
    }

    private func cancelUpload() {
        bluetoothManager.cancelUpload()
    }
}

struct DownloadProgressView: View {
    @Binding var isShowing: Bool
    @Binding var progress: Float
    var cancelAction: () -> Void

    var body: some View {
        if isShowing {
            VStack {
                Text("Downloading...")
                    .font(.headline)
                    .padding()

                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding()

                Button("Cancel") {
                    cancelAction()
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .frame(width: 300, height: 200)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(radius: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray, lineWidth: 1)
            )
        }
    }
}

struct UploadProgressView: View {
    @Binding var isShowing: Bool
    @Binding var progress: Float
    var cancelAction: () -> Void

    var body: some View {
        if isShowing {
            VStack {
                Text("Uploading...")
                    .font(.headline)
                    .padding()

                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding()

                Button("Cancel") {
                    cancelAction()
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .frame(width: 300, height: 200)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(radius: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray, lineWidth: 1)
            )
        }
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
