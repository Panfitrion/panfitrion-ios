import Foundation
import SwiftUI

@MainActor
final class PanfitrionStore: ObservableObject {
    @Published private(set) var database = AppDatabase.empty
    @Published var lastError: String?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    var bakery: Bakery { database.bakery }
    var activeCafeterias: [Cafeteria] { database.cafeterias.filter(\.isActive).sorted { $0.name < $1.name } }
    var activeProducts: [Product] { database.products.filter(\.isActive).sorted { $0.name < $1.name } }
    var documentsURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    var databaseURL: URL { documentsURL.appendingPathComponent("panfitrion-db.json") }
    var pdfsURL: URL { documentsURL.appendingPathComponent("PDFs", isDirectory: true) }
    var backupsURL: URL { documentsURL.appendingPathComponent("Backups", isDirectory: true) }

    func load() async {
        do {
            try ensureFolders()
            if FileManager.default.fileExists(atPath: databaseURL.path) {
                let data = try Data(contentsOf: databaseURL)
                database = try decoder.decode(AppDatabase.self, from: data)
            } else {
                database = .empty
                try save()
            }
        } catch {
            lastError = "No se pudo cargar la base: \(error.localizedDescription)"
            database = .empty
        }
    }

    func save() throws {
        try ensureFolders()
        let data = try encoder.encode(database)
        try data.write(to: databaseURL, options: .atomic)
    }

    func price(for productId: String, cafeteriaId: String) -> Double {
        database.cafeteriaPrices.first { $0.productId == productId && $0.cafeteriaId == cafeteriaId }?.price ?? 0
    }

    func upsertCafeteria(_ cafeteria: Cafeteria) {
        if let index = database.cafeterias.firstIndex(where: { $0.id == cafeteria.id }) {
            database.cafeterias[index] = cafeteria
        } else {
            database.cafeterias.append(cafeteria)
        }
        persistQuietly()
    }

    func upsertProduct(_ product: Product) {
        if let index = database.products.firstIndex(where: { $0.id == product.id }) {
            database.products[index] = product
        } else {
            database.products.append(product)
        }
        persistQuietly()
    }

    func setPrice(productId: String, cafeteriaId: String, price: Double) {
        if let index = database.cafeteriaPrices.firstIndex(where: { $0.productId == productId && $0.cafeteriaId == cafeteriaId }) {
            database.cafeteriaPrices[index].price = price
        } else {
            database.cafeteriaPrices.append(CafeteriaPrice(cafeteriaId: cafeteriaId, productId: productId, price: price))
        }
        persistQuietly()
    }

    func createDelivery(cafeteriaId: String, date: Date, itemQuantities: [String: Double]) -> Delivery {
        let items = activeProducts.compactMap { product -> DeliveryItem? in
            let quantity = itemQuantities[product.id] ?? 0
            guard quantity > 0 else { return nil }
            return DeliveryItem(
                id: UUID().uuidString,
                productId: product.id,
                productName: product.name,
                quantity: quantity,
                unit: product.unit,
                unitPrice: price(for: product.id, cafeteriaId: cafeteriaId)
            )
        }
        let nextFolio = (database.deliveries.map(\.folio).max() ?? 0) + 1
        let delivery = Delivery(
            id: UUID().uuidString,
            folio: nextFolio,
            cafeteriaId: cafeteriaId,
            date: DateHelpers.startOfDay(date),
            items: items,
            printedAt: nil,
            printStatus: .notPrinted,
            editedAfterPrint: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        database.deliveries.append(delivery)
        persistQuietly()
        return delivery
    }

    func updateDelivery(_ delivery: Delivery, newItems: [DeliveryItem]) {
        guard let index = database.deliveries.firstIndex(where: { $0.id == delivery.id }) else { return }
        var updated = delivery
        updated.items = newItems
        updated.updatedAt = Date()
        if updated.printedAt != nil {
            updated.editedAfterPrint = true
        }
        database.deliveries[index] = updated
        persistQuietly()
    }

    func markPrintResult(deliveryId: String, success: Bool) {
        guard let index = database.deliveries.firstIndex(where: { $0.id == deliveryId }) else { return }
        database.deliveries[index].printStatus = success ? .printed : .failed
        if success {
            database.deliveries[index].printedAt = Date()
        }
        database.deliveries[index].updatedAt = Date()
        persistQuietly()
    }

    func deliveries(on date: Date) -> [Delivery] {
        database.deliveries
            .filter { DateHelpers.isSameDay($0.date, date) }
            .sorted { $0.folio > $1.folio }
    }

    func deliveries(for cafeteriaId: String, weekStart: Date) -> [Delivery] {
        database.deliveries
            .filter { $0.cafeteriaId == cafeteriaId && DateHelpers.isDate($0.date, inWeekStarting: weekStart) }
            .sorted { $0.date < $1.date || ($0.date == $1.date && $0.folio < $1.folio) }
    }

    func account(for cafeteria: Cafeteria, weekStart: Date) -> WeeklyAccount {
        let normalizedStart = DateHelpers.weekStart(for: weekStart)
        let priorDeliveries = database.deliveries
            .filter { $0.cafeteriaId == cafeteria.id && DateHelpers.startOfDay($0.date) < normalizedStart }
            .reduce(0) { $0 + $1.total }
        let priorPayments = database.payments
            .filter { $0.cafeteriaId == cafeteria.id && DateHelpers.startOfDay($0.weekStart) < normalizedStart }
            .reduce(0) { $0 + $1.amount }
        let payments = database.payments
            .filter { $0.cafeteriaId == cafeteria.id && DateHelpers.startOfDay($0.weekStart) == normalizedStart }
        return WeeklyAccount(
            cafeteria: cafeteria,
            weekStart: normalizedStart,
            weekEnd: DateHelpers.weekEnd(for: normalizedStart),
            deliveries: deliveries(for: cafeteria.id, weekStart: normalizedStart),
            previousDebt: max(0, priorDeliveries - priorPayments),
            payments: payments
        )
    }

    func addPayment(cafeteriaId: String, weekStart: Date, amount: Double, note: String) {
        let payment = Payment(
            id: UUID().uuidString,
            cafeteriaId: cafeteriaId,
            weekStart: DateHelpers.weekStart(for: weekStart),
            amount: amount,
            date: Date(),
            note: note
        )
        database.payments.append(payment)
        persistQuietly()
    }

    func markPaid(account: WeeklyAccount) {
        guard account.balance > 0 else { return }
        addPayment(cafeteriaId: account.cafeteria.id, weekStart: account.weekStart, amount: account.balance, note: "Cuenta pagada")
    }

    func generatePDF(for account: WeeklyAccount) throws -> URL {
        let url = try PDFService.generate(account: account, bakery: database.bakery, in: pdfsURL)
        let record = GeneratedPDF(
            id: UUID().uuidString,
            cafeteriaId: account.cafeteria.id,
            weekStart: account.weekStart,
            fileName: url.lastPathComponent,
            total: account.balance,
            createdAt: Date()
        )
        database.generatedPDFs.append(record)
        try save()
        return url
    }

    func exportBackup() throws -> URL {
        try ensureFolders()
        let folder = backupsURL.appendingPathComponent("panfitrion-backup-\(DateHelpers.timestampFormatter.string(from: Date()))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let backupURL = folder.appendingPathComponent("backup.json")
        let data = try encoder.encode(database)
        try data.write(to: backupURL, options: .atomic)
        if FileManager.default.fileExists(atPath: pdfsURL.path) {
            let pdfDestination = folder.appendingPathComponent("PDFs", isDirectory: true)
            try FileManager.default.createDirectory(at: pdfDestination, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: pdfsURL, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension.lowercased() == "pdf" {
                try? FileManager.default.copyItem(at: file, to: pdfDestination.appendingPathComponent(file.lastPathComponent))
            }
        }
        return folder
    }

    func importCatalog(from data: Data) throws {
        let catalog = try decoder.decode(CatalogImport.self, from: data)
        guard catalog.version == 1 else {
            throw ImportError.invalidVersion
        }
        guard !catalog.cafeterias.isEmpty, !catalog.products.isEmpty else {
            throw ImportError.emptyCatalog
        }
        database.bakery = catalog.bakery
        database.cafeterias = catalog.cafeterias
        database.products = catalog.products
        database.cafeteriaPrices = catalog.cafeteriaPrices
        try save()
    }

    func sampleCatalogData() throws -> Data {
        let catalog = CatalogImport(
            version: 1,
            bakery: database.bakery,
            cafeterias: database.cafeterias,
            products: database.products,
            cafeteriaPrices: database.cafeteriaPrices
        )
        return try encoder.encode(catalog)
    }

    func savePrinter(_ printer: PrinterConfiguration?) {
        database.printer = printer
        persistQuietly()
    }

    private func ensureFolders() throws {
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pdfsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
    }

    private func persistQuietly() {
        do {
            try save()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

enum ImportError: LocalizedError {
    case invalidVersion
    case emptyCatalog

    var errorDescription: String? {
        switch self {
        case .invalidVersion: return "El JSON debe tener version 1."
        case .emptyCatalog: return "El JSON necesita al menos una cafetería y un producto."
        }
    }
}

