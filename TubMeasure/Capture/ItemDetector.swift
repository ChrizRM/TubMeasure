import CoreVideo
import Foundation
import ImageIO
import Vision

/// Runs Apple's on-device image classifier over sampled camera frames and
/// keeps a running tally of loose items (rugs, shower curtains, toiletries…).
/// This tells you an item was seen, not where it is.
final class ItemDetector {
    private let queue = DispatchQueue(label: "tubmeasure.item-detector", qos: .utility)
    private var aggregator = ItemAggregator()
    private var busy = false

    /// Classifies one frame in the background. Frames that arrive while busy are skipped.
    func process(_ pixelBuffer: CVPixelBuffer, completion: @escaping ([DetectedItem]) -> Void) {
        queue.async { [self] in
            guard !busy else { return }
            busy = true
            defer { busy = false }

            let request = VNClassifyImageRequest()
            // ARKit delivers landscape sensor images; the phone is held upright.
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return
            }
            let labels = (request.results ?? []).map { (label: $0.identifier, confidence: Double($0.confidence)) }
            aggregator.add(frame: labels)
            let items = aggregator.items()
            DispatchQueue.main.async { completion(items) }
        }
    }

    func items() -> [DetectedItem] {
        queue.sync { aggregator.items() }
    }
}
