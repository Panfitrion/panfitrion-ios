import Foundation
import PDFKit
import UIKit

enum PDFService {
    static func generate(account: WeeklyAccount, bakery: Bakery, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeCafe = account.cafeteria.name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "cuenta-\(safeCafe)-\(DateHelpers.storageFormatter.string(from: account.weekStart)).pdf"
        let url = folder.appendingPathComponent(fileName)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            draw(account: account, bakery: bakery)
        }
        return url
    }

    private static func draw(account: WeeklyAccount, bakery: Bakery) {
        let margin: CGFloat = 36
        var y: CGFloat = 36
        let title = UIFont.boldSystemFont(ofSize: 26)
        let header = UIFont.boldSystemFont(ofSize: 14)
        let body = UIFont.systemFont(ofSize: 12)
        let small = UIFont.systemFont(ofSize: 10)

        drawText(bakery.name, x: margin, y: y, width: 340, font: title)
        drawText("Tel. \(formatPhone(bakery.phone))", x: 390, y: y, width: 180, font: body, align: .right)
        y += 30
        drawText(bakery.address.display, x: margin, y: y, width: 360, font: small)
        drawText(bakery.email, x: 390, y: y, width: 180, font: small, align: .right)
        y += 35

        drawText("Cuenta semanal", x: margin, y: y, width: 220, font: header)
        y += 22
        drawText("Cafetería: \(account.cafeteria.name)", x: margin, y: y, width: 330, font: body)
        drawText("Periodo: \(DateHelpers.periodLabel(weekStart: account.weekStart))", x: 300, y: y, width: 276, font: body, align: .right)
        y += 30

        drawLine(y: y)
        y += 10
        drawText("Fecha", x: margin, y: y, width: 90, font: header)
        drawText("Entrega", x: 130, y: y, width: 300, font: header)
        drawText("Subtotal", x: 470, y: y, width: 90, font: header, align: .right)
        y += 18
        drawLine(y: y)
        y += 8

        for delivery in account.deliveries {
            let products = delivery.items.map { "\(trim($0.quantity)) \($0.unit) \($0.productName)" }.joined(separator: ", ")
            drawText(DateHelpers.displayFormatter.string(from: delivery.date), x: margin, y: y, width: 90, font: body)
            drawText(products, x: 130, y: y, width: 300, font: body)
            drawText(currency(delivery.total), x: 470, y: y, width: 90, font: body, align: .right)
            y += max(22, height(for: products, width: 300, font: body) + 8)
            if y > 690 {
                drawText("Continúa en respaldo digital", x: margin, y: y, width: 300, font: small)
                break
            }
        }

        y = max(y + 20, 600)
        drawLine(y: y)
        y += 16
        summaryRow("Total semanal", currency(account.deliveriesTotal), y: &y, header: header, body: body)
        summaryRow("Deuda anterior", currency(account.previousDebt), y: &y, header: header, body: body)
        summaryRow("Pagos", currency(account.paid), y: &y, header: header, body: body)
        summaryRow("Saldo final", currency(account.balance), y: &y, header: UIFont.boldSystemFont(ofSize: 16), body: UIFont.boldSystemFont(ofSize: 16))
    }

    private static func summaryRow(_ label: String, _ value: String, y: inout CGFloat, header: UIFont, body: UIFont) {
        drawText(label, x: 350, y: y, width: 110, font: header)
        drawText(value, x: 470, y: y, width: 90, font: body, align: .right)
        y += 22
    }

    private static func drawText(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, font: UIFont, align: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        NSString(string: text).draw(in: CGRect(x: x, y: y, width: width, height: 80), withAttributes: attributes)
    }

    private static func drawLine(y: CGFloat) {
        UIColor.black.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 36, y: y))
        path.addLine(to: CGPoint(x: 576, y: y))
        path.stroke()
    }

    private static func height(for text: String, width: CGFloat, font: UIFont) -> CGFloat {
        NSString(string: text).boundingRect(
            with: CGSize(width: width, height: 1000),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font],
            context: nil
        ).height
    }

    private static func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "es_MX")
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private static func trim(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.2f", value)
    }

    private static func formatPhone(_ phone: String) -> String {
        phone == "+525521397371" ? "+52 55 2139 7371" : phone
    }
}

