import Foundation

enum UnitSystem: String, CaseIterable, Codable, Identifiable {
    case imperial, metric

    var id: String { rawValue }
    var displayName: String { self == .imperial ? "in" : "cm" }
}

enum MeasureFormat {
    static let metresPerInch = 0.0254

    /// Formats a length in metres. Imperial rounds to the nearest 1/8 inch.
    static func length(_ metres: Double, _ units: UnitSystem) -> String {
        switch units {
        case .metric:
            return String(format: "%.1f cm", metres * 100)
        case .imperial:
            let inches = metres / metresPerInch
            let eighths = Int((abs(inches) * 8).rounded())
            let sign = inches < 0 && eighths > 0 ? "-" : ""
            let text = sign + inchesString(eighths: eighths)
            guard eighths >= 12 * 8 else { return text }
            let feet = eighths / (12 * 8)
            return "\(text) (\(sign)\(feet)' \(inchesString(eighths: eighths % (12 * 8))))"
        }
    }

    static func area(_ squareMetres: Double, _ units: UnitSystem) -> String {
        switch units {
        case .metric: return String(format: "%.2f m²", squareMetres)
        case .imperial: return String(format: "%.1f sq ft", squareMetres / (0.3048 * 0.3048))
        }
    }

    /// e.g. 499 eighths -> `62 3/8"`.
    static func inchesString(eighths: Int) -> String {
        let whole = eighths / 8
        var num = eighths % 8
        guard num != 0 else { return "\(whole)\"" }
        var den = 8
        while num % 2 == 0 {
            num /= 2
            den /= 2
        }
        return whole == 0 ? "\(num)/\(den)\"" : "\(whole) \(num)/\(den)\""
    }
}
