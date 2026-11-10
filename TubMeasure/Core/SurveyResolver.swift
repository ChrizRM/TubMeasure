import Foundation

struct AutoValue: Hashable {
    var value: String
    var detail: String?
}

enum AnswerSource {
    case manual, scan, none
}

struct ResolvedAnswer {
    var field: SurveyField
    var value: String?
    var source: AnswerSource
    var detail: String?
}

/// Combines hand-entered answers with what the scan measured.
struct SurveyResolver {
    let room: RoomModel
    let auto: [String: AutoValue]

    init(room: RoomModel) {
        self.room = room
        auto = SurveyAutoFill.values(for: room)
    }

    func answer(_ field: SurveyField) -> ResolvedAnswer {
        if let manual = room.survey.answers[field.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !manual.isEmpty {
            return ResolvedAnswer(field: field, value: manual, source: .manual, detail: auto[field.id].map { "Scan measured \($0.value)" })
        }
        if let a = auto[field.id] {
            return ResolvedAnswer(field: field, value: a.value, source: .scan, detail: a.detail)
        }
        return ResolvedAnswer(field: field, value: nil, source: .none, detail: nil)
    }

    func value(_ id: String) -> String? {
        SurveyForm.field(id).flatMap { answer($0).value }
    }

    /// Follow-up questions only show when the question they depend on has the matching answer.
    func isVisible(_ field: SurveyField) -> Bool {
        guard let condition = field.showIf else { return true }
        switch condition {
        case .oneOf(let id, let values):
            guard let v = value(id) else { return false }
            return values.contains(v)
        case .noneOf(let id, let values):
            guard let v = value(id) else { return false }
            return !values.contains(v)
        }
    }

    var visibleFields: [SurveyField] { SurveyForm.fields.filter(isVisible) }

    var formProgress: (done: Int, total: Int) {
        let visible = visibleFields
        return (visible.filter { answer($0).value != nil }.count, visible.count)
    }

    func photoDone(_ item: PhotoItem) -> Bool {
        !(room.survey.photos[item.id] ?? []).isEmpty || !(room.survey.photoSkips[item.id] ?? "").isEmpty
    }

    var photoProgress: (done: Int, total: Int) {
        let required = SurveyForm.photos.filter(\.required)
        return (required.filter(photoDone).count, required.count)
    }

    /// The answers in form order, one "question: answer" per line, ready to paste.
    func formText() -> String {
        visibleFields.map { "\($0.title): \(answer($0).value ?? "—")" }.joined(separator: "\n")
    }
}

/// Fills form answers from the scan and the hand-marked points.
enum SurveyAutoFill {
    static func inches(_ metres: Double) -> String { String(Int((metres / MeasureFormat.metresPerInch).rounded())) }

    static func values(for room: RoomModel) -> [String: AutoValue] {
        let e = MeasurementEngine(room: room)
        var out: [String: AutoValue] = [:]
        let exact = { (m: Double) in MeasureFormat.length(m, .imperial) }

        if let d = e.roomDimensions() {
            out["roomSize"] = AutoValue(value: "\(inches(d.length))x\(inches(d.width))x\(inches(d.height))",
                                        detail: "\(exact(d.length)) × \(exact(d.width)) × \(exact(d.height))")
        }

        var doors = room.surfaces.filter { $0.kind == .door }
        if doors.isEmpty { doors = room.surfaces.filter { $0.kind == .opening } }
        if let widest = doors.max(by: { $0.box.size.x < $1.box.size.x }) {
            out["doorwayWidth"] = AutoValue(value: inches(widest.box.size.x),
                                            detail: doors.count > 1 ? "Widest of \(doors.count) doors found (\(exact(widest.box.size.x)))" : exact(widest.box.size.x))
        }

        if let tub = room.objects.first(where: { $0.category == .bathtub }) {
            let depth = min(tub.box.size.x, tub.box.size.z)
            let length = max(tub.box.size.x, tub.box.size.z)
            let rim = tub.box.topY - e.floorY
            out["existingTub"] = AutoValue(value: "\(inches(depth))x\(inches(length))x\(inches(rim))",
                                           detail: "Depth \(exact(depth)), length \(exact(length)), rim \(exact(rim))")
            if let tile = room.marks.first(where: { $0.kind == .tileTop }) {
                let h = tile.position.y - e.floorY
                out["tubArea"] = AutoValue(value: "\(inches(depth))x\(inches(length))x\(inches(h))",
                                           detail: "Tub footprint, height to the marked top of tile. Check if shelving makes the area larger.")
            }
        }

        if let side = e.drainSide() {
            out["drainSide"] = AutoValue(value: side, detail: "From the marked drain, standing in front of the tub")
        }

        let hasToilet = room.objects.contains { $0.category == .toilet } || room.marks.contains { $0.kind == .flangeBolt }
        if hasToilet {
            out["toilet"] = AutoValue(value: SurveyForm.yes, detail: "Found in the scan")
        } else if !room.walls.isEmpty {
            out["toilet"] = AutoValue(value: SurveyForm.no, detail: "No toilet found in the scan")
        }
        if let t = e.toiletDrainToTubEdge() {
            out["toiletToTub"] = AutoValue(value: inches(t.distance),
                                           detail: t.estimated ? "Estimated from the toilet's shape. Mark the flange bolts for an accurate figure." : exact(t.distance))
        }

        if let shelf = room.marks.first(where: { $0.kind == .shelfBottom }) {
            let h = shelf.position.y - e.floorY
            out["shelfAboveToilet"] = AutoValue(value: SurveyForm.yes, detail: "Shelf bottom was marked")
            out["shelfHeight"] = AutoValue(value: inches(h), detail: h < 34 * MeasureFormat.metresPerInch ? "Below the 34\" minimum" : exact(h))
        }

        if let hall = e.pairDistances(.hallway).first {
            out["hallway"] = AutoValue(value: SurveyForm.yes, detail: "Hallway width was marked")
            out["hallwayWidth"] = AutoValue(value: inches(hall), detail: exact(hall))
        }

        let doorWidths = e.pairDistances(.extraDoor)
        if !doorWidths.isEmpty {
            out["otherDoors"] = AutoValue(value: SurveyForm.otherDoorChoices[min(doorWidths.count, 3)],
                                          detail: "\(doorWidths.count) other door(s) marked")
            for (i, w) in doorWidths.prefix(3).enumerated() {
                out["otherDoor\(i + 1)Width"] = AutoValue(value: inches(w), detail: exact(w))
            }
        }
        return out
    }

    /// Lines stamped onto a snapshot taken for a given checklist photo.
    static func captions(forPhoto id: String, room: RoomModel, units: UnitSystem) -> [String] {
        let e = MeasurementEngine(room: room)
        let f = { (m: Double) in MeasureFormat.length(m, units) }
        var lines: [String] = []
        switch id {
        case "tubDrain":
            let all = e.tubMeasurements()
            for m in all where m.title.contains("closest") {
                if let v = m.metres { lines.append("\(m.title): \(f(v))") }
            }
            if let side = e.drainSide() { lines.append("Drain on the \(side.lowercased()) (facing the tub)") }
        case "roughIn":
            for m in e.toiletMeasurements() where m.title.contains("Rough-in") || m.title.contains("Bolt spacing") {
                if let v = m.metres { lines.append("\(m.title): \(f(v))") }
            }
        case "toiletToTub":
            if let t = e.toiletDrainToTubEdge() {
                lines.append("Toilet drain centre → tub/shower edge: \(f(t.distance))\(t.estimated ? " (estimated)" : "")")
            }
        case "doorInterior", "doorExterior":
            if let d = room.surfaces.filter({ $0.kind == .door }).max(by: { $0.box.size.x < $1.box.size.x }) {
                lines.append("Door opening: \(f(d.box.size.x)) wide × \(f(d.box.size.y)) high")
            }
        case "window":
            for w in room.surfaces where w.kind == .window {
                lines.append("Window: \(f(w.box.size.x)) wide × \(f(w.box.size.y)) high, sill \(f(w.box.bottomY - e.floorY)) above floor")
            }
        case "room", "tubEntire":
            if let d = e.roomDimensions() {
                lines.append("Room: \(f(d.length)) × \(f(d.width)) × \(f(d.height)) high")
            }
            if id == "tubEntire", let tub = room.objects.first(where: { $0.category == .bathtub }) {
                lines.append("Tub: \(f(max(tub.box.size.x, tub.box.size.z))) × \(f(min(tub.box.size.x, tub.box.size.z)))")
            }
        case "vanity":
            for m in e.vanityMeasurements() where m.title.hasSuffix("width") || m.title.hasSuffix("depth") {
                if let v = m.metres { lines.append("\(m.title): \(f(v))") }
            }
        default:
            break
        }
        return lines
    }
}
