import Foundation
import StoreKit
import UIKit

/// Infos zur Installation und zum Gerät für die Einstellungen (Kopfbereich, Version).
enum InstallInfo {
    nonisolated enum Method: String, Sendable {
        case xcode = "Xcode"
        case developer = "Entwickler-Signatur"
        case testFlight = "TestFlight"
        case appStore = "App Store"

        /// Anzeige in der App-Sprache (Produktnamen bleiben).
        var displayName: String {
            self == .developer ? loc("Entwickler-Signatur") : rawValue
        }
    }

    /// Wie die App installiert wurde (best effort). Fragt bei Store-Builds StoreKit.
    static func detectMethod() async -> Method {
        let hasProfile = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil
        var storeEnvironment: String?
        if !isDebugBuild, !hasProfile, let transaction = try? await AppTransaction.shared {
            storeEnvironment = transaction.unsafePayloadValue.environment.rawValue
        }
        return method(isDebugBuild: isDebugBuild, hasProvisioningProfile: hasProfile, storeEnvironment: storeEnvironment)
    }

    /// Reine Entscheidung (testbar):
    /// - Debug-Builds kommen aus Xcode.
    /// - Ein eingebettetes Provisioning-Profil ohne Store = Entwickler-/Ad-hoc-Signatur.
    /// - StoreKit-Umgebung „Sandbox“ = TestFlight, sonst App Store.
    static func method(isDebugBuild: Bool, hasProvisioningProfile: Bool, storeEnvironment: String?) -> Method {
        if isDebugBuild { return .xcode }
        if hasProvisioningProfile { return .developer }
        if storeEnvironment == AppStore.Environment.sandbox.rawValue { return .testFlight }
        return .appStore
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Erste Installation: Erstellungsdatum des App-Containers (bleibt bei Updates erhalten).
    static var installDate: Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: URL.documentsDirectory.path(percentEncoded: false))
        return attributes?[.creationDate] as? Date
    }

    /// Kurzform für die Versionszeile: „p“ für iPhone, „t“ für Tablet (iPad), z. B. „p15,2“ / „t13,4“.
    static var shortDeviceModel: String { shortModel(deviceModel) }

    nonisolated static func shortModel(_ identifier: String) -> String {
        if identifier.hasPrefix("iPhone") { return "p" + identifier.dropFirst("iPhone".count) }
        if identifier.hasPrefix("iPad") { return "t" + identifier.dropFirst("iPad".count) }
        return identifier
    }

    /// z. B. „iPadOS 26.1“ / „iOS 26.1“
    static var osVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    /// Modellkennung, z. B. „iPad15,3“ (im Simulator die des simulierten Geräts).
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8) ?? UIDevice.current.model
        }
    }
}
