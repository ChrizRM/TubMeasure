import Foundation

enum Report {
    /// Plain-text summary suitable for sharing with a contractor or supplier.
    static func text(for room: RoomModel, units: UnitSystem) -> String {
        let engine = MeasurementEngine(room: room)
        let all = engine.all()
        var lines = ["TubMeasure report: \(room.name)", ""]
        for group in MeasurementGroup.allCases {
            let rows = all.filter { $0.group == group }
            guard !rows.isEmpty else { continue }
            lines.append(group.title.uppercased())
            for r in rows {
                lines.append("  \(r.title): \(r.value.formatted(units))")
                if let note = r.note { lines.append("      (\(note))") }
            }
            lines.append("")
        }
        lines.append("LOOSE ITEMS NOTICED")
        if room.items.isEmpty {
            lines.append("  None detected.")
        } else {
            for item in room.items {
                lines.append("  \(item.category.displayName) — \(item.source.displayName)")
            }
        }
        lines.append("")
        lines.append("LiDAR measurements are typically within about 1–2 cm (1/2 in). Confirm critical dimensions with a tape before ordering or cutting.")
        return lines.joined(separator: "\n")
    }
}
