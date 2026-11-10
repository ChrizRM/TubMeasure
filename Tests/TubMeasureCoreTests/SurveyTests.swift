import XCTest
@testable import TubMeasureCore

final class SurveyTests: XCTestCase {
    func testAutoFillFromSampleRoom() {
        let r = SurveyResolver(room: .sample())
        XCTAssertEqual(r.value("roomSize"), "96x60x96")
        XCTAssertEqual(r.value("doorwayWidth"), "30")
        XCTAssertEqual(r.value("existingTub"), "30x60x20")
        XCTAssertEqual(r.value("tubArea"), "30x60x75")
        XCTAssertEqual(r.value("toilet"), "Yes")
        XCTAssertEqual(r.value("shelfAboveToilet"), "Yes")
        XCTAssertEqual(r.value("shelfHeight"), "50")
        XCTAssertEqual(r.value("hallway"), "Yes")
        XCTAssertEqual(r.value("hallwayWidth"), "32")
        XCTAssertEqual(r.value("otherDoors"), "Yes, 1 additional door")
        XCTAssertEqual(r.value("otherDoor1Width"), "28")
        XCTAssertNil(r.value("gateCode"))
    }

    func testToiletDrainToTubEdge() {
        // Bolt midpoint is at z = 1.25 m; the tub's outer edge is at z = 2.438 - 0.762.
        let e = MeasurementEngine(room: .sample())
        let t = e.toiletDrainToTubEdge()
        XCTAssertEqual(t?.distance ?? 0, (2.438 - 0.762) - 1.25, accuracy: 1e-3)
        XCTAssertEqual(t?.estimated, false)

        var noBolts = RoomModel.sample()
        noBolts.marks.removeAll { $0.kind == .flangeBolt }
        let est = MeasurementEngine(room: noBolts).toiletDrainToTubEdge()
        XCTAssertEqual(est?.estimated, true)
        XCTAssertNotNil(SurveyResolver(room: noBolts).auto["toiletToTub"]?.detail)
    }

    func testDrainSide() {
        // Facing the tub on the far wall (looking along +z), the drain at low x is on the viewer's right.
        XCTAssertEqual(MeasurementEngine(room: .sample()).drainSide(), "Right")

        var room = RoomModel.sample()
        room.marks = room.marks.map { m in
            var m = m
            if m.kind == .drain { m.position.x = 1.524 - 0.25 }
            return m
        }
        XCTAssertEqual(MeasurementEngine(room: room).drainSide(), "Left")
        room.marks = room.marks.map { m in
            var m = m
            if m.kind == .drain { m.position.x = 0.762 }
            return m
        }
        XCTAssertEqual(MeasurementEngine(room: room).drainSide(), "Center")
    }

    func testManualAnswerOverridesScan() {
        var room = RoomModel.sample()
        room.survey.answers["doorwayWidth"] = "24"
        let a = SurveyResolver(room: room).answer(SurveyForm.field("doorwayWidth")!)
        XCTAssertEqual(a.value, "24")
        XCTAssertEqual(a.source, .manual)
        XCTAssertEqual(a.detail, "Scan measured 30")
    }

    func testConditionalFields() {
        var room = RoomModel(name: "empty")
        var r = SurveyResolver(room: room)
        let ids = { (r: SurveyResolver) in Set(r.visibleFields.map(\.id)) }
        XCTAssertFalse(ids(r).contains("floorAccess"), "hidden until the floor is answered")
        XCTAssertFalse(ids(r).contains("otherDoor1Width"))

        room.survey.answers["floor"] = "Second"
        room.survey.answers["floorAccess"] = "Other"
        room.survey.answers["otherDoors"] = "Yes, 2 additional doors"
        r = SurveyResolver(room: room)
        XCTAssertTrue(ids(r).isSuperset(of: ["floorAccess", "floorAccessOther", "otherDoor1Width", "otherDoor2Width"]))
        XCTAssertFalse(ids(r).contains("otherDoor3Width"))

        room.survey.answers["floor"] = "First"
        XCTAssertFalse(ids(SurveyResolver(room: room)).contains("floorAccess"))
    }

    func testProgressAndFormText() {
        var room = RoomModel.sample()
        room.survey.photos["room"] = [SurveyPhoto(fileName: "a.jpg")]
        room.survey.photoSkips["customers"] = "Requested no photos"
        let r = SurveyResolver(room: room)
        XCTAssertEqual(r.photoProgress.done, 2)
        XCTAssertEqual(r.photoProgress.total, SurveyForm.photos.count - 1)
        XCTAssertGreaterThan(r.formProgress.done, 5)
        let text = r.formText()
        XCTAssertTrue(text.contains("Overall Measurement of the Room where we are Installing the Tub (Inches L x W x H): 96x60x96"))
        XCTAssertTrue(text.contains("Gate Code: —"))
        // Form order is kept.
        XCTAssertLessThan(text.range(of: "Residence")!.lowerBound, text.range(of: "Gate Code")!.lowerBound)
    }

    func testCaptions() {
        let room = RoomModel.sample()
        let rough = SurveyAutoFill.captions(forPhoto: "roughIn", room: room, units: .imperial)
        XCTAssertTrue(rough.contains { $0.contains("Rough-in") && $0.contains("12\"") }, "\(rough)")
        let drain = SurveyAutoFill.captions(forPhoto: "tubDrain", room: room, units: .imperial)
        XCTAssertTrue(drain.contains { $0.contains("right") })
        XCTAssertTrue(SurveyAutoFill.captions(forPhoto: "breakers", room: room, units: .imperial).isEmpty)
    }

    func testFieldIDsAreUnique() {
        XCTAssertEqual(Set(SurveyForm.fields.map(\.id)).count, SurveyForm.fields.count)
        XCTAssertEqual(Set(SurveyForm.photos.map(\.id)).count, SurveyForm.photos.count)
        for f in SurveyForm.fields {
            if case .oneOf(let dep, _) = f.showIf { XCTAssertNotNil(SurveyForm.field(dep), f.id) }
            if case .noneOf(let dep, _) = f.showIf { XCTAssertNotNil(SurveyForm.field(dep), f.id) }
        }
    }

    func testSurveyRoundTrips() throws {
        var room = RoomModel.sample()
        room.survey.info.customerName = "Test Customer"
        room.survey.answers["gateCode"] = "1234"
        let data = try JSONEncoder().encode(room)
        XCTAssertEqual(try JSONDecoder().decode(RoomModel.self, from: data), room)
    }
}
