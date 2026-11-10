import Foundation

/// A point or direction on the floor plan. `x` is world X, `y` is world Z (metres).
struct Vec2: Codable, Hashable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = Vec2(0, 0)

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }

    func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    var length: Double { (x * x + y * y).squareRoot() }
    func distance(to o: Vec2) -> Double { (self - o).length }
    var normalized: Vec2 {
        let l = length
        return l > 1e-9 ? Vec2(x / l, y / l) : .zero
    }
}

/// A point in world space, metres, Y up (the ARKit convention).
struct Vec3: Codable, Hashable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }

    var length: Double { (x * x + y * y + z * z).squareRoot() }
    func distance(to o: Vec3) -> Double { (self - o).length }
    /// Position on the floor plan (drops height).
    var plan: Vec2 { Vec2(x, z) }
}

/// An upright box: rotated about the vertical axis only.
/// `size.x` runs along the box's local X axis, `size.y` is height, `size.z` is depth.
struct OrientedBox: Codable, Hashable {
    var center: Vec3
    var size: Vec3
    /// Rotation about +Y in radians. Local X maps to world (cos yaw, 0, -sin yaw).
    var yaw: Double

    /// Local X axis on the floor plan.
    var axisX: Vec2 { Vec2(cos(yaw), -sin(yaw)) }
    /// Local Z (depth) axis on the floor plan.
    var axisZ: Vec2 { Vec2(sin(yaw), cos(yaw)) }

    var bottomY: Double { center.y - size.y / 2 }
    var topY: Double { center.y + size.y / 2 }

    /// The four floor-plan corners, in order around the box.
    var footprint: [Vec2] {
        let c = center.plan
        let hx = axisX * (size.x / 2)
        let hz = axisZ * (size.z / 2)
        return [c - hx - hz, c + hx - hz, c + hx + hz, c - hx + hz]
    }

    /// Eight corners: the footprint at the bottom, then the footprint at the top.
    var corners: [Vec3] {
        let f = footprint
        return f.map { Vec3($0.x, bottomY, $0.y) } + f.map { Vec3($0.x, topY, $0.y) }
    }

    /// Whether a plan point lies inside the footprint grown by `margin` on every side.
    func contains(plan p: Vec2, margin: Double = 0) -> Bool {
        let d = p - center.plan
        return abs(d.dot(axisX)) <= size.x / 2 + margin && abs(d.dot(axisZ)) <= size.z / 2 + margin
    }

    /// Horizontal distance from a plan point to the footprint (0 when inside).
    func planDistance(to p: Vec2) -> Double {
        let d = p - center.plan
        let dx = max(abs(d.dot(axisX)) - size.x / 2, 0)
        let dz = max(abs(d.dot(axisZ)) - size.z / 2, 0)
        return (dx * dx + dz * dz).squareRoot()
    }
}

enum Geometry {
    /// Shortest distance from `point` to the segment `a`–`b`.
    static func distance(point p: Vec2, segmentA a: Vec2, segmentB b: Vec2) -> Double {
        let ab = b - a
        let len2 = ab.dot(ab)
        guard len2 > 1e-12 else { return p.distance(to: a) }
        let t = min(max((p - a).dot(ab) / len2, 0), 1)
        return p.distance(to: a + ab * t)
    }

    /// Area of a simple polygon (shoelace formula).
    static func polygonArea(_ pts: [Vec2]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var sum = 0.0
        for i in pts.indices {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }
}
