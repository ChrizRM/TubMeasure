import SwiftUI

enum Route: Hashable {
    case job(UUID)
    case scan(UUID)
    case form(UUID)
    case photos(UUID)
    case photo(UUID, String)
}

struct HomeView: View {
    @EnvironmentObject private var store: ScanStore
    @State private var path: [Route] = []
    @State private var creating = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        creating = true
                    } label: {
                        Label("New job", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                    Button {
                        var demo = RoomModel.sample()
                        demo.date = Date()
                        store.save(demo)
                        path = [.job(demo.id)]
                    } label: {
                        Label("Open a demo job", systemImage: "cube.transparent")
                    }
                } footer: {
                    Text("A job holds the bathroom scan, the measurement form and the photo checklist for one customer.")
                }

                Section("Jobs") {
                    if store.rooms.isEmpty {
                        Text("No jobs yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.rooms) { room in
                        NavigationLink(value: Route.job(room.id)) {
                            JobRow(room: room)
                        }
                    }
                    .onDelete { offsets in
                        for id in offsets.map({ store.rooms[$0].id }) { store.delete(id) }
                    }
                }
            }
            .navigationTitle("TubMeasure")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .job(let id): JobView(roomID: id)
                case .scan(let id): ResultView(roomID: id)
                case .form(let id): FormView(roomID: id)
                case .photos(let id): PhotoChecklistView(roomID: id)
                case .photo(let id, let item): PhotoItemView(roomID: id, itemID: item)
                }
            }
        }
        .sheet(isPresented: $creating) {
            NewJobSheet { room in
                store.save(room)
                path = [.job(room.id)]
            }
        }
    }
}

private struct JobRow: View {
    let room: RoomModel

    var body: some View {
        let r = SurveyResolver(room: room)
        let form = r.formProgress, photos = r.photoProgress
        VStack(alignment: .leading, spacing: 2) {
            Text(room.name)
            if !room.survey.info.address.isEmpty {
                Text(room.survey.info.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(room.date.formatted(date: .abbreviated, time: .omitted)) · form \(form.done)/\(form.total) · photos \(photos.done)/\(photos.total)\(room.walls.isEmpty ? " · not scanned" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NewJobSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var info = JobInfo()
    var onCreate: (RoomModel) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Customer name", text: $info.customerName)
                        .textContentType(.name)
                    TextField("Address", text: $info.address, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                    TextField("Prospect # (optional)", text: $info.prospectNumber)
                } footer: {
                    Text("Kept only on this phone. It appears on the PDFs you share.")
                }
            }
            .navigationTitle("New job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = info.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
                        var room = RoomModel(name: name.isEmpty ? "Job " + Date().formatted(date: .abbreviated, time: .shortened) : name)
                        room.survey.info = info
                        onCreate(room)
                        dismiss()
                    }
                }
            }
        }
    }
}
