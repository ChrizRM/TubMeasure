import SwiftUI

/// Isometric drawing of the room. Walls nearest the viewer are drawn as
/// outlines so the fixtures inside stay visible.
struct IsoView: View {
    let room: RoomModel
    @State private var turns = 0

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                draw(&context, size)
            }
            HStack {
                MarkLegend(room: room)
                Spacer()
                Button {
                    turns = (turns + 1) % 4
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private func quad(_ s: Surface) -> [Vec3] {
        let a = s.start, b = s.end
        return [Vec3(a.x, s.box.bottomY, a.y), Vec3(b.x, s.box.bottomY, b.y),
                Vec3(b.x, s.box.topY, b.y), Vec3(a.x, s.box.topY, a.y)]
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let engine = MeasurementEngine(room: room)
        let bounds = room.planBounds
        let pivot = (bounds.min + bounds.max) * 0.5
        let iso = IsoProjector(quarterTurns: turns, pivot: pivot)

        var all: [Vec3] = room.surfaces.filter { $0.kind != .floor }.flatMap(quad)
        all += room.objects.flatMap { $0.box.corners }
        let projected = all.map(iso.project)
        guard let first = projected.first else { return }
        var lo = first, hi = first
        for p in projected {
            lo = Vec2(min(lo.x, p.x), min(lo.y, p.y))
            hi = Vec2(max(hi.x, p.x), max(hi.y, p.y))
        }
        let pad = 16.0
        let w = max(hi.x - lo.x, 0.1), h = max(hi.y - lo.y, 0.1)
        let scale = max(min((Double(size.width) - 2 * pad) / w, (Double(size.height) - 2 * pad) / h), 1)
        let ox = (Double(size.width) - w * scale) / 2
        let oy = (Double(size.height) - h * scale) / 2
        func pt(_ v: Vec3) -> CGPoint {
            let p = iso.project(v)
            return CGPoint(x: ox + (p.x - lo.x) * scale, y: oy + (p.y - lo.y) * scale)
        }
        func polygon(_ pts: [Vec3]) -> Path {
            var p = Path()
            p.addLines(pts.map(pt))
            p.closeSubpath()
            return p
        }
        func isNear(_ s: Surface) -> Bool {
            iso.depth(s.box.center) > iso.depth(Vec3(pivot.x, s.box.center.y, pivot.y))
        }

        // Floor
        let floorY = engine.floorY
        let floorOutline = engine.floorPolygon()
            ?? [bounds.min, Vec2(bounds.max.x, bounds.min.y), bounds.max, Vec2(bounds.min.x, bounds.max.y)]
        ctx.fill(polygon(floorOutline.map { Vec3($0.x, floorY, $0.y) }), with: .color(.gray.opacity(0.15)))

        // Far walls and what is set into them
        let insets = room.surfaces.filter { $0.kind == .door || $0.kind == .window || $0.kind == .opening }
        for wall in engine.walls where !isNear(wall) {
            let path = polygon(quad(wall))
            ctx.fill(path, with: .color(.gray.opacity(0.18)))
            ctx.stroke(path, with: .color(.primary.opacity(0.6)), lineWidth: 1)
        }
        for s in insets where !isNear(s) {
            let path = polygon(quad(s))
            ctx.fill(path, with: .color(Theme.color(s.kind).opacity(0.35)))
            ctx.stroke(path, with: .color(Theme.color(s.kind)), lineWidth: 1.5)
        }

        // Fixtures, back to front
        let objects = room.objects.sorted { iso.depth($0.box.center) < iso.depth($1.box.center) }
        for o in objects {
            let c = o.box.corners
            var faces: [[Vec3]] = [[c[4], c[5], c[6], c[7]]]
            for k in 0..<4 {
                let n = (k + 1) % 4
                faces.append([c[k], c[n], c[n + 4], c[k + 4]])
            }
            func faceDepth(_ f: [Vec3]) -> Double { f.reduce(0) { $0 + iso.depth($1) } / Double(f.count) }
            let colour = Theme.color(o.category)
            for (i, f) in faces.enumerated().sorted(by: { faceDepth($0.element) < faceDepth($1.element) }) {
                let path = polygon(f)
                ctx.fill(path, with: .color(Color(uiColor: .systemBackground)))
                ctx.fill(path, with: .color(colour.opacity(i == 0 ? 0.35 : 0.55)))
                ctx.stroke(path, with: .color(colour), lineWidth: 1)
            }
            let top = Vec3(o.box.center.x, o.box.topY, o.box.center.z)
            ctx.draw(Text(o.category.displayName).font(.caption2.bold()), at: pt(top))
        }

        // Marked points
        for m in room.marks {
            let p = pt(m.position)
            let r: CGFloat = 5
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(dot, with: .color(Theme.color(m.kind)))
            ctx.stroke(dot, with: .color(.white), lineWidth: 1)
        }

        // Near walls as outlines only
        for wall in engine.walls where isNear(wall) {
            ctx.stroke(polygon(quad(wall)), with: .color(.primary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        for s in insets where isNear(s) {
            ctx.stroke(polygon(quad(s)), with: .color(Theme.color(s.kind).opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
    }
}
