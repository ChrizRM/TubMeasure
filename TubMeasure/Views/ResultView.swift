import SwiftUI

struct ResultView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case plan = "Plan", iso = "Isometric", model = "3D", sizes = "Sizes", items = "Items"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: ScanStore
    let roomID: UUID
    @AppStorage("units") private var units: UnitSystem = .imperial
    @State private var tab: Pane = .plan
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        if let room = store.room(roomID) {
            content(room)
        } else {
            Text("This scan is no longer available.")
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ room: RoomModel) -> some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            switch tab {
            case .plan: PlanView(room: room, units: units)
            case .iso: IsoView(room: room)
            case .model: Scene3DView(room: room).id(room.id)
            case .sizes: MeasurementsView(room: room, units: units)
            case .items: ItemsView(room: room)
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Picker("Units", selection: $units) {
                    ForEach(UnitSystem.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)

                Menu {
                    ShareLink(item: Report.text(for: room, units: units)) {
                        Label("Share measurements", systemImage: "doc.text")
                    }
                    if room.hasUSDZ {
                        ShareLink(item: ScanStore.folder(for: room.id).appendingPathComponent(ScanStore.usdzFile)) {
                            Label("Share 3D model (USDZ)", systemImage: "cube")
                        }
                    }
                    Button {
                        newName = room.name
                        renaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename scan", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                var updated = room
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    updated.name = trimmed
                    store.save(updated)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct MeasurementsView: View {
    let room: RoomModel
    let units: UnitSystem

    var body: some View {
        let all = MeasurementEngine(room: room).all()
        List {
            if all.isEmpty {
                Text("Nothing was measured in this scan.")
                    .foregroundStyle(.secondary)
            }
            ForEach(MeasurementGroup.allCases) { group in
                let rows = all.filter { $0.group == group }
                if !rows.isEmpty {
                    Section(group.title) {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.title)
                                    Spacer()
                                    Text(row.value.formatted(units))
                                        .font(.body.monospacedDigit().weight(.semibold))
                                        .multilineTextAlignment(.trailing)
                                }
                                if let note = row.note {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Text("LiDAR is typically within about 1–2 cm (½ in). Confirm critical dimensions with a tape before ordering or cutting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Loose items seen in the room. Detections can be corrected by hand.
struct ItemsView: View {
    @EnvironmentObject private var store: ScanStore
    let room: RoomModel

    var body: some View {
        List {
            Section {
                if room.items.isEmpty {
                    Text("No chairs, rugs, toiletries or shower curtains were noticed.")
                        .foregroundStyle(.secondary)
                }
                ForEach(room.items) { item in
                    HStack {
                        Image(systemName: Theme.symbol(item.category))
                            .frame(width: 28)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(item.category.displayName)
                            Text(detail(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    var updated = room
                    updated.items.remove(atOffsets: offsets)
                    store.save(updated)
                }
            } header: {
                Text("Loose items noticed")
            } footer: {
                Text("Chairs come from the 3D scan. Other items are recognised from camera frames, which shows they were seen but not where. Swipe to remove a wrong one.")
            }

            let missing = ItemCategory.allCases.filter { c in !room.items.contains { $0.category == c } }
            if !missing.isEmpty {
                Section("Add by hand") {
                    ForEach(missing) { category in
                        Button {
                            var updated = room
                            updated.items.append(DetectedItem(category: category, source: .manual, confidence: 1, sightings: 1))
                            store.save(updated)
                        } label: {
                            Label(category.displayName, systemImage: "plus.circle")
                        }
                    }
                }
            }

        }
    }

    private func detail(_ item: DetectedItem) -> String {
        switch item.source {
        case .scan: return "3D scan · \(item.sightings) found"
        case .camera: return "Camera · seen in \(item.sightings) frames · \(Int(item.confidence * 100))% confidence"
        case .manual: return "Added by hand"
        }
    }
}
