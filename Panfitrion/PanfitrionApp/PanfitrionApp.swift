import SwiftUI

@main
struct PanfitrionApp: App {
    @StateObject private var store = PanfitrionStore()
    @StateObject private var printer = PrinterService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(printer)
                .task {
                    await store.load()
                    printer.loadSavedPrinter()
                }
        }
    }
}

