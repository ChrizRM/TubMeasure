import Foundation

/// Saved scans, one folder per room under Documents/Scans.
@MainActor
final class ScanStore: ObservableObject {
    @Published private(set) var rooms: [RoomModel] = []

    private static let roomFile = "room.json"
    static let usdzFile = "room.usdz"

    init() {
        load()
    }

    private static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Scans", isDirectory: true)
    }

    /// The folder holding one scan's files; created on demand.
    static func folder(for id: UUID) -> URL {
        let url = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func room(_ id: UUID) -> RoomModel? {
        rooms.first { $0.id == id }
    }

    func save(_ room: RoomModel) {
        if let i = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[i] = room
        } else {
            rooms.insert(room, at: 0)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(room)
            try data.write(to: Self.folder(for: room.id).appendingPathComponent(Self.roomFile), options: .atomic)
        } catch {
            print("TubMeasure: could not save scan: \(error)")
        }
    }

    func delete(_ id: UUID) {
        rooms.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(id.uuidString))
    }

    private func load() {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let folders = (try? fm.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? []
        rooms = folders.compactMap { folder -> RoomModel? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.roomFile)) else { return nil }
            return try? decoder.decode(RoomModel.self, from: data)
        }
        .sorted { $0.date > $1.date }
    }
}
