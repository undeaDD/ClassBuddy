import Foundation
import LocalAuthentication
import Security

/// Kryptografisch gebundene Entsperrung über die Keychain.
///
/// Statt nur das Ergebnis von `LAContext.evaluatePolicy` (ein Bool, auf manipulierten
/// Geräten fälschbar) zu verwenden, liegt ein zufälliges Token in der Keychain, das die
/// Secure Enclave nur nach Biometrie / Gerätecode herausgibt (`.userPresence`).
/// Das Token ist an dieses Gerät gebunden und landet nicht in Backups.
nonisolated enum KeychainGate {
    enum Outcome: Equatable {
        case success
        case cancelled
        case failed(String)
    }

    private static let service = "de.devsforge.ClassBuddy.appLock"
    private static let account = "unlock-token"

    /// Fragt Biometrie / Code ab und gibt bei Erfolg `.success` zurück. Blockiert – nicht auf dem Main Thread aufrufen.
    static func unlock(reason: String) -> Outcome {
        switch readToken(reason: reason) {
        case errSecSuccess:
            return .success
        case errSecUserCanceled:
            return .cancelled
        case errSecItemNotFound:
            // Erster Start oder Token nach Änderung des Gerätecodes ungültig: neu anlegen und erneut abfragen.
            guard storeNewToken() == errSecSuccess else { return .failed("Die App-Sperre konnte nicht eingerichtet werden.") }
            let retry = readToken(reason: reason)
            return retry == errSecSuccess ? .success : retry == errSecUserCanceled ? .cancelled : .failed(message(for: retry))
        case let status:
            return .failed(message(for: status))
        }
    }

    private static func readToken(reason: String) -> OSStatus {
        let context = LAContext()
        context.localizedReason = reason
        context.localizedCancelTitle = "Abbrechen"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: context,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return status }
        return (result as? Data)?.isEmpty == false ? errSecSuccess : errSecItemNotFound
    }

    private static func storeNewToken() -> OSStatus {
        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(base as CFDictionary)

        var token = Data(count: 32)
        let randomStatus = token.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard randomStatus == errSecSuccess else { return randomStatus }

        // Bewusst `.userPresence` (Biometrie mit Rückfall auf den Gerätecode), wie iOS selbst:
        // Ohne Rückfall könnte eine fehlschlagende Face-ID-Erkennung (oder ein iPad ohne
        // eingerichtete Biometrie) den Zugriff auf die eigenen Daten komplett sperren.
        // nosemgrep: keychain-passcode-fallback, keychain-acl-allows-biometry-changes
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil) else {
            return errSecParam
        }

        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessControl: access,
            kSecValueData: token,
        ]
        return SecItemAdd(item as CFDictionary, nil)
    }

    private static func message(for status: OSStatus) -> String {
        switch status {
        case errSecAuthFailed: "Authentifizierung fehlgeschlagen."
        case errSecNotAvailable, errSecInteractionNotAllowed: "Authentifizierung ist gerade nicht verfügbar."
        default: (SecCopyErrorMessageString(status, nil) as String?) ?? "Authentifizierung fehlgeschlagen (\(status))."
        }
    }
}
