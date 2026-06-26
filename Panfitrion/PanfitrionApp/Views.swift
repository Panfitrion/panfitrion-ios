import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: PanfitrionStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HomeLink(title: "Pedidos", icon: "shippingbox.fill", color: .orange, destination: OrdersView())
                    HomeLink(title: "Entregas", icon: "list.clipboard.fill", color: .blue, destination: DeliveriesView())
                    HomeLink(title: "Cuentas", icon: "doc.text.fill", color: .green, destination: AccountsView())
                    HomeLink(title: "Pagos", icon: "creditcard.fill", color: .purple, destination: PaymentsView())
                    HomeLink(title: "Base de datos", icon: "externaldrive.fill", color: .brown, destination: DatabaseView())
                    HomeLink(title: "Respaldos", icon: "square.and.arrow.up.fill", color: .teal, destination: BackupsView())
                    HomeLink(title: "Impresora", icon: "printer.fill", color: .gray, destination: PrinterSettingsView())
                }
            }
            .navigationTitle("Panfitrión")
            .alert("Error", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }
}

struct HomeLink<Destination: View>: View {
    var title: String
    var icon: String
    var color: Color
    var destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .padding(.vertical, 10)
        }
    }
}

struct OrdersView: View {
    @EnvironmentObject private var store: PanfitrionStore
    @EnvironmentObject private var printer: PrinterService
    @State private var selectedCafeteriaId = ""
    @State private var selectedDate = DateHelpers.startOfDay(Date())
    @State private var quantities: [String: String] = [:]
    @State private var message = ""

    var selectedCafeteria: Cafeteria? {
        store.activeCafeterias.first { $0.id == selectedCafeteriaId } ?? store.activeCafeterias.first
    }

    var body: some View {
        Form {
            Section("Día") {
                HStack {
                    Button { selectedDate = DateHelpers.addDays(-1, to: selectedDate) } label: {
                        Image(systemName: "chevron.left.circle.fill").font(.title2)
                    }
                    Spacer()
                    Text(DateHelpers.displayFormatter.string(from: selectedDate)).font(.headline)
                    Spacer()
                    Button { selectedDate = DateHelpers.addDays(1, to: selectedDate) } label: {
                        Image(systemName: "chevron.right.circle.fill").font(.title2)
                    }
                }
            }

            Section("Cafetería") {
                Picker("Cafetería", selection: $selectedCafeteriaId) {
                    ForEach(store.activeCafeterias) { cafeteria in
                        Text(cafeteria.name).tag(cafeteria.id)
                    }
                }
            }

            Section("Productos") {
                ForEach(store.activeProducts) { product in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(product.name).font(.headline)
                            Text(product.unit).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("0", text: binding(for: product.id))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title3)
                            .frame(width: 90)
                    }
                }
            }

            Section {
                Button("Guardar entrega e imprimir") {
                    Task { await saveAndPrint() }
                }
                .disabled(selectedCafeteria == nil || parsedQuantities().isEmpty)
                Button("Guardar sin imprimir") {
                    saveOnly()
                }
                .disabled(selectedCafeteria == nil || parsedQuantities().isEmpty)
            }

            if !message.isEmpty {
                Section { Text(message) }
            }
        }
        .navigationTitle("Pedidos")
        .onAppear {
            if selectedCafeteriaId.isEmpty {
                selectedCafeteriaId = store.activeCafeterias.first?.id ?? ""
            }
        }
    }

    private func binding(for productId: String) -> Binding<String> {
        Binding(get: { quantities[productId, default: ""] }, set: { quantities[productId] = $0 })
    }

    private func parsedQuantities() -> [String: Double] {
        quantities.compactMapValues { Double($0.replacingOccurrences(of: ",", with: ".")) }.filter { $0.value > 0 }
    }

    private func saveOnly() {
        guard let cafeteria = selectedCafeteria else { return }
        let delivery = store.createDelivery(cafeteriaId: cafeteria.id, date: selectedDate, itemQuantities: parsedQuantities())
        quantities.removeAll()
        message = "Entrega \(delivery.folio) guardada."
    }

    private func saveAndPrint() async {
        guard let cafeteria = selectedCafeteria else { return }
        let delivery = store.createDelivery(cafeteriaId: cafeteria.id, date: selectedDate, itemQuantities: parsedQuantities())
        do {
            try await printer.print(delivery: delivery, cafeteria: cafeteria, bakery: store.bakery)
            store.markPrintResult(deliveryId: delivery.id, success: true)
            quantities.removeAll()
            message = "Entrega \(delivery.folio) impresa."
        } catch {
            store.markPrintResult(deliveryId: delivery.id, success: false)
            message = "Guardado, pero no imprimió: \(error.localizedDescription)"
        }
    }
}

struct DeliveriesView: View {
    @EnvironmentObject private var store: PanfitrionStore
    @State private var selectedDate = DateHelpers.startOfDay(Date())

    var body: some View {
        List {
            Section("Día") {
                HStack {
                    Button { selectedDate = DateHelpers.addDays(-1, to: selectedDate) } label: {
                        Image(systemName: "chevron.left.circle.fill").font(.title2)
                    }
                    Spacer()
                    Text(DateHelpers.displayFormatter.string(from: selectedDate)).font(.headline)
                    Spacer()
                    Button { selectedDate = DateHelpers.addDays(1, to: selectedDate) } label: {
                        Image(systemName: "chevron.right.circle.fill").font(.title2)
                    }
                }
            }
            Section("Entregas") {
                ForEach(store.deliveries(on: selectedDate)) { delivery in
                    NavigationLink(destination: DeliveryEditView(delivery: delivery)) {
                        DeliveryRow(delivery: delivery, cafeteria: store.database.cafeterias.first { $0.id == delivery.cafeteriaId })
                    }
                }
            }
        }
        .navigationTitle("Entregas")
    }
}

struct DeliveryRow: View {
    var delivery: Delivery
    var cafeteria: Cafeteria?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("#\(delivery.folio) \(cafeteria?.name ?? "Cafetería")")
                .font(.headline)
            Text(delivery.items.map { "\(format($0.quantity)) \($0.productName)" }.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text(delivery.printStatus.label)
                if delivery.editedAfterPrint {
                    Text("Editado después de imprimir").foregroundStyle(.red)
                }
            }
            .font(.caption)
        }
    }
}

struct DeliveryEditView: View {
    @EnvironmentObject private var store: PanfitrionStore
    @EnvironmentObject private var printer: PrinterService
    @State var delivery: Delivery
    @State private var quantities: [String: String] = [:]
    @State private var message = ""

    var cafeteria: Cafeteria? {
        store.database.cafeterias.first { $0.id == delivery.cafeteriaId }
    }

    var body: some View {
        Form {
            Section {
                Text("Folio \(delivery.folio)")
                Text(cafeteria?.name ?? "")
                Text(DateHelpers.displayFormatter.string(from: delivery.date))
                Text(delivery.printStatus.label)
                if delivery.editedAfterPrint {
                    Text("Editado después de imprimir").foregroundStyle(.red)
                }
            }
            Section("Productos") {
                ForEach(store.activeProducts) { product in
                    HStack {
                        Text(product.name)
                        Spacer()
                        TextField("0", text: binding(for: product.id))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }
            }
            Section {
                Button("Guardar cambios") { saveChanges() }
                Button("Reimprimir ticket") {
                    Task { await printAgain() }
                }
            }
            if !message.isEmpty {
                Section { Text(message) }
            }
        }
        .navigationTitle("Editar entrega")
        .onAppear {
            quantities = Dictionary(uniqueKeysWithValues: delivery.items.map { ($0.productId, format($0.quantity)) })
        }
    }

    private func binding(for productId: String) -> Binding<String> {
        Binding(get: { quantities[productId, default: ""] }, set: { quantities[productId] = $0 })
    }

    private func saveChanges() {
        let items = store.activeProducts.compactMap { product -> DeliveryItem? in
            let quantity = Double(quantities[product.id, default: ""].replacingOccurrences(of: ",", with: ".")) ?? 0
            guard quantity > 0 else { return nil }
            return DeliveryItem(
                id: delivery.items.first(where: { $0.productId == product.id })?.id ?? UUID().uuidString,
                productId: product.id,
                productName: product.name,
                quantity: quantity,
                unit: product.unit,
                unitPrice: store.price(for: product.id, cafeteriaId: delivery.cafeteriaId)
            )
        }
        store.updateDelivery(delivery, newItems: items)
        if let updated = store.database.deliveries.first(where: { $0.id == delivery.id }) {
            delivery = updated
        }
        message = "Cambios guardados."
    }

    private func printAgain() async {
        guard let cafeteria else { return }
        do {
            try await printer.print(delivery: delivery, cafeteria: cafeteria, bakery: store.bakery)
            store.markPrintResult(deliveryId: delivery.id, success: true)
            message = "Ticket impreso."
        } catch {
            store.markPrintResult(deliveryId: delivery.id, success: false)
            message = "No imprimió: \(error.localizedDescription)"
        }
    }
}

struct AccountsView: View {
    @EnvironmentObject private var store: PanfitrionStore
    @State private var weekStart = DateHelpers.weekStart(for: Date())
    @State private var shareURL: URL?

    var body: some View {
        List {
            WeekSelector(weekStart: $weekStart)
            ForEach(store.activeCafeterias) { cafeteria in
                let account = store.account(for: cafeteria, weekStart: weekStart)
                Section(cafeteria.name) {
                    AccountSummary(account: account)
                    Button("Generar PDF") {
                        do {
                            shareURL = try store.generatePDF(for: account)
                        } catch {
                            store.lastError = error.localizedDescription
                        }
                    }
                }
            }
        }
        .navigationTitle("Cuentas")
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
        }
    }
}

struct PaymentsView: View {
    @EnvironmentObject private var store: PanfitrionStore
    @State private var weekStart = DateHelpers.weekStart(for: Date())
    @State private var paymentText: [String: String] = [:]

    var body: some View {
        List {
            WeekSelector(weekStart: $weekStart)
            ForEach(store.activeCafeterias) { cafeteria in
                let account = store.account(for: cafeteria, weekStart: weekStart)
                Section(cafeteria.name) {
                    AccountSummary(account: account)
                    HStack {
                        TextField("Pago parcial", text: Binding(get: { paymentText[cafeteria.id, default: ""] }, set: { paymentText[cafeteria.id] = $0 }))
                            .keyboardType(.decimalPad)
                        Button("Registrar") {
                            let amount = Double(paymentText[cafeteria.id, default: ""].replacingOccurrences(of: ",", with: ".")) ?? 0
                            if amount > 0 {
                                store.addPayment(cafeteriaId: cafeteria.id, weekStart: weekStart, amount: amount, note: "Pago parcial")
                                paymentText[cafeteria.id] = ""
                            }
                        }
                    }
                    Button("Marcar pagada") { store.markPaid(account: account) }
                        .disabled(account.isPaid)
                }
            }
        }
        .navigationTitle("Pagos")
    }
}

struct WeekSelector: View {
    @Binding var weekStart: Date

    var body: some View {
        Section("Semana lunes a sábado") {
            HStack {
                Button { weekStart = DateHelpers.addWeeks(-1, to: weekStart) } label: {
                    Image(systemName: "chevron.left.circle.fill").font(.title2)
                }
                Spacer()
                Text(DateHelpers.periodLabel(weekStart: weekStart))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Spacer()
                Button { weekStart = DateHelpers.addWeeks(1, to: weekStart) } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.title2)
                }
            }
        }
    }
}

struct AccountSummary: View {
    var account: WeeklyAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Entregas", money(account.deliveriesTotal))
            row("Deuda anterior", money(account.previousDebt))
            row("Pagos", money(account.paid))
            row("Saldo", money(account.balance), bold: true)
            Text(account.isPaid ? "Pagada" : "Pendiente")
                .font(.caption.weight(.bold))
                .foregroundStyle(account.isPaid ? .green : .red)
        }
    }

    private func row(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
        .font(bold ? .headline : .body)
    }
}

struct DatabaseView: View {
    @EnvironmentObject private var store: PanfitrionStore
    @State private var showingImporter = false
    @State private var shareURL: URL?

    var body: some View {
        List {
            Section("Panadería") {
                Text(store.bakery.name)
                Text(store.bakery.email)
                Text(store.bakery.address.display)
                Text("+52 55 2139 7371")
            }
            Section("Catálogo") {
                NavigationLink("Cafeterías", destination: CafeteriasAdminView())
                NavigationLink("Productos", destination: ProductsAdminView())
                NavigationLink("Precios por cafetería", destination: PricesAdminView())
            }
            Section("JSON") {
                Button("Importar JSON") { showingImporter = true }
                Button("Compartir ejemplo JSON") {
                    do {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("panfitrion-catalogo-ejemplo.json")
                        try store.sampleCatalogData().write(to: url, options: .atomic)
                        shareURL = url
                    } catch {
                        store.lastError = error.localizedDescription
                    }
                }
            }
        }
        .navigationTitle("Base de datos")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                try store.importCatalog(from: Data(contentsOf: url))
            } catch {
                store.lastError = error.localizedDescription
            }
        }
        .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
    }
}

struct CafeteriasAdminView: View {
    @EnvironmentObject private var store: PanfitrionStore
    @State private var name = ""

    var body: some View {
        List {
            Section("Nueva cafetería") {
                TextField("Nombre", text: $name)
                Button("Agregar") {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    store.upsertCafeteria(Cafeteria(id: "caf_\(UUID().uuidString)", name: name, contactName: "", phone: "", email: "", address: "", isActive: true))
                    name = ""
                }
            }
            Section("Activas") {
                ForEach(store.database.cafeterias) { cafeteria in
                    Text(cafeteria.name)
                }
            }
        }
        .navigationTitle("Cafeterías")
    }
}

struct ProductsAdminView: View {
    @EnvironmentObject private var store: PanfitrionStore
    @State private var name = ""
    @State private var unit = "pieza"

    var body: some View {
        List {
            Section("Nuevo producto") {
                TextField("Nombre", text: $name)
                TextField("Unidad", text: $unit)
                Button("Agregar") {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    store.upsertProduct(Product(id: "prod_\(UUID().uuidString)", name: name, unit: unit, isActive: true))
                    name = ""
                    unit = "pieza"
                }
            }
            Section("Activos") {
                ForEach(store.database.products) { product in
                    Text("\(product.name) · \(product.unit)")
                }
            }
        }
        .navigationTitle("Productos")
    }
}

struct PricesAdminView: View {
    @EnvironmentObject private var store: PanfitrionStore
    @State private var selectedCafeteriaId = ""
    @State private var prices: [String: String] = [:]

    var body: some View {
        Form {
            Picker("Cafetería", selection: $selectedCafeteriaId) {
                ForEach(store.activeCafeterias) { cafeteria in
                    Text(cafeteria.name).tag(cafeteria.id)
                }
            }
            Section("Precios") {
                ForEach(store.activeProducts) { product in
                    HStack {
                        Text(product.name)
                        Spacer()
                        TextField("0", text: Binding(get: {
                            prices[product.id] ?? String(format: "%.2f", store.price(for: product.id, cafeteriaId: selectedCafeteriaId))
                        }, set: { prices[product.id] = $0 }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    }
                }
                Button("Guardar precios") {
                    for product in store.activeProducts {
                        let text = prices[product.id] ?? String(store.price(for: product.id, cafeteriaId: selectedCafeteriaId))
                        let price = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
                        store.setPrice(productId: product.id, cafeteriaId: selectedCafeteriaId, price: price)
                    }
                    prices.removeAll()
                }
            }
        }
        .navigationTitle("Precios")
        .onAppear {
            selectedCafeteriaId = selectedCafeteriaId.isEmpty ? (store.activeCafeterias.first?.id ?? "") : selectedCafeteriaId
        }
    }
}

struct BackupsView: View {
    @EnvironmentObject private var store: PanfitrionStore
    @State private var shareURL: URL?

    var body: some View {
        List {
            Section {
                Button("Crear respaldo y compartir") {
                    do {
                        shareURL = try store.exportBackup()
                    } catch {
                        store.lastError = error.localizedDescription
                    }
                }
            }
            Section("Incluye") {
                Text("backup.json")
                Text("PDFs generados")
                Text("Configuración de impresora")
            }
        }
        .navigationTitle("Respaldos")
        .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
    }
}

struct PrinterSettingsView: View {
    @EnvironmentObject private var store: PanfitrionStore
    @EnvironmentObject private var printer: PrinterService
    @State private var manualHost = "192.168.1.93"
    @State private var manualMac = "00:11:62:13:B5:00"
    @State private var message = ""

    var body: some View {
        List {
            Section("Guardada") {
                if let saved = printer.savedPrinter {
                    Text(saved.name)
                    Text("\(saved.host):\(saved.port)").foregroundStyle(.secondary)
                    if !saved.macAddress.isEmpty {
                        Text(saved.macAddress).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Sin impresora")
                }
                Button("Imprimir prueba") {
                    Task {
                        do {
                            try await printer.printTest()
                            message = "Prueba impresa."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .disabled(printer.savedPrinter == nil)
            }
            Section("Buscar") {
                Button(printer.isSearching ? "Detener búsqueda" : "Buscar impresora") {
                    printer.isSearching ? printer.stopSearch() : printer.startSearch()
                }
                Text(printer.statusMessage).font(.caption).foregroundStyle(.secondary)
                ForEach(printer.discoveredPrinters) { item in
                    Button {
                        printer.save(item)
                        store.savePrinter(printer.savedPrinter)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text("\(item.host):\(item.port)").font(.caption).foregroundStyle(.secondary)
                            if !item.macAddress.isEmpty {
                                Text(item.macAddress).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("IP manual") {
                TextField("192.168.1.50", text: $manualHost)
                    .keyboardType(.numbersAndPunctuation)
                TextField("00:11:62:13:B5:00", text: $manualMac)
                    .textInputAutocapitalization(.characters)
                    .keyboardType(.numbersAndPunctuation)
                Button("Usar 192.168.1.93") {
                    manualHost = "192.168.1.93"
                    manualMac = "00:11:62:13:B5:00"
                    printer.saveManual(host: manualHost, macAddress: manualMac)
                    store.savePrinter(printer.savedPrinter)
                    message = "IP 192.168.1.93 y MAC 00:11:62:13:B5:00 guardadas."
                }
                Button("Guardar IP manual") {
                    printer.saveManual(host: manualHost, macAddress: manualMac)
                    store.savePrinter(printer.savedPrinter)
                    message = "IP \(manualHost.trimmingCharacters(in: .whitespacesAndNewlines)) guardada."
                }
                .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !message.isEmpty {
                Section { Text(message) }
            }
        }
        .navigationTitle("Impresora")
    }
}

private func money(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = Locale(identifier: "es_MX")
    return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
}

private func format(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.2f", value)
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}
