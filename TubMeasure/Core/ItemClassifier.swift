import Foundation

/// Maps image-classifier labels (e.g. "bath_mat", "shower curtain") onto the
/// loose-item categories the app reports.
enum ItemClassifier {
    private static let keywords: [(ItemCategory, Set<String>)] = [
        (.showerCurtain, ["curtain", "curtains", "drape", "drapes"]),
        (.carpet, ["rug", "rugs", "carpet", "carpets", "mat", "bathmat", "doormat"]),
        (.toiletries, ["toiletry", "toiletries", "soap", "shampoo", "toothbrush", "toothpaste", "razor", "lotion",
                       "cosmetic", "cosmetics", "makeup", "perfume", "deodorant", "hairbrush", "comb", "bottle",
                       "bottles", "dispenser", "sponge", "loofah", "tissue"]),
        (.towel, ["towel", "towels", "bathrobe", "robe", "washcloth"]),
        (.chair, ["chair", "chairs", "stool", "stools", "bench", "armchair"]),
        (.bin, ["bin", "wastebasket", "trashcan", "hamper", "basket", "bucket"]),
    ]

    static func category(forLabel label: String) -> ItemCategory? {
        let tokens = Set(label.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        if tokens.contains("toilet") && tokens.contains("paper") { return .toiletries }
        for (category, words) in keywords where !tokens.isDisjoint(with: words) {
            return category
        }
        return nil
    }
}

/// Collects classifier results across many camera frames so that one noisy
/// frame does not produce a detection.
struct ItemAggregator {
    var minConfidence = 0.15
    var minSightings = 2
    private var best: [ItemCategory: Double] = [:]
    private var counts: [ItemCategory: Int] = [:]

    init() {}

    /// Adds the labels seen in one frame.
    mutating func add(frame labels: [(label: String, confidence: Double)]) {
        var seen: [ItemCategory: Double] = [:]
        for l in labels where l.confidence >= minConfidence {
            guard let c = ItemClassifier.category(forLabel: l.label) else { continue }
            seen[c] = max(seen[c] ?? 0, l.confidence)
        }
        for (c, conf) in seen {
            counts[c, default: 0] += 1
            best[c] = max(best[c] ?? 0, conf)
        }
    }

    func items() -> [DetectedItem] {
        ItemCategory.allCases.compactMap { c in
            guard let n = counts[c], n >= minSightings else { return nil }
            return DetectedItem(category: c, source: .camera, confidence: best[c] ?? 0, sightings: n)
        }
    }

    /// Combines camera detections with objects the 3D scan recognised.
    /// A scanned chair is stronger evidence than a camera guess, so it wins.
    static func merge(camera: [DetectedItem], objects: [RoomObject]) -> [DetectedItem] {
        var out = camera
        let chairs = objects.filter { $0.category == .chair }.count
        if chairs > 0 {
            out.removeAll { $0.category == .chair }
            out.insert(DetectedItem(category: .chair, source: .scan, confidence: 1, sightings: chairs), at: 0)
        }
        return out
    }
}
