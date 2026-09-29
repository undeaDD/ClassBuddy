import LocalAuthentication
import SwiftUI

/// App-Sperre (Face ID) und Privatsphäre-Modus.
///
/// - App-Sperre: gesperrt beim Start und sobald die App in den Hintergrund geht.
/// - Privatsphäre-Modus: Einschalten jederzeit ohne Authentifizierung,
///   Ausschalten nur mit Face ID / Code.
@Observable
final class AppSecurity {
    private(set) var isLocked: Bool
    private(set) var isPrivacyModeOn: Bool {
        didSet { UserDefaults.standard.set(isPrivacyModeOn, forKey: Keys.privacyMode) }
    }
    private(set) var isAppLockEnabled: Bool {
        didSet { UserDefaults.standard.set(isAppLockEnabled, forKey: Keys.appLockEnabled) }
    }
    private(set) var isAuthenticating = false
    private(set) var lastError: String?

    private enum Keys {
        static let appLockEnabled = "security.appLockEnabled"
        static let privacyMode = "security.privacyMode"
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.appLockEnabled: true, Keys.privacyMode: false])
        let lockEnabled = defaults.bool(forKey: Keys.appLockEnabled)
        isAppLockEnabled = lockEnabled
        isPrivacyModeOn = defaults.bool(forKey: Keys.privacyMode)
        isLocked = lockEnabled
    }

    // MARK: Biometrie-Infos

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    var biometrySymbol: String {
        switch biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock"
        }
    }

    var biometryName: String {
        switch biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Code"
        }
    }

    // MARK: App-Sperre

    /// Automatisch nach Face ID fragen, sobald die App wieder aktiv ist
    /// (nur nach Start / Rückkehr aus dem Hintergrund – nicht nach „Abbrechen“).
    private var promptOnNextActivation = true

    func lock() {
        guard isAppLockEnabled else { return }
        isLocked = true
        promptOnNextActivation = true
    }

    /// Einschalten ohne Rückfrage, Ausschalten nur mit Face ID / Code.
    func setAppLockEnabled(_ enabled: Bool) async {
        if enabled {
            isAppLockEnabled = true
        } else if await authenticate(reason: "App-Sperre deaktivieren") {
            isAppLockEnabled = false
        }
    }

    func sceneDidBecomeActive() async {
        guard isLocked, promptOnNextActivation else { return }
        promptOnNextActivation = false
        await unlock()
    }

    func unlock() async {
        guard isLocked else { return }
        if await authenticate(reason: "ClassBuddy entsperren") {
            isLocked = false
        }
    }

    // MARK: Privatsphäre-Modus

    func enablePrivacyMode() {
        isPrivacyModeOn = true
    }

    func disablePrivacyMode() async {
        guard isPrivacyModeOn else { return }
        if await authenticate(reason: "Sensible Informationen wieder anzeigen") {
            isPrivacyModeOn = false
        }
    }

    func togglePrivacyMode() async {
        if isPrivacyModeOn {
            await disablePrivacyMode()
        } else {
            enablePrivacyMode()
        }
    }

    // MARK: Authentifizierung

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        lastError = nil

        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        var error: NSError?
        // .deviceOwnerAuthentication = Face ID mit Fallback auf den Gerätecode.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            #if targetEnvironment(simulator)
            // Simulator ohne eingerichteten Code: nicht aussperren.
            return true
            #else
            lastError = error?.localizedDescription ?? "Authentifizierung nicht verfügbar."
            return false
            #endif
        }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
