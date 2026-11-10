import Foundation

enum MeasurementGroup: String, CaseIterable, Identifiable {
    case room, toilet, tub, vanity, windows, doors, points

    var id: String { rawValue }

    var title: String {
        switch self {
        case .room: return "Room"
        case .toilet: return "Toilet & flange"
        case .tub: return "Tub / shower & drain"
        case .vanity: return "Vanity & cabinets"
        case .windows: return "Windows"
        case .doors: return "Doors & openings"
        case .points: return "Custom points"
        }
    }
}

enum MeasurementValue: Hashable {
    case length(Double)   // metres
    case area(Double)     // square metres
    case text(String)

    func formatted(_ units: UnitSystem) -> String {
        switch self {
        case .length(let m): return MeasureFormat.length(m, units)
        case .area(let a): return MeasureFormat.area(a, units)
        case .text(let t): return t
        }
    }
}

struct Measurement: Identifiable, Hashable {
    let id = UUID()
    var group: MeasurementGroup
    var title: String
    var value: MeasurementValue
    var note: String?

    /// Length in metres, when this measurement is a length.
    var metres: Double? {
        if case .length(let m) = value { return m }
        return nil
    }
}

/// Where something sits along a wall.
struct WallPlacement {
    var wall: Surface
    /// Distance from the wall's start end to the nearest side of the item.
    var sideToStart: Double
    /// Distance from the wall's far end to the nearest side of the item.
    var sideToEnd: Double
    var centreToStart: Double
    var centreToEnd: Double
}

/// Turns a `RoomModel` into the list of measurements shown in the app.
struct MeasurementEngine {
    let room: RoomModel
    /// Walls ordered around the room; labelled A, B, C… in this order.
    let walls: [Surface]
    /// Height of the finished floor in the model's coordinates.
    let floorY: Double
    private let labels: [UUID: String]

    /// Two wall ends closer than this are treated as meeting at a corner.
    static let cornerTolerance = 0.35

    init(room: RoomModel) {
        self.room = room
        let raw = room.walls
        let n = Double(max(raw.count, 1))
        let cx = raw.reduce(0) { $0 + $1.box.center.x } / n
        let cz = raw.reduce(0) { $0 + $1.box.center.z } / n
        let sorted = raw.sorted {
            atan2($0.box.center.z - cz, $0.box.center.x - cx) < atan2($1.box.center.z - cz, $1.box.center.x - cx)
        }
        walls = sorted
        var labels: [UUID: String] = [:]
        for (i, w) in sorted.enumerated() {
            labels[w.id] = i < 26 ? String(UnicodeScalar(UInt8(65 + i))) : "W\(i + 1)"
        }
        self.labels = labels

        let floors = room.surfaces.filter { $0.kind == .floor }
        if !floors.isEmpty {
            floorY = floors.reduce(0) { $0 + $1.box.center.y } / Double(floors.count)
        } else if let low = raw.map(\.box.bottomY).min() {
            floorY = low
        } else {
            floorY = room.objects.map(\.box.bottomY).min() ?? 0
        }
    }

    func label(_ wall: Surface) -> String { labels[wall.id] ?? "?" }

    // MARK: - Everything

    func all() -> [Measurement] {
        roomMeasurements() + toiletMeasurements() + tubMeasurements() + vanityMeasurements()
            + windowMeasurements() + doorMeasurements() + pointMeasurements()
    }

    // MARK: - Room

    /// Overall extents measured square to the longest wall: (length, width, height).
    func roomDimensions() -> (length: Double, width: Double, height: Double)? {
        guard let longest = walls.max(by: { $0.box.size.x < $1.box.size.x }) else { return nil }
        let u = longest.box.axisX
        let v = longest.box.axisZ
        let ends = walls.flatMap { [$0.start, $0.end] }
        let us = ends.map { $0.dot(u) }
        let vs = ends.map { $0.dot(v) }
        let a = (us.max() ?? 0) - (us.min() ?? 0)
        let b = (vs.max() ?? 0) - (vs.min() ?? 0)
        let top = walls.map(\.box.topY).max() ?? floorY
        return (max(a, b), min(a, b), top - floorY)
    }

    /// The floor outline, if the walls join end-to-end into a closed loop.
    func floorPolygon() -> [Vec2]? {
        guard walls.count >= 3 else { return nil }
        var remaining = Array(walls.dropFirst())
        var pts = [walls[0].start, walls[0].end]
        var current = walls[0].end
        while !remaining.isEmpty {
            var best: (index: Int, far: Vec2, dist: Double)?
            for (i, w) in remaining.enumerated() {
                for (near, far) in [(w.start, w.end), (w.end, w.start)] {
                    let d = near.distance(to: current)
                    if best == nil || d < best!.dist { best = (i, far, d) }
                }
            }
            guard let b = best, b.dist <= Self.cornerTolerance else { return nil }
            current = b.far
            pts.append(current)
            remaining.remove(at: b.index)
        }
        guard current.distance(to: pts[0]) <= Self.cornerTolerance else { return nil }
        pts.removeLast()
        return pts
    }

    func roomMeasurements() -> [Measurement] {
        guard let dims = roomDimensions() else { return [] }
        var out = [
            Measurement(group: .room, title: "Room length", value: .length(dims.length)),
            Measurement(group: .room, title: "Room width", value: .length(dims.width)),
            Measurement(group: .room, title: "Room height (floor to ceiling)", value: .length(dims.height)),
        ]
        if let poly = floorPolygon() {
            out.append(Measurement(group: .room, title: "Floor area", value: .area(Geometry.polygonArea(poly))))
        } else {
            out.append(Measurement(group: .room, title: "Floor area", value: .area(dims.length * dims.width),
                                   note: "Length × width; the walls did not scan as a closed outline."))
        }
        for w in walls {
            out.append(Measurement(group: .room, title: "Wall \(label(w)) length", value: .length(w.box.size.x)))
        }
        return out
    }

    // MARK: - Wall helpers

    func nearestWall(to p: Vec2, where include: (Surface) -> Bool = { _ in true }) -> (wall: Surface, distance: Double)? {
        var best: (Surface, Double)?
        for w in walls where include(w) {
            let d = Geometry.distance(point: p, segmentA: w.start, segmentB: w.end)
            if best == nil || d < best!.1 { best = (w, d) }
        }
        return best.map { (wall: $0.0, distance: $0.1) }
    }

    /// Names what is at one end of a wall: the wall it meets, or an open end.
    func endName(of wall: Surface, atStart: Bool) -> String {
        let p = atStart ? wall.start : wall.end
        if let hit = nearestWall(to: p, where: { $0.id != wall.id }), hit.distance < Self.cornerTolerance {
            return "wall \(label(hit.wall))"
        }
        return "open end of wall \(label(wall))"
    }

    func placement(footprint: [Vec2], on wall: Surface) -> WallPlacement {
        let axis = wall.box.axisX
        let ts = footprint.map { ($0 - wall.start).dot(axis) }
        let lo = ts.min() ?? 0
        let hi = ts.max() ?? 0
        let mid = (lo + hi) / 2
        let len = wall.box.size.x
        return WallPlacement(wall: wall, sideToStart: max(lo, 0), sideToEnd: max(len - hi, 0),
                             centreToStart: mid, centreToEnd: len - mid)
    }

    private func placementMeasurements(_ name: String, group: MeasurementGroup, footprint: [Vec2],
                                       wall: Surface, sides: Bool, centreline: Bool) -> [Measurement] {
        let p = placement(footprint: footprint, on: wall)
        let a = endName(of: wall, atStart: true)
        let b = endName(of: wall, atStart: false)
        var out = [Measurement(group: group, title: "\(name) location", value: .text("On wall \(label(wall))"))]
        if sides {
            out.append(Measurement(group: group, title: "\(name) side → \(a)", value: .length(p.sideToStart)))
            out.append(Measurement(group: group, title: "\(name) side → \(b)", value: .length(p.sideToEnd)))
        }
        if centreline {
            out.append(Measurement(group: group, title: "\(name) centreline → \(a)", value: .length(p.centreToStart)))
            out.append(Measurement(group: group, title: "\(name) centreline → \(b)", value: .length(p.centreToEnd)))
        }
        return out
    }

    private func parentWall(of s: Surface) -> Surface? {
        if let id = s.parentID, let w = walls.first(where: { $0.id == id }) { return w }
        return nearestWall(to: s.box.center.plan)?.wall
    }

    private func marks(_ kind: MarkKind) -> [MarkedPoint] { room.marks.filter { $0.kind == kind } }

    private func numbered(_ base: String, _ index: Int, of count: Int) -> String {
        count > 1 ? "\(base) \(index + 1)" : base
    }

    // MARK: - Toilet

    /// The wall behind a pair of closet bolts: the nearest wall that runs parallel to the bolt line.
    func backWall(forBolts bolts: [Vec2]) -> Surface? {
        guard let first = bolts.first else { return nil }
        let mid = bolts.count >= 2 ? (bolts[0] + bolts[1]) * 0.5 : first
        if bolts.count >= 2 {
            let dir = (bolts[1] - bolts[0]).normalized
            if let hit = nearestWall(to: mid, where: { abs($0.box.axisX.dot(dir)) > 0.8 }) { return hit.wall }
        }
        return nearestWall(to: mid)?.wall
    }

    func toiletMeasurements() -> [Measurement] {
        var out: [Measurement] = []
        let toilets = room.objects.filter { $0.category == .toilet }
        for (i, t) in toilets.enumerated() {
            let name = numbered("Toilet", i, of: toilets.count)
            out.append(Measurement(group: .toilet, title: "\(name) overall height", value: .length(t.box.topY - floorY),
                                   note: "Floor to the highest scanned part (usually the tank lid). Mark the seat rim for seat height."))
            out.append(Measurement(group: .toilet, title: "\(name) width", value: .length(min(t.box.size.x, t.box.size.z))))
            out.append(Measurement(group: .toilet, title: "\(name) depth (wall to front)", value: .length(max(t.box.size.x, t.box.size.z))))
            if let hit = nearestWall(to: t.box.center.plan) {
                out += placementMeasurements(name, group: .toilet, footprint: t.box.footprint, wall: hit.wall,
                                             sides: false, centreline: true)
            }
        }

        let seats = marks(.toiletSeat)
        for (i, m) in seats.enumerated() {
            out.append(Measurement(group: .toilet, title: numbered("Seat height (marked)", i, of: seats.count),
                                   value: .length(m.position.y - floorY)))
        }

        let bolts = marks(.flangeBolt)
        if bolts.isEmpty {
            if !toilets.isEmpty {
                out.append(Measurement(group: .toilet, title: "Flange bolt rough-in", value: .text("Not marked"),
                                       note: "Mark both closet bolts in the scan to measure bolt-to-wall distance."))
            }
            return out
        }
        // Bolts are marked in pairs, one pair per toilet.
        let pairs = stride(from: 0, to: bolts.count, by: 2).map { Array(bolts[$0..<min($0 + 2, bolts.count)]) }
        for (pi, pair) in pairs.enumerated() {
            let prefix = pairs.count > 1 ? "Toilet \(pi + 1) " : ""
            let pts = pair.map { $0.position.plan }
            guard let wall = backWall(forBolts: pts) else { continue }
            let wl = label(wall)
            let dists = pts.map { Geometry.distance(point: $0, segmentA: wall.start, segmentB: wall.end) }
            for (bi, d) in dists.enumerated() {
                out.append(Measurement(group: .toilet, title: "\(prefix)Flange bolt \(bi + 1) → wall \(wl)", value: .length(d)))
            }
            let roughIn = dists.reduce(0, +) / Double(dists.count)
            out.append(Measurement(group: .toilet, title: "\(prefix)Rough-in (bolt centreline → wall \(wl))",
                                   value: .length(roughIn), note: Self.roughInNote(roughIn)))
            if pts.count == 2 {
                out.append(Measurement(group: .toilet, title: "\(prefix)Bolt spacing", value: .length(pts[0].distance(to: pts[1])),
                                       note: "Closet bolts are normally 6 in apart; a big difference means a mark is off."))
            } else {
                out.append(Measurement(group: .toilet, title: "\(prefix)Second bolt", value: .text("Not marked"),
                                       note: "Mark the bolt on the other side for a more reliable rough-in."))
            }
            let mid = pts.count == 2 ? (pts[0] + pts[1]) * 0.5 : pts[0]
            let p = placement(footprint: [mid], on: wall)
            out.append(Measurement(group: .toilet, title: "\(prefix)Flange centre → \(endName(of: wall, atStart: true))",
                                   value: .length(p.centreToStart)))
            out.append(Measurement(group: .toilet, title: "\(prefix)Flange centre → \(endName(of: wall, atStart: false))",
                                   value: .length(p.centreToEnd)))
        }
        return out
    }

    static func roughInNote(_ metres: Double) -> String {
        let inches = metres / MeasureFormat.metresPerInch
        let nearest = [10.0, 12.0, 14.0].min(by: { abs($0 - inches) < abs($1 - inches) }) ?? 12
        return "Closest standard rough-in: \(Int(nearest)) in. Measured to the finished wall surface, not the baseboard."
    }

    // MARK: - Tub, shower and drain

    private func edgeName(_ a: Vec2, _ b: Vec2, isLong: Bool) -> String {
        let mid = (a + b) * 0.5
        let size = isLong ? "long" : "short"
        if let hit = nearestWall(to: mid), hit.distance < 0.2 {
            return "\(size) edge along wall \(label(hit.wall))"
        }
        return "\(size) open edge"
    }

    func tubMeasurements() -> [Measurement] {
        var out: [Measurement] = []
        let tubs = room.objects.filter { $0.category == .bathtub }
        for (i, t) in tubs.enumerated() {
            let name = numbered("Tub", i, of: tubs.count)
            out.append(Measurement(group: .tub, title: "\(name) length", value: .length(max(t.box.size.x, t.box.size.z))))
            out.append(Measurement(group: .tub, title: "\(name) width", value: .length(min(t.box.size.x, t.box.size.z))))
            out.append(Measurement(group: .tub, title: "\(name) rim height", value: .length(t.box.topY - floorY)))
        }

        let edgePts = marks(.tubEdge).map { $0.position.plan }
        let drains = marks(.drain)
        if drains.isEmpty && (!tubs.isEmpty || !edgePts.isEmpty) {
            out.append(Measurement(group: .tub, title: "Drain", value: .text("Not marked"),
                                   note: "Mark the drain centre in the scan to measure it to the tub or shower edges."))
        }
        for (i, d) in drains.enumerated() {
            let name = numbered("Drain", i, of: drains.count)
            let p = d.position.plan
            let tub = tubs.filter { $0.box.planDistance(to: p) < 1.5 }
                .min(by: { $0.box.planDistance(to: p) < $1.box.planDistance(to: p) })
            if let tub {
                let f = tub.box.footprint
                var edges: [(name: String, dist: Double)] = []
                let longIsX = tub.box.size.x >= tub.box.size.z
                for k in 0..<4 {
                    let a = f[k], b = f[(k + 1) % 4]
                    // Edges 0 and 2 run along local X; 1 and 3 along local Z.
                    let isLong = (k % 2 == 0) == longIsX
                    edges.append((edgeName(a, b, isLong: isLong), Geometry.distance(point: p, segmentA: a, segmentB: b)))
                }
                if let closest = edges.min(by: { $0.dist < $1.dist }) {
                    out.append(Measurement(group: .tub, title: "\(name) centre → closest tub edge", value: .length(closest.dist),
                                           note: "Closest is the \(closest.name). Edges are the tub's outer scanned outline; mark edge points for the inner rim or a shower curb."))
                }
                for e in edges {
                    out.append(Measurement(group: .tub, title: "\(name) centre → tub \(e.name)", value: .length(e.dist)))
                }
            }
            if !edgePts.isEmpty {
                var best = Double.infinity
                if edgePts.count == 1 {
                    best = p.distance(to: edgePts[0])
                } else {
                    for k in 0..<(edgePts.count - 1) {
                        best = min(best, Geometry.distance(point: p, segmentA: edgePts[k], segmentB: edgePts[k + 1]))
                    }
                }
                out.append(Measurement(group: .tub, title: "\(name) centre → closest marked edge", value: .length(best),
                                       note: edgePts.count == 1 ? "Only one edge point marked; this is point-to-point." : nil))
            }
            if tub == nil && edgePts.isEmpty {
                out.append(Measurement(group: .tub, title: "\(name) centre → tub/shower edge", value: .text("No edge found"),
                                       note: "No tub was recognised near this drain. Mark points along the shower edge or curb."))
            }
            // Two nearest walls locate the drain in the room.
            let byDistance = walls.map { ($0, Geometry.distance(point: p, segmentA: $0.start, segmentB: $0.end)) }
                .sorted { $0.1 < $1.1 }
            for (w, dist) in byDistance.prefix(2) {
                out.append(Measurement(group: .tub, title: "\(name) centre → wall \(label(w))", value: .length(dist)))
            }
        }
        return out
    }

    // MARK: - Vanity

    func vanityMeasurements() -> [Measurement] {
        var out: [Measurement] = []
        let sinks = room.objects.filter { $0.category == .sink }
        var cabinets = room.objects.filter { $0.category == .storage }
        var vanities: [(sink: RoomObject, cabinet: RoomObject?)] = []
        for s in sinks {
            if let idx = cabinets.firstIndex(where: { $0.box.contains(plan: s.box.center.plan, margin: 0.3) }) {
                vanities.append((s, cabinets.remove(at: idx)))
            } else {
                vanities.append((s, nil))
            }
        }

        func describe(_ name: String, _ box: OrientedBox, heightTitle: String) {
            guard let hit = nearestWall(to: box.center.plan) else {
                out.append(Measurement(group: .vanity, title: "\(name) width", value: .length(box.size.x)))
                out.append(Measurement(group: .vanity, title: "\(name) depth", value: .length(box.size.z)))
                out.append(Measurement(group: .vanity, title: heightTitle, value: .length(box.topY - floorY)))
                return
            }
            // Width is measured along the wall the unit stands against.
            let alongX = abs(box.axisX.dot(hit.wall.box.axisX)) >= abs(box.axisZ.dot(hit.wall.box.axisX))
            out.append(Measurement(group: .vanity, title: "\(name) width", value: .length(alongX ? box.size.x : box.size.z)))
            out.append(Measurement(group: .vanity, title: "\(name) depth", value: .length(alongX ? box.size.z : box.size.x)))
            out.append(Measurement(group: .vanity, title: heightTitle, value: .length(box.topY - floorY)))
            out += placementMeasurements(name, group: .vanity, footprint: box.footprint, wall: hit.wall,
                                         sides: true, centreline: true)
        }

        for (i, v) in vanities.enumerated() {
            let name = numbered("Vanity", i, of: vanities.count)
            if let cab = v.cabinet {
                describe(name, cab.box, heightTitle: "\(name) cabinet height")
                out.append(Measurement(group: .vanity, title: "\(name) sink rim height", value: .length(v.sink.box.topY - floorY)))
                if let hit = nearestWall(to: cab.box.center.plan) {
                    let p = placement(footprint: [v.sink.box.center.plan], on: hit.wall)
                    out.append(Measurement(group: .vanity, title: "\(name) sink centre → \(endName(of: hit.wall, atStart: true))",
                                           value: .length(p.centreToStart)))
                }
            } else {
                describe("\(name) (sink only)", v.sink.box, heightTitle: "\(name) sink rim height")
            }
        }
        for (i, c) in cabinets.enumerated() {
            let name = numbered("Cabinet", i, of: cabinets.count)
            describe(name, c.box, heightTitle: "\(name) height")
        }
        return out
    }

    // MARK: - Windows and doors

    func windowMeasurements() -> [Measurement] {
        var out: [Measurement] = []
        let windows = room.surfaces.filter { $0.kind == .window }
        for (i, w) in windows.enumerated() {
            let name = numbered("Window", i, of: windows.count)
            out.append(Measurement(group: .windows, title: "\(name) width", value: .length(w.box.size.x)))
            out.append(Measurement(group: .windows, title: "\(name) height", value: .length(w.box.size.y)))
            out.append(Measurement(group: .windows, title: "\(name) sill height above floor", value: .length(w.box.bottomY - floorY)))
            out.append(Measurement(group: .windows, title: "\(name) head height above floor", value: .length(w.box.topY - floorY)))
            if let wall = parentWall(of: w) {
                out += placementMeasurements(name, group: .windows, footprint: [w.start, w.end], wall: wall,
                                             sides: true, centreline: false)
            }
        }
        return out
    }

    func doorMeasurements() -> [Measurement] {
        var out: [Measurement] = []
        let doors = room.surfaces.filter { $0.kind == .door }
        let openings = room.surfaces.filter { $0.kind == .opening }
        func describe(_ name: String, _ s: Surface) {
            out.append(Measurement(group: .doors, title: "\(name) opening width", value: .length(s.box.size.x)))
            out.append(Measurement(group: .doors, title: "\(name) opening height", value: .length(s.box.size.y),
                                   note: s.box.bottomY - floorY > 0.05 ? "Bottom of the opening is above the floor." : nil))
            if let wall = parentWall(of: s) {
                out += placementMeasurements(name, group: .doors, footprint: [s.start, s.end], wall: wall,
                                             sides: true, centreline: false)
            }
        }
        for (i, d) in doors.enumerated() { describe(numbered("Door", i, of: doors.count), d) }
        for (i, o) in openings.enumerated() { describe(numbered("Opening", i, of: openings.count), o) }
        return out
    }

    // MARK: - Custom points

    func pointMeasurements() -> [Measurement] {
        var out: [Measurement] = []
        let pts = marks(.custom)
        for (i, m) in pts.enumerated() {
            out.append(Measurement(group: .points, title: "Point \(i + 1) height above floor", value: .length(m.position.y - floorY)))
            if let hit = nearestWall(to: m.position.plan) {
                out.append(Measurement(group: .points, title: "Point \(i + 1) → wall \(label(hit.wall))", value: .length(hit.distance)))
            }
            if i > 0 {
                out.append(Measurement(group: .points, title: "Point \(i) → point \(i + 1)",
                                       value: .length(pts[i - 1].position.distance(to: m.position))))
            }
        }
        return out
    }
}
