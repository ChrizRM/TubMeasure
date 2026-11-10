import Foundation
import RoomPlan
import simd

/// Converts RoomPlan's result into the app's own platform-independent model.
enum CapturedRoomConverter {
    static func box(transform: simd_float4x4, dimensions: simd_float3) -> OrientedBox {
        let xAxis = transform.columns.0
        let t = transform.columns.3
        return OrientedBox(center: Vec3(Double(t.x), Double(t.y), Double(t.z)),
                           size: Vec3(Double(dimensions.x), Double(dimensions.y), Double(dimensions.z)),
                           yaw: Double(atan2(-xAxis.z, xAxis.x)))
    }

    static func convert(_ room: CapturedRoom, name: String) -> RoomModel {
        var model = RoomModel(name: name)

        func add(_ surfaces: [CapturedRoom.Surface], as kind: SurfaceKind) {
            for s in surfaces {
                var isOpen: Bool?
                if case .door(let open) = s.category { isOpen = open }
                model.surfaces.append(Surface(id: s.identifier, kind: kind,
                                              box: box(transform: s.transform, dimensions: s.dimensions),
                                              parentID: s.parentIdentifier, isOpenDoor: isOpen))
            }
        }
        add(room.walls, as: .wall)
        add(room.doors, as: .door)
        add(room.windows, as: .window)
        add(room.openings, as: .opening)
        add(room.floors, as: .floor)

        for o in room.objects {
            model.objects.append(RoomObject(id: o.identifier, category: category(o.category),
                                            box: box(transform: o.transform, dimensions: o.dimensions)))
        }
        return model
    }

    static func category(_ c: CapturedRoom.Object.Category) -> ObjectCategory {
        switch c {
        case .toilet: return .toilet
        case .bathtub: return .bathtub
        case .sink: return .sink
        case .storage: return .storage
        case .chair: return .chair
        case .table: return .table
        case .washerDryer: return .washerDryer
        case .sofa: return .sofa
        case .bed: return .bed
        case .television: return .television
        case .refrigerator: return .refrigerator
        case .stove: return .stove
        case .oven: return .oven
        case .dishwasher: return .dishwasher
        case .fireplace: return .fireplace
        case .stairs: return .stairs
        @unknown default: return .other
        }
    }
}
