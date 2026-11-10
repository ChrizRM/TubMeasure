import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: ScanStore
    @State private var path: [UUID] = []
    @State private var scanning = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan a bathroom", systemImage: "camera.viewfinder")
                            .font(.headline)
                    }
                    .disabled(!CaptureController.isSupported)

                    if !CaptureController.isSupported {
                        Text("Scanning needs a LiDAR device (iPhone 12 Pro or later Pro models, or iPad Pro). You can still explore the demo room.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        var demo = RoomModel.sample()
                        demo.date = Date()
                        store.save(demo)
                        path = [demo.id]
                    } label: {
                        Label("Open a demo room", systemImage: "cube.transparent")
                    }
                }

                Section("Saved scans") {
                    if store.rooms.isEmpty {
                        Text("No scans yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.rooms) { room in
                        NavigationLink(value: room.id) {
                            VStack(alignment: .leading) {
                                Text(room.name)
                                Text(room.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for id in offsets.map({ store.rooms[$0].id }) { store.delete(id) }
                    }
                }
            }
            .navigationTitle("TubMeasure")
            .navigationDestination(for: UUID.self) { id in
                ResultView(roomID: id)
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            ScanView { id in
                path = [id]
            }
        }
    }
}
