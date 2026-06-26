import Foundation
import Network
import Darwin
import StarIO10
import UIKit

struct DiscoveredPrinter: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var host: String
    var port: Int
    var model: String
    var macAddress: String
}

@MainActor
final class PrinterService: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var discoveredPrinters: [DiscoveredPrinter] = []
    @Published var savedPrinter: PrinterConfiguration?
    @Published var isSearching = false
    @Published var statusMessage = ""

    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private let defaultsKey = "panfitrion.savedPrinter"

    override init() {
        super.init()
    }

    func loadSavedPrinter() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(PrinterConfiguration.self, from: data)
        else { return }
        savedPrinter = config
    }

    func save(_ printer: DiscoveredPrinter) {
        let config = PrinterConfiguration(
            name: printer.name,
            host: printer.host,
            port: printer.port,
            model: printer.model,
            macAddress: printer.macAddress
        )
        savedPrinter = config
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func saveManual(host: String, port: Int = 9100, macAddress: String = "00:11:62:13:B5:00") {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMac = macAddress.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let config = PrinterConfiguration(name: "TSP100 III", host: cleanHost, port: port, model: "Star TSP100 III", macAddress: cleanMac)
        savedPrinter = config
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func startSearch() {
        stopBrowsers()
        discoveredPrinters.removeAll()
        services.removeAll()
        statusMessage = "Buscando impresoras en red..."
        isSearching = true
        let serviceTypes = [
            "_printer._tcp.",
            "_pdl-datastream._tcp.",
            "_star-prnt._tcp.",
            "_starpro._tcp."
        ]
        browsers = serviceTypes.map { type in
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.searchForServices(ofType: type, inDomain: "local.")
            return browser
        }
    }

    func stopSearch() {
        stopBrowsers()
        isSearching = false
        if discoveredPrinters.isEmpty {
            statusMessage = "No se encontraron impresoras. Captura la IP manual o revisa Wi-Fi."
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor in
            service.delegate = self
            services.append(service)
            service.resolve(withTimeout: 6)
            if !moreComing {
                statusMessage = "Resolviendo impresoras..."
            }
        }
    }

    nonisolated func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        Task { @MainActor in isSearching = false }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor in
            let host = ipv4Address(from: sender) ?? sender.hostName ?? sender.name
            let port = sender.port > 0 ? sender.port : 9100
            let mac = macAddress(from: sender)
            let printer = DiscoveredPrinter(name: sender.name, host: host, port: port, model: "LAN", macAddress: mac)
            if !discoveredPrinters.contains(where: { $0.host == printer.host && $0.port == printer.port }) {
                discoveredPrinters.append(printer)
            }
            statusMessage = "\(discoveredPrinters.count) impresora(s) encontradas"
        }
    }

    func printTest() async throws {
        let lines = [
            "PANFITRION",
            "Prueba de impresion",
            DateHelpers.displayFormatter.string(from: Date()),
            "TSP100 III LAN 9100",
            "MAC \(savedPrinter?.macAddress ?? "")",
            "",
            "OK"
        ]
        try await send(text: lines.joined(separator: "\n"))
    }

    func print(delivery: Delivery, cafeteria: Cafeteria, bakery: Bakery) async throws {
        var lines: [String] = []
        lines.append(bakery.name.uppercased())
        lines.append(DateHelpers.displayFormatter.string(from: delivery.date))
        lines.append("Folio: \(delivery.folio)")
        lines.append("Cafeteria: \(cafeteria.name)")
        lines.append("------------------------------")
        for item in delivery.items {
            lines.append("\(trim(item.quantity)) \(item.unit)  \(item.productName)")
        }
        lines.append("------------------------------")
        lines.append("Entrega recibida")
        lines.append("")
        try await send(text: lines.joined(separator: "\n"))
    }

    private func send(text: String) async throws {
        guard let printer = savedPrinter else {
            throw PrinterError.noPrinter
        }
        let identifier = printer.macAddress.isEmpty
            ? printer.host.trimmingCharacters(in: .whitespacesAndNewlines)
            : printer.macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = StarConnectionSettings(interfaceType: .lan, identifier: identifier)
        let starPrinter = StarPrinter(settings)
        try await starPrinter.open()
        defer {
            Task {
                await starPrinter.close()
            }
        }
        try await starPrinter.print(command: createImageTicketCommand(text: text))
    }

    private func stopBrowsers() {
        browsers.forEach { $0.stop() }
        browsers.removeAll()
    }

    private func macAddress(from service: NetService) -> String {
        guard let data = service.txtRecordData() else { return "" }
        let record = NetService.dictionary(fromTXTRecord: data)
        let candidates = ["mac", "macaddress", "MAC", "MACADDRESS", "usb_MFG"]
        for key in candidates {
            if let value = record[key], let text = String(data: value, encoding: .utf8), text.contains(":") {
                return text.uppercased()
            }
        }
        return ""
    }

    private func ipv4Address(from service: NetService) -> String? {
        service.addresses?.compactMap { data -> String? in
            data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return nil }
                let sockaddrPointer = base.assumingMemoryBound(to: sockaddr.self)
                guard sockaddrPointer.pointee.sa_family == UInt8(AF_INET) else { return nil }
                let sockaddrInPointer = base.assumingMemoryBound(to: sockaddr_in.self)
                var address = sockaddrInPointer.pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buffer)
            }
        }.first
    }

    private func createImageTicketCommand(text: String) -> String {
        let image = ticketImage(from: text)
        let builder = StarXpandCommand.StarXpandCommandBuilder()
        _ = builder.addDocument(StarXpandCommand.DocumentBuilder()
            .addPrinter(StarXpandCommand.PrinterBuilder()
                .actionPrintImage(StarXpandCommand.Printer.ImageParameter(image: image, width: 576))
                .actionFeedLine(2)
                .actionCut(StarXpandCommand.Printer.CutType.partial)
            )
        )
        return builder.getCommands()
    }

    private func ticketImage(from text: String) -> UIImage {
        let width: CGFloat = 576
        let margin: CGFloat = 24
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left
        let font = UIFont.monospacedSystemFont(ofSize: 28, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]
        let cleanText = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .joined(separator: "\n")
        let textRect = NSString(string: cleanText).boundingRect(
            with: CGSize(width: width - (margin * 2), height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let height = ceil(textRect.height) + margin * 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            NSString(string: cleanText).draw(
                in: CGRect(x: margin, y: margin, width: width - (margin * 2), height: height - (margin * 2)),
                withAttributes: attributes
            )
        }
    }

    private func trim(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.2f", value)
    }
}

enum PrinterError: LocalizedError {
    case noPrinter
    case timeout

    var errorDescription: String? {
        switch self {
        case .noPrinter:
            return "No hay impresora guardada."
        case .timeout:
            return "La impresora no respondió en 8 segundos."
        }
    }
}
