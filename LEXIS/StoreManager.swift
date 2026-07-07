import Foundation
import StoreKit

// MARK: - StoreKit 2 shop (R6 — first revenue, cosmetic-led)
//
// Gentle, cosmetic-only monetisation on top of a measured, retained base
// (the Royal Match model): buy an individual tile theme outright, or the
// one-time "LEXIS Supporter" bundle that unlocks every cosmetic. NO
// pay-to-win, no consumable power-ups, near-zero ads — spending is a
// shortcut and a show of support, never a wall in front of the fun.
//
// This is a scaffold: the code is complete, but products must be created in
// App Store Connect (ids below) before anything transacts. Until then
// `products` is empty and the UI simply falls back to the coin economy — the
// app is fully functional with zero IAP configured. For local testing,
// attach Products.storekit to the run scheme in Xcode.
//
// The catalogue mirrors CosmeticsStore, so a StoreKit purchase and a coin
// purchase both end at CosmeticsStore.grant(_:) — one source of truth.

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var supporterOwned = false
    @Published private(set) var purchasing: String?   // product id mid-purchase

    private var updatesTask: Task<Void, Never>?

    enum ProductID {
        static let supporter = "com.daviddefranceski.lexis.supporter"
        static func theme(_ t: TileTheme) -> String {
            "com.daviddefranceski.lexis.theme.\(t.rawValue.lowercased())"
        }
        /// Every paid product: the supporter bundle + one per non-default theme.
        static var all: [String] {
            [supporter] + TileTheme.allCases.filter { $0 != .classic }.map { theme($0) }
        }
    }

    private init() {}

    /// Start the transaction listener and load products. Call once at launch.
    func start() {
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            products = try await Product.products(for: ProductID.all)
        } catch {
            print("StoreKit: product load failed — \(error.localizedDescription)")
        }
    }

    func product(for id: String) -> Product? { products.first { $0.id == id } }
    var supporterProduct: Product? { product(for: ProductID.supporter) }
    func product(for theme: TileTheme) -> Product? { product(for: ProductID.theme(theme)) }

    /// Purchase a product. Returns true on a verified success.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchasing = product.id
        defer { purchasing = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return false }
                apply(productID: transaction.productID, celebrate: true)
                await transaction.finish()
                Analytics.shared.purchase(product.id)
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            print("StoreKit: purchase failed — \(error.localizedDescription)")
            return false
        }
    }

    /// Restore previous purchases (App Store account is the source of truth).
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                apply(productID: transaction.productID, celebrate: false)
            }
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await MainActor.run {
                        StoreManager.shared.apply(productID: transaction.productID, celebrate: false)
                    }
                    await transaction.finish()
                }
            }
        }
    }

    /// Turn an owned product into a granted cosmetic. Idempotent.
    private func apply(productID: String, celebrate: Bool) {
        if productID == ProductID.supporter {
            supporterOwned = true
            for theme in TileTheme.allCases { CosmeticsStore.shared.grant(theme, celebrate: false) }
        } else {
            for theme in TileTheme.allCases where ProductID.theme(theme) == productID {
                CosmeticsStore.shared.grant(theme, celebrate: celebrate)
            }
        }
    }
}
