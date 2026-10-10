import Foundation
import StoreKit

/// Stand von Testphase und Vollversion.
nonisolated enum PurchaseStatus: Hashable, Sendable {
    /// Käufe noch nicht geladen (kurz nach dem Start): nie sperren.
    case loading
    case notStarted
    case trial(daysLeft: Int)
    case expired
    case purchased

    static let trialDays = 30

    /// Reine Berechnung aus den Käufen: Vollversion schlägt alles, sonst zählt das Kaufdatum des Test-Artikels.
    /// Tage übrig wird aufgerundet („Noch 1 Tag“ bis zum letzten Moment).
    static func from(hasFullVersion: Bool, trialStart: Date?, now: Date = .now, calendar: Calendar = .current) -> Self {
        if hasFullVersion { return .purchased }
        guard let trialStart else { return .notStarted }
        guard let end = calendar.date(byAdding: .day, value: trialDays, to: trialStart), end > now else { return .expired }
        // Über den Kalender statt Sekunden, damit die Zeitumstellung keinen Tag dazu- oder wegrechnet.
        let remaining = calendar.dateComponents([.day, .second], from: now, to: end)
        let days = (remaining.day ?? 0) + ((remaining.second ?? 0) > 0 ? 1 : 0)
        return .trial(daysLeft: max(days, 1))
    }

    /// Ohne Entscheidung (noch nicht gestartet) oder abgelaufen ist nur die Kaufseite erreichbar.
    var requiresChoice: Bool { self == .notStarted || self == .expired }

    var trialDaysLeft: Int? {
        if case .trial(let days) = self { days } else { nil }
    }
}

/// In-App-Käufe (StoreKit 2): Vollversion (einmalig) und kostenlose Testphase (0-€-Artikel, Richtlinie 3.1.1).
/// Berechtigungen kommen nur aus `Transaction.currentEntitlements`, ohne eigenen Server; sie hängen an der Apple-ID
/// und überstehen so Neuinstallation und Gerätewechsel.
@Observable
final class PurchaseStore {
    nonisolated static let fullVersionID = "de.devsforge.ClassBuddy.full"
    nonisolated static let trialID = "de.devsforge.ClassBuddy.trial"

    private(set) var status: PurchaseStatus = .loading
    private(set) var fullVersion: Product?
    private(set) var trial: Product?
    /// Kauf oder Wiederherstellen läuft (Buttons gesperrt, Fortschritt in der Karte).
    private(set) var isWorking = false

    private var hasFullVersion = false
    private var trialStart: Date?
    private var updates: Task<Void, Never>?

    #if DEBUG
    /// Debug-Menü: Status simulieren statt der echten Käufe (`nil` = echt). Bleibt über Neustarts erhalten;
    /// Testen und Kaufen schalten dann ebenfalls nur die Simulation weiter.
    var simulatedStatus: PurchaseStatus? = PurchaseStatus(debugKey: UserDefaults.standard.string(forKey: simulationKey)) {
        didSet {
            UserDefaults.standard.set(simulatedStatus?.debugKey, forKey: Self.simulationKey)
            refreshStatus()
        }
    }

    private static let simulationKey = "debug.simulatedPurchaseStatus"
    #endif

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
        Task { await load() }
    }

    /// Produkte (Preise) und Berechtigungen laden. Auch beim Wechsel in den Vordergrund, damit der Tageszähler stimmt.
    func load() async {
        if fullVersion == nil || trial == nil {
            let products = (try? await Product.products(for: [Self.fullVersionID, Self.trialID])) ?? []
            fullVersion = products.first { $0.id == Self.fullVersionID }
            trial = products.first { $0.id == Self.trialID }
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var hasFullVersion = false
        var trialStart: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case Self.fullVersionID: hasFullVersion = true
            case Self.trialID: trialStart = transaction.originalPurchaseDate
            default: break
            }
        }
        self.hasFullVersion = hasFullVersion
        self.trialStart = trialStart
        refreshStatus()
    }

    private func refreshStatus() {
        #if DEBUG
        if let simulatedStatus {
            status = simulatedStatus
            return
        }
        #endif
        status = .from(hasFullVersion: hasFullVersion, trialStart: trialStart)
    }

    enum Outcome {
        case success
        case cancelled
        /// Wartet auf Freigabe (z. B. „Kaufen anfragen“ in der Familie).
        case pending
        case failed
    }

    func startTrial() async -> Outcome {
        await purchase(Self.trialID)
    }

    func buyFullVersion() async -> Outcome {
        await purchase(Self.fullVersionID)
    }

    private func product(_ id: String) -> Product? {
        id == Self.trialID ? trial : fullVersion
    }

    private func purchase(_ id: String) async -> Outcome {
        guard !isWorking else { return .cancelled }
        #if DEBUG
        if simulatedStatus != nil {
            simulatedStatus = id == Self.trialID ? .trial(daysLeft: PurchaseStatus.trialDays) : .purchased
            return .success
        }
        #endif
        isWorking = true
        defer { isWorking = false }
        // Offline beim Start: Produkte jetzt nachladen.
        if product(id) == nil { await load() }
        guard let product = product(id) else { return .failed }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlements()
                return .success
            case .success(.unverified):
                return .failed
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    /// „Käufe wiederherstellen“: gleicht mit dem App Store ab (fragt ggf. nach dem Apple-Account).
    func restore() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
        } catch {
            return false
        }
        await refreshEntitlements()
        return true
    }
}

#if DEBUG
extension PurchaseStatus {
    /// Simulierte Zustände im Debug-Menü (Testphase mit 23 Tagen bzw. 1 Tag).
    static let debugCases: [PurchaseStatus] = [.notStarted, .trial(daysLeft: 23), .trial(daysLeft: 1), .expired, .purchased]

    init?(debugKey: String?) {
        guard let match = Self.debugCases.first(where: { $0.debugKey == debugKey }) else { return nil }
        self = match
    }

    var debugKey: String {
        switch self {
        case .loading: "loading"
        case .notStarted: "notStarted"
        case .trial(let days): "trial\(days)"
        case .expired: "expired"
        case .purchased: "purchased"
        }
    }
}
#endif
