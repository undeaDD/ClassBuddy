import CommonCrypto
import CryptoKit
import Foundation

/// Echte Excel-Verschlüsselung (ECMA-376 „Agile Encryption“, MS-OFFCRYPTO): AES-256-CBC, SHA-512, 100 000 Runden.
/// Die .xlsx liegt verschlüsselt in einem Compound File (`CompoundFile`) und öffnet in Excel, Numbers und
/// LibreOffice nur mit dem Passwort. Ohne Bibliothek, CommonCrypto für AES.
nonisolated enum OfficeEncryption {
    enum OfficeError: LocalizedError, Equatable {
        case wrongPassword
        case unsupported

        var errorDescription: String? {
            switch self {
            case .wrongPassword: loc("Das Passwort passt nicht zu dieser Datei.")
            case .unsupported: loc("Diese verschlüsselte Datei kann ClassBuddy nicht öffnen.")
            }
        }
    }

    static let spinCount = 100_000
    private static let segmentLength = 4096
    private static let verifierInputBlock = Data([0xFE, 0xA7, 0xD2, 0x76, 0x3B, 0x4B, 0x9E, 0x79])
    private static let verifierValueBlock = Data([0xD7, 0xAA, 0x0F, 0x6D, 0x30, 0x61, 0x34, 0x4E])
    private static let keyValueBlock = Data([0x14, 0x6E, 0x0B, 0xE7, 0xAB, 0xAC, 0xD0, 0xD6])
    private static let hmacKeyBlock = Data([0x5F, 0xB2, 0xAD, 0x01, 0x0C, 0xB9, 0xE1, 0xF6])
    private static let hmacValueBlock = Data([0xA0, 0x67, 0x7F, 0x02, 0xB2, 0x2C, 0x84, 0x33])

    /// Verschlüsselt? (Compound File statt ZIP)
    static func isEncrypted(_ data: Data) -> Bool {
        CompoundFile.isCompoundFile(data)
    }

    // MARK: Verschlüsseln

    static func encrypt(_ package: Data, password: String) throws -> Data {
        let secretKey = random(32)
        let keySalt = random(16)
        let passwordSalt = random(16)

        // Paket in 4096-Byte-Segmenten, IV je Segment aus Salt und Nummer.
        var encryptedPackage = littleEndian(UInt64(package.count))
        var offset = 0
        var index: UInt32 = 0
        while offset < package.count {
            let segment = package.subdata(in: offset..<min(offset + segmentLength, package.count))
            let vector = hashIV(keySalt + littleEndian(index))
            encryptedPackage += try aes(encrypt: true, padded(segment), key: secretKey, vector: vector)
            offset += segmentLength
            index += 1
        }

        // Integrität: HMAC-SHA512 über den ganzen verschlüsselten Strom.
        let hmacKey = random(64)
        let hmacValue = Data(HMAC<SHA512>.authenticationCode(for: encryptedPackage, using: SymmetricKey(data: hmacKey)))
        let encryptedHmacKey = try aes(encrypt: true, hmacKey, key: secretKey, vector: hashIV(keySalt + hmacKeyBlock))
        let encryptedHmacValue = try aes(encrypt: true, hmacValue, key: secretKey, vector: hashIV(keySalt + hmacValueBlock))

        // Passwort-Schlüssel und Prüfwert.
        let passwordHash = iteratedHash(password: password, salt: passwordSalt)
        let verifierInput = random(16)
        let verifierHash = Data(SHA512.hash(data: verifierInput))
        let encryptedVerifierInput = try aes(
            encrypt: true, verifierInput, key: blockKey(passwordHash, verifierInputBlock), vector: passwordSalt
        )
        let encryptedVerifierHash = try aes(
            encrypt: true, verifierHash, key: blockKey(passwordHash, verifierValueBlock), vector: passwordSalt
        )
        let encryptedKeyValue = try aes(encrypt: true, secretKey, key: blockKey(passwordHash, keyValueBlock), vector: passwordSalt)

        let parameters = #"saltSize="16" blockSize="16" keyBits="256" hashSize="64" cipherAlgorithm="AES" "#
            + #"cipherChaining="ChainingModeCBC" hashAlgorithm="SHA512""#
        let xml = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r
            <encryption xmlns="http://schemas.microsoft.com/office/2006/encryption" \
            xmlns:p="http://schemas.microsoft.com/office/2006/keyEncryptor/password" \
            xmlns:c="http://schemas.microsoft.com/office/2006/keyEncryptor/certificate">\
            <keyData \(parameters) saltValue="\(keySalt.base64EncodedString())"/>\
            <dataIntegrity encryptedHmacKey="\(encryptedHmacKey.base64EncodedString())" \
            encryptedHmacValue="\(encryptedHmacValue.base64EncodedString())"/>\
            <keyEncryptors><keyEncryptor uri="http://schemas.microsoft.com/office/2006/keyEncryptor/password">\
            <p:encryptedKey spinCount="\(spinCount)" \(parameters) saltValue="\(passwordSalt.base64EncodedString())" \
            encryptedVerifierHashInput="\(encryptedVerifierInput.base64EncodedString())" \
            encryptedVerifierHashValue="\(encryptedVerifierHash.base64EncodedString())" \
            encryptedKeyValue="\(encryptedKeyValue.base64EncodedString())"/></keyEncryptor></keyEncryptors></encryption>
            """
        // Version 4.4, Flags 0x40 (Agile).
        let info = littleEndian(UInt16(4)) + littleEndian(UInt16(4)) + littleEndian(UInt32(0x40)) + Data(xml.utf8)

        return CompoundFile.write([
            CompoundFile.Entry(path: ["\u{06}DataSpaces", "Version"], data: DataSpaces.version),
            CompoundFile.Entry(path: ["\u{06}DataSpaces", "DataSpaceMap"], data: DataSpaces.map),
            CompoundFile.Entry(path: ["\u{06}DataSpaces", "DataSpaceInfo", "StrongEncryptionDataSpace"], data: DataSpaces.info),
            CompoundFile.Entry(
                path: ["\u{06}DataSpaces", "TransformInfo", "StrongEncryptionTransform", "\u{06}Primary"],
                data: DataSpaces.primary
            ),
            CompoundFile.Entry(path: ["EncryptionInfo"], data: info),
            CompoundFile.Entry(path: ["EncryptedPackage"], data: encryptedPackage),
        ])
    }

    // MARK: Entschlüsseln

    static func decrypt(_ data: Data, password: String) throws -> Data {
        let file = try CompoundFile(data)
        guard let info = file.stream(named: "EncryptionInfo"), let encrypted = file.stream(named: "EncryptedPackage"),
              info.count > 8, encrypted.count > 8
        else { throw OfficeError.unsupported }
        let version = info.withUnsafeBytes {
            ($0.loadUnaligned(fromByteOffset: 0, as: UInt16.self), $0.loadUnaligned(fromByteOffset: 2, as: UInt16.self))
        }
        guard version == (4, 4), let xml = String(data: info.dropFirst(8), encoding: .utf8) else { throw OfficeError.unsupported }

        guard let keyData = element("keyData", in: xml), let encryptedKey = element("p:encryptedKey", in: xml),
              keyData["hashAlgorithm"] == "SHA512", encryptedKey["hashAlgorithm"] == "SHA512",
              keyData["cipherAlgorithm"] == "AES", keyData["keyBits"] == "256",
              let keySalt = keyData["saltValue"].flatMap({ Data(base64Encoded: $0) }),
              let passwordSalt = encryptedKey["saltValue"].flatMap({ Data(base64Encoded: $0) }),
              let spin = encryptedKey["spinCount"].flatMap(Int.init),
              let verifierInput = encryptedKey["encryptedVerifierHashInput"].flatMap({ Data(base64Encoded: $0) }),
              let verifierHash = encryptedKey["encryptedVerifierHashValue"].flatMap({ Data(base64Encoded: $0) }),
              let keyValue = encryptedKey["encryptedKeyValue"].flatMap({ Data(base64Encoded: $0) })
        else { throw OfficeError.unsupported }

        let passwordHash = iteratedHash(password: password, salt: passwordSalt, spinCount: spin)
        let input = try aes(encrypt: false, verifierInput, key: blockKey(passwordHash, verifierInputBlock), vector: passwordSalt)
        let hash = try aes(encrypt: false, verifierHash, key: blockKey(passwordHash, verifierValueBlock), vector: passwordSalt)
        guard Data(SHA512.hash(data: input.prefix(16))) == hash.prefix(64) else { throw OfficeError.wrongPassword }
        let secretKey = try aes(encrypt: false, keyValue, key: blockKey(passwordHash, keyValueBlock), vector: passwordSalt).prefix(32)

        if let integrity = element("dataIntegrity", in: xml),
           let hmacKeyData = integrity["encryptedHmacKey"].flatMap({ Data(base64Encoded: $0) }),
           let hmacValueData = integrity["encryptedHmacValue"].flatMap({ Data(base64Encoded: $0) }) {
            let hmacKey = try aes(encrypt: false, hmacKeyData, key: Data(secretKey), vector: hashIV(keySalt + hmacKeyBlock)).prefix(64)
            let expected = try aes(encrypt: false, hmacValueData, key: Data(secretKey), vector: hashIV(keySalt + hmacValueBlock)).prefix(64)
            let actual = Data(HMAC<SHA512>.authenticationCode(for: encrypted, using: SymmetricKey(data: hmacKey)))
            guard actual == expected else { throw OfficeError.unsupported }
        }

        let size = Int(encrypted.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian)
        var result = Data()
        var offset = 8
        var index: UInt32 = 0
        while offset < encrypted.count, result.count < size {
            let end = min(offset + segmentLength, encrypted.count)
            let segment = encrypted.subdata(in: (encrypted.startIndex + offset)..<(encrypted.startIndex + end))
            guard segment.count % 16 == 0 else { throw OfficeError.unsupported }
            result += try aes(encrypt: false, segment, key: Data(secretKey), vector: hashIV(keySalt + littleEndian(index)))
            offset = end
            index += 1
        }
        guard result.count >= size else { throw OfficeError.unsupported }
        return result.prefix(size)
    }

    // MARK: Bausteine

    /// H0 = SHA512(Salt + Passwort als UTF-16LE), danach `spinCount`-mal SHA512(Zähler + H).
    private static func iteratedHash(password: String, salt: Data, spinCount: Int = spinCount) -> Data {
        var passwordBytes = Data()
        for unit in password.utf16 { passwordBytes += littleEndian(unit) }
        var hash = Data(SHA512.hash(data: salt + passwordBytes))
        var buffer = Data(count: 4 + 64)
        for iterator in 0..<UInt32(spinCount) {
            buffer.replaceSubrange(0..<4, with: littleEndian(iterator))
            buffer.replaceSubrange(4..<68, with: hash)
            hash = Data(SHA512.hash(data: buffer))
        }
        return hash
    }

    private static func blockKey(_ hash: Data, _ block: Data) -> Data {
        Data(SHA512.hash(data: hash + block)).prefix(32)
    }

    private static func hashIV(_ input: Data) -> Data {
        Data(SHA512.hash(data: input)).prefix(16)
    }

    private static func padded(_ data: Data) -> Data {
        let remainder = data.count % 16
        return remainder == 0 ? data : data + Data(count: 16 - remainder)
    }

    private static func aes(encrypt: Bool, _ data: Data, key: Data, vector: Data) throws -> Data {
        let input = padded(data)
        var output = Data(count: input.count)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    vector.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0,
                            keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                            inputBytes.baseAddress, input.count, outputBytes.baseAddress, input.count, &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw OfficeError.unsupported }
        return output.prefix(moved)
    }

    private static func random(_ count: Int) -> Data {
        DataPassword.randomBytes(count)
    }

    /// Attribute eines Elements (erstes Vorkommen) aus dem EncryptionInfo-XML.
    private static func element(_ name: String, in xml: String) -> [String: String]? {
        guard let start = xml.range(of: "<\(name) "), let end = xml[start.upperBound...].range(of: ">") else { return nil }
        let body = String(xml[start.upperBound..<end.lowerBound])
        var attributes: [String: String] = [:]
        for match in body.matches(of: #/([\w:]+)="([^"]*)"/#) {
            attributes[String(match.1)] = String(match.2)
        }
        return attributes
    }
}

nonisolated func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

/// Feste Beschreibung der Verschlüsselung (MS-OFFCRYPTO 2.1, „\u{06}DataSpaces“), wie Excel sie schreibt.
nonisolated private enum DataSpaces {
    /// Länge in Bytes + UTF-16LE, auf 4 Bytes aufgefüllt.
    private static func unicode(_ text: String) -> Data {
        var bytes = Data()
        for unit in text.utf16 { bytes += littleEndian(unit) }
        let padding = (4 - bytes.count % 4) % 4
        return littleEndian(UInt32(bytes.count)) + bytes + Data(count: padding)
    }

    private static let versions = littleEndian(UInt32(1)) + littleEndian(UInt32(1)) + littleEndian(UInt32(1))

    static let version = unicode("Microsoft.Container.DataSpaces") + versions

    static let map: Data = {
        let entryBody = littleEndian(UInt32(1)) + littleEndian(UInt32(0)) + unicode("EncryptedPackage")
            + unicode("StrongEncryptionDataSpace")
        let entry = littleEndian(UInt32(entryBody.count + 4)) + entryBody
        return littleEndian(UInt32(8)) + littleEndian(UInt32(1)) + entry
    }()

    static let info = littleEndian(UInt32(8)) + littleEndian(UInt32(1)) + unicode("StrongEncryptionTransform")

    static let primary: Data = {
        let transformID = unicode("{FF9A3F03-56EF-4613-BDD5-5A41C1D07246}")
        let header = littleEndian(UInt32(8 + transformID.count)) + littleEndian(UInt32(1)) + transformID
        return header + unicode("Microsoft.Container.EncryptionTransform") + versions
            + littleEndian(UInt32(0)) + littleEndian(UInt32(0)) + littleEndian(UInt32(0)) + littleEndian(UInt32(4))
    }()
}
