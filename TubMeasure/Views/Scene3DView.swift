import SceneKit
import SwiftUI

/// Interactive 3D model: drag to orbit, pinch to zoom.
struct Scene3DView: View {
    @State private var scene: SCNScene

    init(room: RoomModel) {
        _scene = State(initialValue: Self.makeScene(room))
    }

    var body: some View {
        SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
    }

    private static func position(_ v: Vec3) -> SCNVector3 {
        SCNVector3(Float(v.x), Float(v.y), Float(v.z))
    }

    private static func boxNode(_ box: OrientedBox, minDepth: Double, colour: Color, opacity: CGFloat) -> SCNNode {
        let geometry = SCNBox(width: CGFloat(max(box.size.x, 0.005)), height: CGFloat(max(box.size.y, 0.005)),
                              length: CGFloat(max(box.size.z, minDepth)), chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(colour)
        material.transparency = opacity
        material.isDoubleSided = true
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = position(box.center)
        node.eulerAngles.y = Float(box.yaw)
        return node
    }

    static func makeScene(_ room: RoomModel) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.systemBackground
        let root = scene.rootNode
        let engine = MeasurementEngine(room: room)
        let bounds = room.planBounds
        let size = bounds.max - bounds.min
        let centre = (bounds.min + bounds.max) * 0.5
        let height = engine.roomDimensions()?.height ?? 2.4

        let floor = SCNBox(width: CGFloat(size.x), height: 0.01, length: CGFloat(size.y), chamferRadius: 0)
        floor.firstMaterial?.diffuse.contents = UIColor.systemGray4
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(Float(centre.x), Float(engine.floorY - 0.005), Float(centre.y))
        root.addChildNode(floorNode)

        for s in room.surfaces {
            switch s.kind {
            case .wall:
                root.addChildNode(boxNode(s.box, minDepth: 0.02, colour: .gray, opacity: 0.3))
            case .door, .window, .opening:
                root.addChildNode(boxNode(s.box, minDepth: 0.05, colour: Theme.color(s.kind), opacity: 0.75))
            case .floor:
                break
            }
        }
        for o in room.objects {
            root.addChildNode(boxNode(o.box, minDepth: 0.005, colour: Theme.color(o.category), opacity: 0.9))
        }
        for m in room.marks where m.kind.isInRoom {
            let sphere = SCNSphere(radius: 0.03)
            sphere.firstMaterial?.diffuse.contents = UIColor(Theme.color(m.kind))
            sphere.firstMaterial?.lightingModel = .constant
            let node = SCNNode(geometry: sphere)
            node.position = position(m.position)
            root.addChildNode(node)
        }

        let camera = SCNCamera()
        camera.zNear = 0.05
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let reach = Float(max(size.x, size.y, height)) * 1.4
        let target = SCNVector3(Float(centre.x), Float(engine.floorY + height / 2), Float(centre.y))
        cameraNode.position = SCNVector3(target.x + reach, target.y + reach, target.z + reach)
        cameraNode.look(at: target)
        root.addChildNode(cameraNode)
        return scene
    }
}
