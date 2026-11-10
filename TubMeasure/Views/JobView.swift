import SwiftUI

/// One customer's job: the scan, the measurement form, the photo checklist and export.
struct JobView: View {
    @EnvironmentObject private var store: ScanStore
    let roomID: UUID
    @AppStorage("units") private var units: UnitSystem = .imperial
    @State private var scanning = false
    @State private var confirmRescan = false
    @State private var share: ShareItems?
    @State private var exportError: String?
    @State private var copied = false

    var body: some View {
        if let room = store.room(roomID) {
            content(room)
        } else {
            Text("This job is no longer available.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ room: RoomModel) -> some View {
        let r = SurveyResolver(room: room)
        let form = r.formProgress, photos = r.photoProgress
        return List {
            Section("Customer") {
                TextField("Customer name", text: info(\.customerName))
                TextField("Address", text: info(\.address), axis: .vertical)
                TextField("Prospect #", text: info(\.prospectNumber))
            }

            Section {
                if room.walls.isEmpty {
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan the bathroom", systemImage: "camera.viewfinder")
                            .font(.headline)
                    }
                    .disabled(!CaptureController.isSupported)
                } else {
                    NavigationLink(value: Route.scan(roomID)) {
                        Label("Plan, 3D and all sizes", systemImage: "cube")
                    }
                    Button {
                        confirmRescan = true
                    } label: {
                        Label("Re-scan", systemImage: "arrow.clockwise")
                    }
                    .disabled(!CaptureController.isSupported)
                }
            } header: {
                Text("Scan")
            } footer: {
                if !CaptureController.isSupported {
                    Text("Scanning needs an iPhone or iPad with LiDAR. You can still fill in the form and photos.")
                } else if room.walls.isEmpty {
                    Text("Sweep the room, then mark the drain, flange bolts, shelf above the toilet, top of tile, hallway and other doors. Most of the form fills itself in.")
                }
            }

            Section("Office forms") {
                NavigationLink(value: Route.form(roomID)) {
                    ProgressRow(title: "Measurements", symbol: "ruler", done: form.done, total: form.total)
                }
                NavigationLink(value: Route.photos(roomID)) {
                    ProgressRow(title: "Photos", symbol: "camera", done: photos.done, total: photos.total)
                }
            }

            Section {
                Button {
                    exportPDFs(room)
                } label: {
                    Label("Share measurement & photo PDFs", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = r.formText()
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy all measurement answers", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("Send to the office")
            } footer: {
                Text("The PDFs follow the order of the office forms. Copied answers paste as one \"question: answer\" per line.")
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .fullScreenCover(isPresented: $scanning) {
            ScanView(jobID: roomID)
        }
        .confirmationDialog("Re-scan the bathroom?", isPresented: $confirmRescan, titleVisibility: .visible) {
            Button("Re-scan") { scanning = true }
        } message: {
            Text("The new scan replaces the room measurements and marked points. Typed answers and photos are kept.")
        }
        .sheet(item: $share) { items in
            ShareSheet(items: items.urls)
        }
        .alert("Couldn't make the PDFs", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func info(_ key: WritableKeyPath<JobInfo, String>) -> Binding<String> {
        Binding(
            get: { store.room(roomID)?.survey.info[keyPath: key] ?? "" },
            set: { value in
                store.update(roomID) { room in
                    room.survey.info[keyPath: key] = value
                    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if key == \JobInfo.customerName && !name.isEmpty { room.name = name }
                }
            }
        )
    }

    private func exportPDFs(_ room: RoomModel) {
        do {
            share = ShareItems(urls: [try SurveyPDF.measurements(for: room, units: units), try SurveyPDF.photos(for: room)])
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct ProgressRow: View {
    let title: String
    let symbol: String
    let done: Int
    let total: Int

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text("\(done) of \(total)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(done == total ? .green : .secondary)
            if done == total {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

struct ShareItems: Identifiable {
    let id = UUID()
    var urls: [URL]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
