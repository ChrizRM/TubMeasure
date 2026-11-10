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
        let pad = 48.0
        let w = max(bounds.max.x - bounds.min.x, 0.1)
        let h = max(bounds.max.y - bounds.min.y, 0.1)
        let scale = max(min((Double(size.width) - 2 * pad) / w, (Double(size.height) - 2 * pad) / h), 1)
        let ox = (Double(size.width) - w * scale) / 2
        let oy = (Double(size.height) - h * scale) / 2
        func pt(_ v: Vec2) -> CGPoint {
            CGPoint(x: ox + (v.x - bounds.min.x) * scale, y: oy + (v.y - bounds.min.y) * scale)
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

        for o in room.objects {
            let colour = Theme.color(o.category)
            let path = polygon(o.box.footprint)
            ctx.fill(path, with: .color(colour.opacity(0.22)))
            ctx.stroke(path, with: .color(colour), lineWidth: 1.5)
            ctx.draw(Text(o.category.displayName).font(.caption2).foregroundColor(colour), at: pt(o.box.center.plan))
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
            let p = pt(mid)
            let at = CGPoint(x: Double(p.x) + out.x * 24, y: Double(p.y) + out.y * 24)
            let text = Text("\(engine.label(wall))").font(.caption.bold())
                + Text("  \(MeasureFormat.length(wall.box.size.x, units))").font(.caption2)
            ctx.draw(text.foregroundColor(.secondary), at: at)
        }

        for m in room.marks {
            let p = pt(m.position.plan)
            let r: CGFloat = 6
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(dot, with: .color(Theme.color(m.kind)))
            ctx.stroke(dot, with: .color(.white), lineWidth: 1)
            ctx.draw(Text(Theme.letter(m.kind)).font(.system(size: 8, weight: .bold)).foregroundColor(.white), at: p)
        }
    }
}
