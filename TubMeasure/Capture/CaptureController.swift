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
    /// Confirmation shown briefly after a photo is filed into the checklist.
    @Published private(set) var lastPhotoTitle: String?
    /// Units used when stamping measurements onto snapshots.
    var units: UnitSystem = .imperial

    /// Hosts the RoomPlan view while scanning and the AR view while marking.
    let containerView = UIView()

    static var isSupported: Bool { RoomCaptureSession.isSupported }

    private let arSession = ARSession()
    private var roomCaptureView: RoomCaptureView?
    private var sceneView: ARSCNView?
    private var markNodes: [SCNNode] = []
    private var capturedRoom: CapturedRoom?
    /// The scan converted to the app's model (in AR world coordinates), once processed.
    private var scannedModel: RoomModel?
    private var photos: [(photoID: String, data: Data)] = []
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
            scannedModel = CapturedRoomConverter.convert(room, name: "")
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

    /// Takes a photo and files it under a checklist item. While marking points, the photo is a
    /// snapshot of the AR view (with the marked dots) stamped with the matching measurements.
    func takePhoto(for photoID: String) {
        var image: UIImage?
        if phase == .marking, let view = sceneView {
            image = view.snapshot()
        } else if let frame = arSession.currentFrame {
            let ci = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
            if let cg = ciContext.createCGImage(ci, from: ci.extent) { image = UIImage(cgImage: cg) }
        }
        guard var photo = image else { return }
        if phase == .marking {
            var model = scannedModel ?? RoomModel(name: "")
            model.marks = marks
            photo = PhotoFiles.stamp(photo, lines: SurveyAutoFill.captions(forPhoto: photoID, room: model, units: units))
        }
        guard let data = PhotoFiles.jpeg(photo) else { return }
        photos.append((photoID, data))
        photoCount = photos.count

        let title = SurveyForm.photos.first { $0.id == photoID }?.title ?? "photos"
        lastPhotoTitle = "Saved to: \(title)"
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self?.lastPhotoTitle == "Saved to: \(title)" { self?.lastPhotoTitle = nil }
        }
    }

    private func sampleFrame() {
        guard phase == .scanning || phase == .marking, let frame = arSession.currentFrame else { return }
        detector.process(frame.capturedImage) { [weak self] items in
            self?.liveItems = items
        }
    }

    // MARK: - Result

    /// Puts the scan into an existing job, keeping its name, typed answers and earlier photos.
    /// Re-scanning replaces the room geometry and marked points.
    func finish(into job: RoomModel) -> RoomModel {
        var model = scannedModel ?? RoomModel(name: job.name)
        model.id = job.id
        model.name = job.name
        model.date = job.date
        model.survey = job.survey
        model.marks = marks
        model.items = ItemAggregator.merge(camera: detector.items(), objects: model.objects)
        model = model.normalized()

        for p in photos {
            if let file = PhotoFiles.write(p.data, jobID: model.id, photoID: p.photoID) {
                model.survey.photos[p.photoID, default: []].append(SurveyPhoto(fileName: file))
            }
        }
        if let room = capturedRoom {
            let url = ScanStore.folder(for: model.id).appendingPathComponent(ScanStore.usdzFile)
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
