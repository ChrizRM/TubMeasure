import XCTest
@testable import TubMeasureCore

final class MeasurementTests: XCTestCase {
    let inch = 0.0254

    private func value(_ title: String, in room: RoomModel, file: StaticString = #filePath, line: UInt = #line) -> Double {
        let all = MeasurementEngine(room: room).all()
        guard let m = all.first(where: { $0.title == title }), let v = m.metres else {
            XCTFail("No length measurement titled '\(title)'. Have: \(all.map(\.title))", file: file, line: line)
            return .nan
        }
        return v
    }

    func testRoomDimensions() {
        let room = RoomModel.sample()
        XCTAssertEqual(value("Room length", in: room), 96 * inch, accuracy: 1e-3)
        XCTAssertEqual(value("Room width", in: room), 60 * inch, accuracy: 1e-3)
        XCTAssertEqual(value("Room height (floor to ceiling)", in: room), 96 * inch, accuracy: 1e-3)
        let engine = MeasurementEngine(room: room)
        let poly = engine.floorPolygon()
        XCTAssertNotNil(poly)
        XCTAssertEqual(Geometry.polygonArea(poly ?? []), 1.524 * 2.438, accuracy: 1e-3)
    }

    func testFlangeRoughIn() {
        let room = RoomModel.sample()
        let engine = MeasurementEngine(room: room)
        let left = engine.walls.first { abs($0.box.center.x) < 1e-6 }!
        let l = engine.label(left)
        XCTAssertEqual(value("Rough-in (bolt centreline → wall \(l))", in: room), 12 * inch, accuracy: 1e-3)
        XCTAssertEqual(value("Bolt spacing", in: room), 6 * inch, accuracy: 1e-3)
        XCTAssertTrue(MeasurementEngine.roughInNote(12.2 * inch).contains("12 in"))
        XCTAssertTrue(MeasurementEngine.roughInNote(10.3 * inch).contains("10 in"))
    }

    func testBackWallPrefersWallParallelToBolts() {
        // Toilet squeezed into a corner: the side wall is nearer than the back wall.
        var room = RoomModel.sample()
        room.marks = [
            MarkedPoint(kind: .flangeBolt, position: Vec3(0.3556, 0, 0.20 - 0.0762)),
            MarkedPoint(kind: .flangeBolt, position: Vec3(0.3556, 0, 0.20 + 0.0762)),
        ]
        let engine = MeasurementEngine(room: room)
        let wall = engine.backWall(forBolts: room.marks.map { $0.position.plan })
        XCTAssertEqual(wall?.box.center.x ?? 99, 0, accuracy: 1e-6, "back wall should be x = 0, not the nearer z = 0 wall")
    }

    func testToiletHeights() {
        let room = RoomModel.sample()
        XCTAssertEqual(value("Toilet overall height", in: room), 0.75, accuracy: 1e-3)
        XCTAssertEqual(value("Seat height (marked)", in: room), 0.42, accuracy: 1e-3)
    }

    func testDrainToTubEdge() {
        let room = RoomModel.sample()
        XCTAssertEqual(value("Drain centre → closest tub edge", in: room), 0.25, accuracy: 1e-3)
        XCTAssertEqual(value("Tub length", in: room), 60 * inch, accuracy: 1e-3)
        XCTAssertEqual(value("Tub width", in: room), 30 * inch, accuracy: 1e-3)
    }

    func testDrainToMarkedShowerEdge() {
        var room = RoomModel.sample()
        room.objects.removeAll { $0.category == .bathtub }
        room.marks += [
            MarkedPoint(kind: .tubEdge, position: Vec3(0, 0.1, 1.7)),
            MarkedPoint(kind: .tubEdge, position: Vec3(1.524, 0.1, 1.7)),
        ]
        XCTAssertEqual(value("Drain centre → closest marked edge", in: room), 2.438 - 0.381 - 1.7, accuracy: 1e-3)
    }

    func testWindowAndDoor() {
        let room = RoomModel.sample()
        XCTAssertEqual(value("Window width", in: room), 0.61, accuracy: 1e-3)
        XCTAssertEqual(value("Window height", in: room), 0.61, accuracy: 1e-3)
        XCTAssertEqual(value("Window sill height above floor", in: room), 1.6 - 0.305, accuracy: 1e-3)
        XCTAssertEqual(value("Door opening width", in: room), 30 * inch, accuracy: 1e-3)
        XCTAssertEqual(value("Door opening height", in: room), 80 * inch, accuracy: 1e-3)
        // Door spans x 0.619…1.381 on the 1.524 m front wall.
        let all = MeasurementEngine(room: room).all()
        let sides = all.filter { $0.title.hasPrefix("Door side →") }.compactMap(\.metres).sorted()
        XCTAssertEqual(sides.count, 2)
        XCTAssertEqual(sides[0], 1.524 - 1.381, accuracy: 1e-3)
        XCTAssertEqual(sides[1], 0.619, accuracy: 1e-3)
    }

    func testVanity() {
        let room = RoomModel.sample()
        XCTAssertEqual(value("Vanity width", in: room), 0.61, accuracy: 1e-3)
        XCTAssertEqual(value("Vanity depth", in: room), 0.54, accuracy: 1e-3)
        XCTAssertEqual(value("Vanity cabinet height", in: room), 0.86, accuracy: 1e-3)
        let all = MeasurementEngine(room: room).all()
        let sides = all.filter { $0.title.hasPrefix("Vanity side →") }.compactMap(\.metres).sorted()
        XCTAssertEqual(sides[0], 0.45 - 0.305, accuracy: 1e-3)
    }

    func testMeasurementsSurviveArbitraryWorldOrientation() {
        // AR world axes are arbitrary: spin and shift the room, then normalise.
        var room = RoomModel.sample()
        let phi = 0.7, c = cos(phi), s = sin(phi)
        func move(_ p: Vec3) -> Vec3 { Vec3(p.x * c + p.z * s + 3, p.y - 1.2, -p.x * s + p.z * c - 5) }
        for i in room.surfaces.indices {
            room.surfaces[i].box.center = move(room.surfaces[i].box.center)
            room.surfaces[i].box.yaw += phi
        }
        for i in room.objects.indices {
            room.objects[i].box.center = move(room.objects[i].box.center)
            room.objects[i].box.yaw += phi
        }
        for i in room.marks.indices { room.marks[i].position = move(room.marks[i].position) }

        for candidate in [room, room.normalized()] {
            XCTAssertEqual(value("Room length", in: candidate), 96 * inch, accuracy: 1e-3)
            XCTAssertEqual(value("Bolt spacing", in: candidate), 6 * inch, accuracy: 1e-3)
            XCTAssertEqual(value("Drain centre → closest tub edge", in: candidate), 0.25, accuracy: 1e-3)
            XCTAssertEqual(value("Toilet overall height", in: candidate), 0.75, accuracy: 1e-3)
            XCTAssertEqual(value("Window sill height above floor", in: candidate), 1.295, accuracy: 1e-3)
        }
        let n = room.normalized()
        let b = n.planBounds
        XCTAssertEqual(b.min.x, 0, accuracy: 1e-6)
        XCTAssertEqual(b.min.y, 0, accuracy: 1e-6)
        XCTAssertEqual(b.max.x, 2.438, accuracy: 1e-3, "longest wall should lie along X after normalising")
        XCTAssertEqual(MeasurementEngine(room: n).floorY, 0, accuracy: 1e-9)
    }

    func testOpenRoomFallsBackToBoundingArea() {
        var room = RoomModel.sample()
        let wallID = room.walls[0].id
        room.surfaces.removeAll { $0.id == wallID }
        XCTAssertNil(MeasurementEngine(room: room).floorPolygon())
        XCTAssertFalse(MeasurementEngine(room: room).all().isEmpty)
    }

    func testEmptyRoomProducesNothing() {
        XCTAssertTrue(MeasurementEngine(room: RoomModel(name: "empty")).all().isEmpty)
        _ = RoomModel(name: "empty").normalized()
    }

    func testFormatting() {
        XCTAssertEqual(MeasureFormat.length(12 * inch, .imperial), "12\" (1' 0\")")
        XCTAssertEqual(MeasureFormat.length(62.375 * inch, .imperial), "62 3/8\" (5' 2 3/8\")")
        XCTAssertEqual(MeasureFormat.length(5.5 * inch, .imperial), "5 1/2\"")
        XCTAssertEqual(MeasureFormat.length(0.25 * inch, .imperial), "1/4\"")
        XCTAssertEqual(MeasureFormat.length(11.97 * inch, .imperial), "12\" (1' 0\")")
        XCTAssertEqual(MeasureFormat.length(1.584, .metric), "158.4 cm")
        XCTAssertEqual(MeasureFormat.area(0.3048 * 0.3048 * 40, .imperial), "40.0 sq ft")
    }

    func testItemClassification() {
        XCTAssertEqual(ItemClassifier.category(forLabel: "shower_curtain"), .showerCurtain)
        XCTAssertEqual(ItemClassifier.category(forLabel: "bath mat"), .carpet)
        XCTAssertEqual(ItemClassifier.category(forLabel: "Rug"), .carpet)
        XCTAssertEqual(ItemClassifier.category(forLabel: "toothbrush"), .toiletries)
        XCTAssertEqual(ItemClassifier.category(forLabel: "toilet_paper"), .toiletries)
        XCTAssertEqual(ItemClassifier.category(forLabel: "folding_chair"), .chair)
        XCTAssertNil(ItemClassifier.category(forLabel: "tomato"), "'mat' must match whole words only")
        XCTAssertNil(ItemClassifier.category(forLabel: "bathroom"))
    }

    func testItemAggregationNeedsRepeatSightings() {
        var agg = ItemAggregator()
        agg.add(frame: [("rug", 0.6), ("towel", 0.05)])
        XCTAssertTrue(agg.items().isEmpty, "one frame is not enough")
        agg.add(frame: [("bath_mat", 0.4), ("towel", 0.05)])
        let items = agg.items()
        XCTAssertEqual(items.map(\.category), [.carpet])
        XCTAssertEqual(items.first?.confidence ?? 0, 0.6, accuracy: 1e-9)

        let merged = ItemAggregator.merge(camera: items, objects: [
            RoomObject(category: .chair, box: OrientedBox(center: Vec3(0, 0, 0), size: Vec3(0.4, 0.9, 0.4), yaw: 0)),
        ])
        XCTAssertEqual(merged.map(\.category), [.chair, .carpet])
        XCTAssertEqual(merged.first?.source, .scan)
    }

    func testReportAndCodableRoundTrip() throws {
        let room = RoomModel.sample()
        let text = Report.text(for: room, units: .imperial)
        XCTAssertTrue(text.contains("Rough-in"))
        XCTAssertTrue(text.contains("Shower curtain"))
        let data = try JSONEncoder().encode(room)
        XCTAssertEqual(try JSONDecoder().decode(RoomModel.self, from: data), room)
    }

    func testIsoProjection() {
        let iso = IsoProjector()
        XCTAssertEqual(iso.project(Vec3(0, 1, 0)).y, -1, accuracy: 1e-9, "up in the room is up the screen")
        XCTAssertGreaterThan(iso.depth(Vec3(1, 0, 1)), iso.depth(Vec3(0, 0, 0)))
        let turned = IsoProjector(quarterTurns: 4)
        XCTAssertEqual(turned.project(Vec3(1, 0, 2)), iso.project(Vec3(1, 0, 2)))
    }
}
