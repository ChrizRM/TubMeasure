import SwiftUI
import UIKit

/// Builds the two PDFs the office asks for, in the same order as its forms.
@MainActor
enum SurveyPDF {
    static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter, points
    static let margin: CGFloat = 36

    static func measurements(for room: RoomModel, units: UnitSystem) throws -> URL {
        let url = fileURL(room, suffix: "Measurements")
        let resolver = SurveyResolver(room: room)
        let engine = MeasurementEngine(room: room)
        try UIGraphicsPDFRenderer(bounds: pageRect).writePDF(to: url) { ctx in
            let page = PDFPage(ctx)
            page.header("Bathroom measurements", room: room)

            page.section("Property information and measurements")
            for field in resolver.visibleFields {
                let a = resolver.answer(field)
                page.row(field.title, a.value ?? "—", note: a.source == .scan ? "from scan" : nil)
            }

            if !room.walls.isEmpty, let plan = planImage(room, units: units) {
                page.section("Current bathroom diagram")
                page.image(plan, maxWidth: page.contentWidth, maxHeight: 420)
            }

            let all = engine.all()
            if !all.isEmpty {
                page.section("All scan measurements")
                for group in MeasurementGroup.allCases {
                    let rows = all.filter { $0.group == group }
                    guard !rows.isEmpty else { continue }
                    page.subheading(group.title)
                    for m in rows { page.row(m.title, m.value.formatted(units), note: nil) }
                }
            }

            if !room.items.isEmpty {
                page.section("Loose items to clear before install")
                for item in room.items { page.row(item.category.displayName, item.source.displayName, note: nil) }
            }
            page.space(10)
            page.paragraph("Scan measurements are typically within about 1–2 cm (1/2 in). Confirm critical dimensions with a tape.",
                           font: .italicSystemFont(ofSize: 9), color: .darkGray)
        }
        return url
    }

    static func photos(for room: RoomModel) throws -> URL {
        let url = fileURL(room, suffix: "Photos")
        try UIGraphicsPDFRenderer(bounds: pageRect).writePDF(to: url) { ctx in
            let page = PDFPage(ctx)
            page.header("Bathroom photos", room: room)
            for item in SurveyForm.photos {
                let files = room.survey.photos[item.id] ?? []
                let skip = room.survey.photoSkips[item.id] ?? ""
                let note = room.survey.photoNotes[item.id] ?? ""
                if !item.required && files.isEmpty && note.isEmpty { continue }

                page.section(item.title)
                if files.isEmpty {
                    page.paragraph(skip.isEmpty ? "Not taken" : skip, font: .systemFont(ofSize: 20, weight: .regular),
                                   color: skip.isEmpty ? .systemRed : .black)
                } else {
                    let images = files.compactMap { PhotoFiles.image(jobID: room.id, fileName: $0.fileName) }
                    page.imageGrid(images)
                }
                if !note.isEmpty {
                    page.paragraph(note, font: .systemFont(ofSize: 14, weight: .medium), color: .black)
                }
            }
        }
        return url
    }

    private static func fileURL(_ room: RoomModel, suffix: String) -> URL {
        let safe = room.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(safe) - \(suffix).pdf")
    }

    private static func planImage(_ room: RoomModel, units: UnitSystem) -> UIImage? {
        let view = PlanView(room: room, units: units)
            .frame(width: 540, height: 420)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// Flowing layout onto PDF pages: keeps a cursor and starts a new page when one fills up.
@MainActor
private final class PDFPage {
    let ctx: UIGraphicsPDFRendererContext
    private var y: CGFloat = 0
    private var pageNumber = 0
    let left = SurveyPDF.margin
    var contentWidth: CGFloat { SurveyPDF.pageRect.width - 2 * SurveyPDF.margin }
    private var bottom: CGFloat { SurveyPDF.pageRect.height - SurveyPDF.margin - 14 }

    init(_ ctx: UIGraphicsPDFRendererContext) {
        self.ctx = ctx
        newPage()
    }

    private func newPage() {
        ctx.beginPage()
        pageNumber += 1
        y = SurveyPDF.margin
        let footer = "Page \(pageNumber) · TubMeasure" as NSString
        footer.draw(at: CGPoint(x: left, y: SurveyPDF.pageRect.height - SurveyPDF.margin),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray])
    }

    private func ensure(_ height: CGFloat) {
        if y + height > bottom { newPage() }
    }

    func space(_ h: CGFloat) { y += h }

    private func height(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        ceil((text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin], attributes: [.font: font], context: nil).height)
    }

    private func draw(_ text: String, font: UIFont, color: UIColor, x: CGFloat, width: CGFloat, align: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        (text as NSString).draw(with: CGRect(x: x, y: y, width: width, height: height(text, font: font, width: width) + 2),
                                options: [.usesLineFragmentOrigin],
                                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style], context: nil)
    }

    func header(_ title: String, room: RoomModel) {
        draw(title.uppercased(), font: .systemFont(ofSize: 20, weight: .bold), color: UIColor(red: 0.75, green: 0.1, blue: 0.1, alpha: 1),
             x: left, width: contentWidth)
        y += 30
        let info = room.survey.info
        var lines = [info.customerName.isEmpty ? room.name : info.customerName]
        if !info.address.isEmpty { lines.append(info.address) }
        if !info.prospectNumber.isEmpty { lines.append("Prospect # \(info.prospectNumber)") }
        lines.append("Date: \(room.date.formatted(date: .numeric, time: .omitted))")
        let text = lines.joined(separator: "\n")
        let h = height(text, font: .systemFont(ofSize: 11), width: contentWidth - 16) + 16
        UIColor.black.setStroke()
        UIBezierPath(rect: CGRect(x: left, y: y, width: contentWidth, height: h)).stroke()
        y += 8
        draw(text, font: .systemFont(ofSize: 11), color: .black, x: left + 8, width: contentWidth - 16)
        y += h
    }

    func section(_ title: String) {
        ensure(60)
        y += 14
        draw(title, font: .systemFont(ofSize: 13, weight: .bold), color: .black, x: left, width: contentWidth)
        y += 18
        UIColor.black.setFill()
        UIRectFill(CGRect(x: left, y: y, width: contentWidth, height: 1))
        y += 3
    }

    func subheading(_ title: String) {
        ensure(30)
        y += 6
        draw(title, font: .systemFont(ofSize: 10, weight: .semibold), color: .darkGray, x: left, width: contentWidth)
        y += 14
    }

    func row(_ label: String, _ value: String, note: String?) {
        let labelWidth = contentWidth * 0.66
        let valueWidth = contentWidth - labelWidth - 8
        let labelFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let valueFont = UIFont.systemFont(ofSize: 10)
        let valueText = note.map { "\(value)\n\($0)" } ?? value
        let h = max(height(label, font: labelFont, width: labelWidth), height(valueText, font: valueFont, width: valueWidth)) + 8
        ensure(h)
        y += 4
        draw(label, font: labelFont, color: .black, x: left + 2, width: labelWidth)
        draw(value, font: valueFont, color: .black, x: left + labelWidth + 8, width: valueWidth - 2, align: .right)
        if let note {
            let noteY = y + height(value, font: valueFont, width: valueWidth)
            let saved = y
            y = noteY
            draw(note, font: .italicSystemFont(ofSize: 8), color: .gray, x: left + labelWidth + 8, width: valueWidth - 2, align: .right)
            y = saved
        }
        y += h - 4
        UIColor(white: 0.85, alpha: 1).setFill()
        UIRectFill(CGRect(x: left, y: y, width: contentWidth, height: 0.5))
    }

    func paragraph(_ text: String, font: UIFont, color: UIColor) {
        let h = height(text, font: font, width: contentWidth)
        ensure(h + 8)
        y += 6
        draw(text, font: font, color: color, x: left, width: contentWidth)
        y += h + 2
    }

    func image(_ image: UIImage, maxWidth: CGFloat, maxHeight: CGFloat) {
        let size = fit(image.size, maxWidth: maxWidth, maxHeight: maxHeight)
        ensure(size.height + 8)
        y += 6
        image.draw(in: CGRect(x: left + (contentWidth - size.width) / 2, y: y, width: size.width, height: size.height))
        y += size.height
    }

    /// Two photos per row, each up to 300 pt tall.
    func imageGrid(_ images: [UIImage]) {
        let gap: CGFloat = 12
        let cell = (contentWidth - gap) / 2
        for start in stride(from: 0, to: images.count, by: 2) {
            let rowImages = Array(images[start..<min(start + 2, images.count)])
            let sizes = rowImages.map { fit($0.size, maxWidth: rowImages.count == 1 ? contentWidth : cell, maxHeight: 300) }
            let rowHeight = sizes.map(\.height).max() ?? 0
            ensure(rowHeight + 10)
            y += 8
            if rowImages.count == 1 {
                rowImages[0].draw(in: CGRect(x: left + (contentWidth - sizes[0].width) / 2, y: y, width: sizes[0].width, height: sizes[0].height))
            } else {
                for (i, img) in rowImages.enumerated() {
                    let x = left + CGFloat(i) * (cell + gap) + (cell - sizes[i].width) / 2
                    img.draw(in: CGRect(x: x, y: y, width: sizes[i].width, height: sizes[i].height))
                }
            }
            y += rowHeight
        }
    }

    private func fit(_ size: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let s = min(maxWidth / size.width, maxHeight / size.height)
        return CGSize(width: size.width * s, height: size.height * s)
    }
}
