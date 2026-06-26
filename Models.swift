import Foundation

struct Bakery: Codable, Equatable {
    var name: String
    var email: String
    var phone: String
    var address: BakeryAddress
    var logoFileName: String

    static let panfitrion = Bakery(
        name: "Panfitrión",
        email: "atencion@panfitrion.com.mx",
        phone: "+525521397371",
        address: BakeryAddress(
            street: "Dakota 410",
            neighborhood: "Ampliación Nápoles",
            postalCode: "03840",
            city: "CDMX",
            country: "MX"
        ),
        logoFileName: "panfitrion-logo.png"
    )
}

struct BakeryAddress: Codable, Equatable {
    var street: String
    var neighborhood: String
    var postalCode: String
    var city: String
    var country: String

    var display: String {
        "\(street), \(neighborhood), \(postalCode), \(city)"
    }
}

struct Cafeteria: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var contactName: String
    var phone: String
    var email: String
    var address: String
    var isActive: Bool
}

struct Product: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var unit: String
    var isActive: Bool
}

struct CafeteriaPrice: Codable, Identifiable, Equatable {
    var cafeteriaId: String
    var productId: String
    var price: Double

    var id: String { "\(cafeteriaId)-\(productId)" }
}

struct Delivery: Codable, Identifiable, Equatable {
    var id: String
    var folio: Int
    var cafeteriaId: String
    var date: Date
    var items: [DeliveryItem]
    var printedAt: Date?
    var printStatus: PrintStatus
    var editedAfterPrint: Bool
    var createdAt: Date
    var updatedAt: Date

    var total: Double {
        items.reduce(0) { $0 + ($1.quantity * $1.unitPrice) }
    }
}

struct DeliveryItem: Codable, Identifiable, Equatable {
    var id: String
    var productId: String
    var productName: String
    var quantity: Double
    var unit: String
    var unitPrice: Double

    var subtotal: Double { quantity * unitPrice }
}

enum PrintStatus: String, Codable, CaseIterable {
    case notPrinted
    case printed
    case failed

    var label: String {
        switch self {
        case .notPrinted: return "No impreso"
        case .printed: return "Impreso"
        case .failed: return "Error impresión"
        }
    }
}

struct Payment: Codable, Identifiable, Equatable {
    var id: String
    var cafeteriaId: String
    var weekStart: Date
    var amount: Double
    var date: Date
    var note: String
}

struct GeneratedPDF: Codable, Identifiable, Equatable {
    var id: String
    var cafeteriaId: String
    var weekStart: Date
    var fileName: String
    var total: Double
    var createdAt: Date
}

struct PrinterConfiguration: Codable, Equatable {
    var name: String
    var host: String
    var port: Int
    var model: String
    var macAddress: String
}

struct AppDatabase: Codable, Equatable {
    var version: Int
    var bakery: Bakery
    var cafeterias: [Cafeteria]
    var products: [Product]
    var cafeteriaPrices: [CafeteriaPrice]
    var deliveries: [Delivery]
    var payments: [Payment]
    var generatedPDFs: [GeneratedPDF]
    var printer: PrinterConfiguration?

    static let empty = AppDatabase(
        version: 1,
        bakery: .panfitrion,
        cafeterias: [
            Cafeteria(id: "caf_001", name: "Cafetería ejemplo", contactName: "", phone: "", email: "", address: "", isActive: true)
        ],
        products: [
            Product(id: "prod_001", name: "Croissant", unit: "pieza", isActive: true)
        ],
        cafeteriaPrices: [
            CafeteriaPrice(cafeteriaId: "caf_001", productId: "prod_001", price: 25)
        ],
        deliveries: [],
        payments: [],
        generatedPDFs: [],
        printer: nil
    )
}

struct CatalogImport: Codable {
    var version: Int
    var bakery: Bakery
    var cafeterias: [Cafeteria]
    var products: [Product]
    var cafeteriaPrices: [CafeteriaPrice]
}

struct WeeklyAccount: Identifiable, Equatable {
    var id: String { "\(cafeteria.id)-\(DateHelpers.storageFormatter.string(from: weekStart))" }
    var cafeteria: Cafeteria
    var weekStart: Date
    var weekEnd: Date
    var deliveries: [Delivery]
    var previousDebt: Double
    var payments: [Payment]

    var deliveriesTotal: Double { deliveries.reduce(0) { $0 + $1.total } }
    var paid: Double { payments.reduce(0) { $0 + $1.amount } }
    var balance: Double { previousDebt + deliveriesTotal - paid }
    var isPaid: Bool { balance <= 0.009 }
}

