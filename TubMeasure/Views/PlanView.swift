import SwiftUI

/// Top-down floor plan with wall labels, fixtures, openings and marked points.
struct PlanView: View {
    let room: RoomModel
    let units: UnitSystem

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                draw(&context, size)
            }
            if let d = MeasurementEngine(room: room).roomDimensions() {
                Text("\(MeasureFormat.length(d.length, units)) × \(MeasureFormat.length(d.width, units)) · ceiling \(MeasureFormat.length(d.height, units))")
                    .font(.footnote.monospacedDigit())
            }
            MarkLegend(room: room)
        }
        .padding()
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let engine = MeasurementEngine(room: room)
        let bounds = room.planBounds
        // Side margins leave room for the wall labels, which sit outside the walls.
        let padX = 92.0, padY = 40.0
        let roomW = max(bounds.max.x - bounds.min.x, 0.1)
        let roomH = max(bounds.max.y - bounds.min.y, 0.1)
        // Turn the plan a quarter turn when that lets it fill the space (a long room on a tall screen).
        let rotate = (roomW > roomH) != (size.width > size.height)
        let w = rotate ? roomH : roomW
        let h = rotate ? roomW : roomH
        let scale = max(min((Double(size.width) - 2 * padX) / w, (Double(size.height) - 2 * padY) / h), 1)
        let ox = (Double(size.width) - w * scale) / 2
        let oy = (Double(size.height) - h * scale) / 2
        /// Room plan coordinates to drawing coordinates, before scaling.
        func local(_ v: Vec2) -> Vec2 {
            let u = v.x - bounds.min.x, t = v.y - bounds.min.y
            return rotate ? Vec2(roomH - t, u) : Vec2(u, t)
        }
        /// A direction on the room plan, turned the same way as `local`.
        func turn(_ d: Vec2) -> Vec2 { rotate ? Vec2(-d.y, d.x) : d }
        func pt(_ v: Vec2) -> CGPoint {
            let l = local(v)
            return CGPoint(x: ox + l.x * scale, y: oy + l.y * scale)
        }
        func line(_ a: Vec2, _ b: Vec2) -> Path {
            var p = Path()
            p.move(to: pt(a))
            p.addLine(to: pt(b))
            return p
        }
        func polygon(_ pts: [Vec2]) -> Path {
            var p = Path()
            p.addLines(pts.map(pt))
            p.closeSubpath()
            return p
        }

        if let floor = engine.floorPolygon() {
            ctx.fill(polygon(floor), with: .color(.gray.opacity(0.08)))
        }

        // A sink standing in a cabinet is labelled once, as a vanity.
        let cabinets = room.objects.filter { $0.category == .storage }
        func isVanitySink(_ o: RoomObject) -> Bool {
            o.category == .sink && cabinets.contains { $0.box.contains(plan: o.box.center.plan, margin: 0.3) }
        }
        func isVanityCabinet(_ o: RoomObject) -> Bool {
            o.category == .storage && room.objects.contains { isVanitySink($0) && o.box.contains(plan: $0.box.center.plan, margin: 0.3) }
        }
        for o in room.objects {
            let colour = Theme.color(o.category)
            let path = polygon(o.box.footprint)
            ctx.fill(path, with: .color(colour.opacity(0.22)))
            ctx.stroke(path, with: .color(colour), lineWidth: 1.5)
            if isVanitySink(o) { continue }
            let name = isVanityCabinet(o) ? "Vanity" : o.category.displayName
            ctx.draw(Text(name).font(.caption2).foregroundColor(colour), at: pt(o.box.center.plan))
        }

        for wall in engine.walls {
            ctx.stroke(line(wall.start, wall.end), with: .color(.primary), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }

        let background = Color(uiColor: .systemBackground)
        for s in room.surfaces where s.kind == .door || s.kind == .window || s.kind == .opening {
            let path = line(s.start, s.end)
            ctx.stroke(path, with: .color(background), lineWidth: 7)
            let colour = Theme.color(s.kind)
            switch s.kind {
            case .window:
                ctx.stroke(path, with: .color(colour), lineWidth: 3)
            case .door:
                ctx.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
            default:
                ctx.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
            }
        }

        // Wall labels sit just outside the room, with each wall's length.
        let centre = (bounds.min + bounds.max) * 0.5
        for wall in engine.walls {
            let mid = wall.box.center.plan
            var out = wall.box.axisZ
            if out.dot(mid - centre) < 0 { out = out * -1 }
            out = turn(out)
            let p = pt(mid)
            let at = CGPoint(x: Double(p.x) + out.x * 12, y: Double(p.y) + out.y * 16)
            let text = Text("\(engine.label(wall))").font(.caption.bold())
                + Text("  \(MeasureFormat.length(wall.box.size.x, units))").font(.caption2)
            // Side-wall labels grow outward from the wall instead of straddling it.
            let anchor: UnitPoint = out.x > 0.5 ? .leading : out.x < -0.5 ? .trailing : .center
            ctx.draw(text.foregroundColor(.secondary), at: at, anchor: anchor)
        }

        for m in room.marks where m.kind.isInRoom {
            let p = pt(m.position.plan)
            let r: CGFloat = 6
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(dot, with: .color(Theme.color(m.kind)))
            ctx.stroke(dot, with: .color(.white), lineWidth: 1)
            ctx.draw(Text(Theme.letter(m.kind)).font(.system(size: 8, weight: .bold)).foregroundColor(.white), at: p)
        }
    }
}
