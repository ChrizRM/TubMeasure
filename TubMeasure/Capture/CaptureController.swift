import ARKit
import CoreImage
import RoomPlan
import SceneKit
import SwiftUI
import UIKit

/// Drives one scan from start to finish:
/// 1. `scanning`: RoomPlan sweeps the room with LiDAR.
/// 2. `marking`: the same AR session stays alive (so coordinates line up with
///    the scan) and the user marks drains, flange bolts and edges by aiming a crosshair.
@MainActor
final class CaptureController: NSObject, ObservableObject {
    enum Phase: Equatable {
        case scanning, processing, marking
        case failed(String)
    }

    @Published private(set) var phase: Phase = .scanning
    @Published private(set) var marks: [MarkedPoint] = []
    @Published private(set) var photoCount = 0
    @Published private(set) var liveItems: [DetectedItem] = []
    @Published var markError: String?

    /// Hosts the RoomPlan view while scanning and the AR view while marking.
    let containerView = UIView()

    static var isSupported: Bool { RoomCaptureSession.isSupported }
    static let maxPhotos = 12

    private let arSession = ARSession()
    private var roomCaptureView: RoomCaptureView?
    private var sceneView: ARSCNView?
    private var markNodes: [SCNNode] = []
    private var capturedRoom: CapturedRoom?
    private var photos: [Data] = []
    private let detector = ItemDetector()
    private let ciContext = CIContext()
    private var sampleTimer: Timer?
    private var started = false
    private var cancelled = false

    // MARK: - Scanning

    func start() {
        guard !started else { return }
        started = true
        guard Self.isSupported else {
            phase = .failed("This device has no LiDAR scanner. Scanning needs an iPhone Pro (12 Pro or later) or an iPad Pro.")
            return
        }
        containerView.backgroundColor = .black
        let view = RoomCaptureView(frame: containerView.bounds, arSession: arSession)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.captureSession.delegate = self
        containerView.addSubview(view)
        roomCaptureView = view
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())

        UIApplication.shared.isIdleTimerDisabled = true
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleFrame() }
        }
    }

    func finishScanning() {
        guard phase == .scanning else { return }
        phase = .processing
        // Keep the AR session running so marked points share the scan's coordinates.
        roomCaptureView?.captureSession.stop(pauseARSession: false)
    }

    func cancel() {
        cancelled = true
        sampleTimer?.invalidate()
        sampleTimer = nil
        if phase == .scanning { roomCaptureView?.captureSession.stop() }
        arSession.pause()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func process(_ data: CapturedRoomData) async {
        guard !cancelled else { return }
        do {
            let room = try await RoomBuilder(options: [.beautifyObjects]).capturedRoom(from: data)
            guard !cancelled else { return }
            capturedRoom = room
            enterMarking()
        } catch {
            phase = .failed("The scan could not be processed: \(error.localizedDescription)")
            arSession.pause()
        }
    }

    // MARK: - Marking

    private func enterMarking() {
        roomCaptureView?.removeFromSuperview()
        roomCaptureView = nil

        let view = ARSCNView(frame: containerView.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.session = arSession
        view.automaticallyUpdatesLighting = true
        containerView.addSubview(view)
        sceneView = view
        phase = .marking
    }

    /// Records the surface point under the centre crosshair.
    func addMark(_ kind: MarkKind) {
        guard let view = sceneView else { return }
        guard let p = pointUnderCrosshair(in: view) else {
            markError = "Couldn't find a surface there. Move a little closer (30–100 cm works best) and try again."
            return
        }
        markError = nil
        marks.append(MarkedPoint(kind: kind, position: Vec3(Double(p.x), Double(p.y), Double(p.z))))

        let sphere = SCNSphere(radius: 0.012)
        sphere.firstMaterial?.diffuse.contents = UIColor(Theme.color(kind))
        sphere.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: sphere)
        node.simdPosition = p
        view.scene.rootNode.addChildNode(node)
        markNodes.append(node)
    }

    func undoMark() {
        guard !marks.isEmpty else { return }
        marks.removeLast()
        markNodes.popLast()?.removeFromParentNode()
    }

    private func pointUnderCrosshair(in view: ARSCNView) -> simd_float3? {
        let centre = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        if let query = view.raycastQuery(from: centre, allowing: .estimatedPlane, alignment: .any),
           let hit = arSession.raycast(query).first {
            let t = hit.worldTransform.columns.3
            return simd_float3(t.x, t.y, t.z)
        }
        return depthPointAtImageCentre()
    }

    /// Fallback: read the LiDAR depth at the middle of the camera image.
    private func depthPointAtImageCentre() -> simd_float3? {
        guard let frame = arSession.currentFrame,
              let depthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap,
              CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let w = CVPixelBufferGetWidth(depthMap), h = CVPixelBufferGetHeight(depthMap)
        let row = base.advanced(by: (h / 2) * CVPixelBufferGetBytesPerRow(depthMap))
        let depth = row.assumingMemoryBound(to: Float32.self)[w / 2]
        guard depth.isFinite, depth > 0.05, depth < 8 else { return nil }

        // Unproject the centre pixel using intrinsics scaled to the depth map's resolution.
        let k = frame.camera.intrinsics
        let res = frame.camera.imageResolution
        let sx = Float(w) / Float(res.width), sy = Float(h) / Float(res.height)
        let xn = (Float(w) / 2 - k.columns.2.x * sx) / (k.columns.0.x * sx)
        let yn = (Float(h) / 2 - k.columns.2.y * sy) / (k.columns.1.y * sy)
        // Camera space: +X right, +Y up, looking down -Z (image Y points down).
        let world = frame.camera.transform * simd_float4(xn * depth, -yn * depth, -depth, 1)
        return simd_float3(world.x, world.y, world.z)
    }

    // MARK: - Photos and item detection

    func takePhoto() {
        guard photos.count < Self.maxPhotos, let frame = arSession.currentFrame else { return }
        let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let data = ciContext.jpegRepresentation(of: image, colorSpace: space) else { return }
        photos.append(data)
        photoCount = photos.count
    }

    private func sampleFrame() {
        guard phase == .scanning || phase == .marking, let frame = arSession.currentFrame else { return }
        detector.process(frame.capturedImage) { [weak self] items in
            self?.liveItems = items
        }
    }

    // MARK: - Result

    /// Builds the final model, writes photos and the USDZ next to it, and stops the session.
    func finish(name: String) -> RoomModel {
        var model = capturedRoom.map { CapturedRoomConverter.convert($0, name: name) } ?? RoomModel(name: name)
        model.marks = marks
        model.items = ItemAggregator.merge(camera: detector.items(), objects: model.objects)
        model = model.normalized()

        let folder = ScanStore.folder(for: model.id)
        for (i, data) in photos.enumerated() {
            let file = "photo-\(i + 1).jpg"
            if (try? data.write(to: folder.appendingPathComponent(file))) != nil {
                model.photoFileNames.append(file)
            }
        }
        if let room = capturedRoom {
            let url = folder.appendingPathComponent(ScanStore.usdzFile)
            try? FileManager.default.removeItem(at: url)
            model.hasUSDZ = (try? room.export(to: url, exportOptions: .parametric)) != nil
        }
        cancel()
        return model
    }
}

extension CaptureController: RoomCaptureSessionDelegate {
    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        Task { @MainActor in
            await self.process(data)
        }
    }
}
