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

    var biometryName: String {
        switch biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: loc("Code")
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
        } else if await authenticate(reason: loc("App-Sperre deaktivieren")) {
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
        if await authenticate(reason: loc("ClassBuddy entsperren")) {
            isLocked = false
        }
    }

    // MARK: Privatsphäre-Modus

    func enablePrivacyMode() {
        isPrivacyModeOn = true
    }

    func disablePrivacyMode() async {
        guard isPrivacyModeOn else { return }
        if await authenticate(reason: loc("Sensible Informationen wieder anzeigen")) {
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

    /// Bestätigung per Face ID / Code vor unumkehrbaren Aktionen (z. B. alle Daten löschen).
    func confirmDestructiveAction(reason: String) async -> Bool {
        await authenticate(reason: reason)
    }

    // MARK: Authentifizierung

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        lastError = nil

        // Ohne eingerichteten Gerätecode gibt es keine sichere Entsperrung.
        var error: NSError?
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            #if targetEnvironment(simulator)
            // Simulator ohne eingerichteten Code: nicht aussperren.
            return true
            #else
            lastError = error?.localizedDescription ?? loc("Authentifizierung nicht verfügbar.")
            return false
            #endif
        }

        // Face ID / Code über die Keychain (Secure Enclave), nicht nur als Bool.
        let outcome = await Task.detached { KeychainGate.unlock(reason: reason) }.value
        switch outcome {
        case .success:
            return true
        case .cancelled:
            return false
        case .failed(let message):
            lastError = message
            return false
        }
    }
}
