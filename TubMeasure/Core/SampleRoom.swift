import Foundation

extension RoomModel {
    /// A typical 5 ft × 8 ft bathroom, used for the demo and for tests.
    /// Plan: X runs 0…1.524 m across the room, Z runs 0…2.438 m from the door wall to the tub wall.
    static func sample() -> RoomModel {
        let w = 1.524, l = 2.438, h = 2.438
        func wall(_ cx: Double, _ cz: Double, _ len: Double, _ yaw: Double) -> Surface {
            Surface(kind: .wall, box: OrientedBox(center: Vec3(cx, h / 2, cz), size: Vec3(len, h, 0), yaw: yaw))
        }
        let front = wall(w / 2, 0, w, 0)
        let back = wall(w / 2, l, w, .pi)
        let left = wall(0, l / 2, l, -.pi / 2)
        let right = wall(w, l / 2, l, .pi / 2)

        let door = Surface(kind: .door,
                           box: OrientedBox(center: Vec3(1.0, 1.016, 0), size: Vec3(0.762, 2.032, 0), yaw: 0),
                           parentID: front.id, isOpenDoor: false)
        let window = Surface(kind: .window,
                             box: OrientedBox(center: Vec3(w / 2, 1.6, l), size: Vec3(0.61, 0.61, 0), yaw: .pi),
                             parentID: back.id)

        let tub = RoomObject(category: .bathtub,
                             box: OrientedBox(center: Vec3(w / 2, 0.25, l - 0.381), size: Vec3(w, 0.5, 0.762), yaw: 0))
        let toilet = RoomObject(category: .toilet,
                                box: OrientedBox(center: Vec3(0.35, 0.375, 1.25), size: Vec3(0.40, 0.75, 0.70), yaw: -.pi / 2))
        let cabinet = RoomObject(category: .storage,
                                 box: OrientedBox(center: Vec3(0.27, 0.43, 0.45), size: Vec3(0.61, 0.86, 0.54), yaw: -.pi / 2))
        let sink = RoomObject(category: .sink,
                              box: OrientedBox(center: Vec3(0.27, 0.84, 0.45), size: Vec3(0.45, 0.15, 0.40), yaw: -.pi / 2))

        let marks = [
            MarkedPoint(kind: .flangeBolt, position: Vec3(0.3048, 0.02, 1.25 - 0.0762)),
            MarkedPoint(kind: .flangeBolt, position: Vec3(0.3048, 0.02, 1.25 + 0.0762)),
            MarkedPoint(kind: .toiletSeat, position: Vec3(0.45, 0.42, 1.25)),
            MarkedPoint(kind: .drain, position: Vec3(0.25, 0.05, l - 0.381)),
        ]
        let items = [
            DetectedItem(category: .carpet, source: .camera, confidence: 0.62, sightings: 9),
            DetectedItem(category: .showerCurtain, source: .camera, confidence: 0.48, sightings: 6),
            DetectedItem(category: .toiletries, source: .camera, confidence: 0.33, sightings: 4),
        ]
        return RoomModel(name: "Demo bathroom (5 × 8 ft)",
                         surfaces: [front, back, left, right, door, window],
                         objects: [tub, toilet, cabinet, sink],
                         marks: marks, items: items)
    }
}
