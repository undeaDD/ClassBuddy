import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Ein Daten-Passwort für alles, was das Gerät verlässt: Excel-Backup, Kollegen-Paket, lokaler Sync, Cloud-Ordner
/// und iCloud. Beim ersten Zugriff zufällig erzeugt, im Schlüsselbund dieses Geräts gespeichert, jederzeit änderbar.
/// Eigene Geräte brauchen dasselbe Passwort (die Kopplung übernimmt es vom anderen Gerät).
nonisolated enum DataPassword {
    static let minimumLength = 8
    private static let service = "de.devsforge.ClassBuddy.dataPassword"
    private static let account = "data"

    /// Gespeichertes Passwort, beim ersten Aufruf neu erzeugt.
    static var current: String {
        if let stored { return stored }
        let password = generate()
        store(password)
        return password
    }

    static func set(_ password: String) {
        store(password)
    }

    /// Gut lesbar: 4 Gruppen à 5 Zeichen ohne verwechselbare Zeichen (0/o, 1/l/i), z. B. „k7mqp-3vhxa-…“.
    static func generate() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        let groups = (0..<4).map { _ in
            String((0..<5).map { _ in alphabet[Int(randomBytes(1)[0]) % alphabet.count] })
        }
        return groups.joined(separator: "-")
    }

    static func isValid(_ password: String) -> Bool {
        password.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumLength
    }

    private static var stored: String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func store(_ password: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData] = Data(password.utf8)
        // Ab dem ersten Entsperren lesbar (iCloud-Sync beim Start), nie in Geräte-Backups oder auf andere Geräte.
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

/// Verschlüsselung mit dem Daten-Passwort (Kollegen-Paket, Cloud-Ordner, iCloud): AES-256-GCM, Schlüssel per
/// PBKDF2-SHA256 aus Passwort und zufälligem Salt. Aufbau: „CBENC1“, Salt (16), Runden (UInt32), GCM-Block.
nonisolated enum DataCrypto {
    enum CryptoError: LocalizedError, Equatable {
        case wrongPassword

        var errorDescription: String? {
            loc("Das Daten-Passwort passt nicht. Es muss auf allen Geräten gleich sein.")
        }
    }

    private static let magic = Data("CBENC1".utf8)
    static let iterations: UInt32 = 200_000

    static func isSealed(_ data: Data) -> Bool {
        data.prefix(magic.count) == magic
    }

    static func seal(_ data: Data, password: String) throws -> Data {
        let salt = DataPassword.randomBytes(16)
        let key = deriveKey(password: password, salt: salt, iterations: iterations)
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else { throw CryptoError.wrongPassword }
        var rounds = iterations.littleEndian
        return magic + salt + Data(bytes: &rounds, count: 4) + combined
    }

    static func open(_ data: Data, password: String) throws -> Data {
        let header = magic.count + 16 + 4
        guard isSealed(data), data.count > header else { throw CryptoError.wrongPassword }
        let bytes = Data(data)
        let salt = bytes.subdata(in: magic.count..<(magic.count + 16))
        let rounds = bytes.subdata(in: (magic.count + 16)..<header).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let key = deriveKey(password: password, salt: salt, iterations: UInt32(littleEndian: rounds))
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: bytes.subdata(in: header..<bytes.count)), using: key)
        } catch {
            throw CryptoError.wrongPassword
        }
    }

    static func deriveKey(password: String, salt: Data, iterations: UInt32) -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        salt.withUnsafeBytes { saltBytes in
            _ = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.map { CChar(bitPattern: $0) }, passwordBytes.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &derived, derived.count
            )
        }
        return SymmetricKey(data: derived)
    }
}
