import SwiftUI

enum Theme {
    static func color(_ category: ObjectCategory) -> Color {
        switch category {
        case .toilet: return .purple
        case .bathtub: return .teal
        case .sink: return .blue
        case .storage: return .brown
        case .chair: return .orange
        default: return .gray
        }
    }

    static func color(_ kind: MarkKind) -> Color {
        switch kind {
        case .drain: return .red
        case .flangeBolt: return .orange
        case .tubEdge: return .green
        case .toiletSeat: return .pink
        case .shelfBottom: return .mint
        case .tileTop: return .cyan
        case .hallway: return .indigo
        case .extraDoor: return .purple
        case .custom: return .yellow
        }
    }

    static func color(_ kind: SurfaceKind) -> Color {
        switch kind {
        case .window: return .cyan
        case .door: return .indigo
        case .opening: return .mint
        default: return .primary
        }
    }

    static func letter(_ kind: MarkKind) -> String {
        switch kind {
        case .drain: return "D"
        case .flangeBolt: return "B"
        case .tubEdge: return "E"
        case .toiletSeat: return "S"
        case .shelfBottom: return "H"
        case .tileTop: return "T"
        case .hallway: return "W"
        case .extraDoor: return "O"
        case .custom: return "P"
        }
    }

    static func symbol(_ item: ItemCategory) -> String {
        switch item {
        case .chair: return "chair.fill"
        case .carpet: return "square.grid.3x3.fill"
        case .toiletries: return "drop.fill"
        case .showerCurtain: return "shower.fill"
        case .towel: return "rectangle.portrait.fill"
        case .bin: return "trash.fill"
        }
    }
}

/// Key for the hand-marked points, shown under the drawings.
struct MarkLegend: View {
    let room: RoomModel

    var body: some View {
        let kinds = MarkKind.allCases.filter { k in k.isInRoom && room.marks.contains { $0.kind == k } }
        if !kinds.isEmpty {
            HStack(spacing: 12) {
                ForEach(kinds) { kind in
                    HStack(spacing: 4) {
                        Circle().fill(Theme.color(kind)).frame(width: 9, height: 9)
                        Text(kind.displayName)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
