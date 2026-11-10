import Foundation

/// Isometric projection used by the isometric view.
/// The camera looks down from the +X/+Z corner; `quarterTurns` spins the room in 90° steps.
struct IsoProjector {
    var quarterTurns: Int = 0
    var pivot: Vec2 = .zero

    private func rotated(_ p: Vec3) -> Vec3 {
        var x = p.x - pivot.x, z = p.z - pivot.y
        for _ in 0..<(((quarterTurns % 4) + 4) % 4) { (x, z) = (-z, x) }
        return Vec3(x, p.y, z)
    }

    /// Screen position in metres-scaled units; +y is down the screen.
    func project(_ p: Vec3) -> Vec2 {
        let r = rotated(p)
        return Vec2((r.x - r.z) * 0.8660254, (r.x + r.z) * 0.5 - r.y)
    }

    /// Larger values are nearer the camera (draw them later).
    func depth(_ p: Vec3) -> Double {
        let r = rotated(p)
        return r.x + r.z + r.y
    }
}
