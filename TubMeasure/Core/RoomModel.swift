import Foundation

enum SurfaceKind: String, Codable {
    case wall, door, window, opening, floor
}

/// A wall, or something set into a wall. `box.size.z` is ~0 for scanned surfaces.
struct Surface: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: SurfaceKind
    var box: OrientedBox
    /// The wall a door/window/opening sits in, when the scanner reported it.
    var parentID: UUID?
    var isOpenDoor: Bool?

    var start: Vec2 { box.center.plan - box.axisX * (box.size.x / 2) }
    var end: Vec2 { box.center.plan + box.axisX * (box.size.x / 2) }
}

enum ObjectCategory: String, Codable, CaseIterable {
    case toilet, bathtub, sink, storage, chair, table, washerDryer, sofa, bed
    case television, refrigerator, stove, oven, dishwasher, fireplace, stairs, other

    var displayName: String {
        switch self {
        case .toilet: return "Toilet"
        case .bathtub: return "Tub"
        case .sink: return "Sink"
        case .storage: return "Cabinet"
        case .chair: return "Chair"
        case .table: return "Table"
        case .washerDryer: return "Washer/dryer"
        case .sofa: return "Sofa"
        case .bed: return "Bed"
        case .television: return "TV"
        case .refrigerator: return "Fridge"
        case .stove: return "Stove"
        case .oven: return "Oven"
        case .dishwasher: return "Dishwasher"
        case .fireplace: return "Fireplace"
        case .stairs: return "Stairs"
        case .other: return "Object"
        }
    }
}

struct RoomObject: Codable, Identifiable, Hashable {
    var id = UUID()
    var category: ObjectCategory
    var box: OrientedBox
}

/// A point the user marks by hand in AR, for things the scanner cannot recognise.
enum MarkKind: String, Codable, CaseIterable, Identifiable {
    case drain, flangeBolt, tubEdge, toiletSeat, shelfBottom, tileTop, hallway, extraDoor, custom

    var id: String { rawValue }

    /// Hallway and other-door widths are measured outside the bathroom, so they are left off the drawings.
    var isInRoom: Bool { self != .hallway && self != .extraDoor }

    var displayName: String {
        switch self {
        case .drain: return "Drain centre"
        case .flangeBolt: return "Flange bolt"
        case .tubEdge: return "Tub/shower edge"
        case .toiletSeat: return "Toilet seat rim"
        case .shelfBottom: return "Shelf over toilet"
        case .tileTop: return "Top of tile"
        case .hallway: return "Hallway width"
        case .extraDoor: return "Other door width"
        case .custom: return "Custom point"
        }
    }

    var instruction: String {
        switch self {
        case .drain:
            return "Aim the crosshair at the centre of the tub drain and tap Mark."
        case .flangeBolt:
            return "Mark the two closet bolts (bolt caps) at the base of the toilet, one on each side."
        case .tubEdge:
            return "Mark points along the tub or shower edge / curb, in order. Two or more points make an edge line."
        case .toiletSeat:
            return "Aim at the top of the toilet seat rim to record seat height."
        case .shelfBottom:
            return "Aim at the underside of the shelf or counter above the toilet."
        case .tileTop:
            return "Aim at the top edge of the tile or surround around the tub."
        case .hallway:
            return "Walk into the hallway. Mark one wall, then the opposite wall, at the narrowest point."
        case .extraDoor:
            return "For each other door being removed, mark one side of the opening and then the other (jamb to jamb)."
        case .custom:
            return "Mark any point. Consecutive custom points are measured like a tape."
        }
    }
}

struct MarkedPoint: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: MarkKind
    var position: Vec3
}

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case chair, carpet, toiletries, showerCurtain, towel, bin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chair: return "Chair / stool"
        case .carpet: return "Carpet / rug / bath mat"
        case .toiletries: return "Toiletries"
        case .showerCurtain: return "Shower curtain"
        case .towel: return "Towels / robe"
        case .bin: return "Bin / basket / hamper"
        }
    }
}

enum ItemSource: String, Codable {
    case scan      // RoomPlan recognised the object in 3D
    case camera    // on-device image classification of camera frames
    case manual    // added by the user

    var displayName: String {
        switch self {
        case .scan: return "3D scan"
        case .camera: return "Camera"
        case .manual: return "Added by hand"
        }
    }
}

/// A loose item noticed in the room (things to move before work starts).
struct DetectedItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var category: ItemCategory
    var source: ItemSource
    /// 0…1. For camera detections this is the best classifier confidence seen.
    var confidence: Double
    /// How many sampled frames (camera) or objects (scan) support this.
    var sightings: Int
}

struct RoomModel: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var date = Date()
    var surfaces: [Surface] = []
    var objects: [RoomObject] = []
    var marks: [MarkedPoint] = []
    var items: [DetectedItem] = []
    var survey = Survey()
    var hasUSDZ = false

    var walls: [Surface] { surfaces.filter { $0.kind == .wall } }

    /// Returns the room rotated so its longest wall runs along +X, moved so the
    /// plan's minimum corner is the origin and the floor is at height 0.
    /// AR world axes are arbitrary; this makes plans draw square to the page.
    func normalized() -> RoomModel {
        let walls = self.walls
        guard let longest = walls.max(by: { $0.box.size.x < $1.box.size.x }) else { return self }
        let phi = -longest.box.yaw
        let c = cos(phi), s = sin(phi)
        func rot(_ p: Vec3) -> Vec3 { Vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c) }

        var out = self
        for i in out.surfaces.indices {
            out.surfaces[i].box.center = rot(out.surfaces[i].box.center)
            out.surfaces[i].box.yaw += phi
        }
        for i in out.objects.indices {
            out.objects[i].box.center = rot(out.objects[i].box.center)
            out.objects[i].box.yaw += phi
        }
        for i in out.marks.indices {
            out.marks[i].position = rot(out.marks[i].position)
        }

        let ends = out.walls.flatMap { [$0.start, $0.end] }
        let minX = ends.map(\.x).min() ?? 0
        let minZ = ends.map(\.y).min() ?? 0
        let floorY = MeasurementEngine(room: out).floorY
        let shift = Vec3(minX, floorY, minZ)
        for i in out.surfaces.indices { out.surfaces[i].box.center = out.surfaces[i].box.center - shift }
        for i in out.objects.indices { out.objects[i].box.center = out.objects[i].box.center - shift }
        for i in out.marks.indices { out.marks[i].position = out.marks[i].position - shift }
        return out
    }

    /// Plan-view bounding box of everything in the room: (min, max).
    var planBounds: (min: Vec2, max: Vec2) {
        var pts = surfaces.filter { $0.kind != .floor }.flatMap { [$0.start, $0.end] }
        pts += objects.flatMap { $0.box.footprint }
        pts += marks.filter(\.kind.isInRoom).map { $0.position.plan }
        guard let first = pts.first else { return (Vec2.zero, Vec2(1, 1)) }
        var lo = first, hi = first
        for p in pts {
            lo = Vec2(min(lo.x, p.x), min(lo.y, p.y))
            hi = Vec2(max(hi.x, p.x), max(hi.y, p.y))
        }
        return (lo, hi)
    }
}
