import Foundation
import Network
import Security
import SwiftData
import UIKit

// Sync zwischen eigenen Geräten im selben Netz, ohne Server: einmal per QR-Code koppeln (gemeinsamer zufälliger
// Schlüssel), danach finden sich die Geräte über Bonjour und verbinden sich verschlüsselt (TLS mit diesem Schlüssel,
// nur gekoppelte Geräte kommen durch). Beide schicken sich ihr Manifest und dann nur, was beim anderen fehlt.

/// Gekoppeltes Gerät. Name und letzter Abgleich in UserDefaults, der Schlüssel in der Keychain (nur dieses Gerät).
struct LocalPairing: Codable, Identifiable, Equatable {
    /// Auf beiden Geräten gleich.
    var id: String
    var peerName: String
    var lastSync: Date?
}

/// Inhalt des QR-Codes: Kopplungs-ID, Schlüssel und Name des zeigenden Geräts.
struct PairingCode: Codable, Equatable {
    var id: String
    var secret: Data
    var name: String

    private static let prefix = "classbuddy-pair:"

    static func make(name: String) -> PairingCode {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return PairingCode(id: UUID().uuidString, secret: Data(bytes), name: name)
    }

    var text: String {
        Self.prefix + ((try? JSONEncoder().encode(self))?.base64EncodedString() ?? "")
    }

    init(id: String, secret: Data, name: String) {
        self.id = id
        self.secret = secret
        self.name = name
    }

    init?(text: String) {
        guard text.hasPrefix(Self.prefix),
              let data = Data(base64Encoded: String(text.dropFirst(Self.prefix.count))),
              let code = try? JSONDecoder().decode(PairingCode.self, from: data),
              code.secret.count == 32, UUID(uuidString: code.id) != nil
        else { return nil }
        self = code
    }
}

nonisolated enum LocalPairingStore {
    private static let listKey = "sync.local.pairings"
    private static let keychainService = "de.devsforge.ClassBuddy.localSync"

    static func all() -> [LocalPairing] {
        UserDefaults.standard.data(forKey: listKey).flatMap { try? JSONDecoder().decode([LocalPairing].self, from: $0) } ?? []
    }

    static func save(_ pairings: [LocalPairing]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(pairings), forKey: listKey)
    }

    static func secret(for id: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: id,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }

    static func storeSecret(_ secret: Data, for id: String) {
        removeSecret(for: id)
        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: id,
            kSecValueData: secret, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func removeSecret(for id: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: id]
        SecItemDelete(query as CFDictionary)
    }
}

/// Nachrichten zwischen zwei Geräten, je mit 4 Byte Länge davor.
enum LocalSyncMessage: Codable {
    struct Hello: Codable {
        var appVersion: String
        var deviceName: String
        var manifest: SyncManifest
    }

    case hello(Hello)
    case package(SyncPackage)
    case done
    case failure(String)
}

/// Lokaler Sync: wartet im Vordergrund auf gekoppelte Geräte (je Kopplung ein Bonjour-Dienst) und verbindet sich
/// auf Wunsch selbst. Alles auf dem Main Thread (Datenmengen sind klein, SwiftData braucht den Haupt-Kontext).
@MainActor
@Observable
final class LocalSyncService {
    enum State: Equatable {
        case idle
        /// QR-Code wird gezeigt, das andere Gerät hat noch nicht gescannt.
        case waitingForScan
        case syncing(peer: String)
        case finished(String)
        case failed(String)
    }

    static let serviceType = "_classbuddy._tcp"

    private(set) var pairings: [LocalPairing] = LocalPairingStore.all()
    private(set) var state: State = .idle
    /// Gezeigter Code, solange das andere Gerät noch nicht gescannt hat.
    private(set) var pendingCode: PairingCode?

    private var context: ModelContext?
    private var deviceName = ""
    private var listeners: [String: NWListener] = [:]
    private var sessions: [ObjectIdentifier: LocalSyncSession] = [:]
    private var browser: NWBrowser?
    private var searchTimeout: Task<Void, Never>?
    /// Bonjour-Name je Gerät: Kopplungs-ID plus Kürzel dieses Geräts (beide Geräte bieten den Dienst an).
    private let deviceTag = String(SyncEngine.deviceID.prefix(8))

    /// Name, unter dem andere Geräte dieses sehen, z. B. „iPad von Dominic“.
    static func deviceName(teacher: TeacherProfile) -> String {
        let model = UIDevice.current.model
        return teacher.firstName.isEmpty ? model : loc("\(model) von \(teacher.firstName)")
    }

    var isBusy: Bool {
        if case .syncing = state { return true }
        return false
    }

    // MARK: Lebenszyklus

    /// App im Vordergrund: auf gekoppelte Geräte warten.
    func start(context: ModelContext, deviceName: String) {
        self.context = context
        self.deviceName = deviceName
        for pairing in pairings where listeners[pairing.id] == nil {
            listen(for: pairing.id)
        }
        if let pendingCode, listeners[pendingCode.id] == nil { listen(for: pendingCode.id) }
    }

    /// App im Hintergrund: Dienste beenden (iOS würde sie ohnehin anhalten).
    func stop() {
        listeners.values.forEach { $0.cancel() }
        listeners = [:]
        browser?.cancel()
        browser = nil
    }

    // MARK: Koppeln

    /// Neuer Code zum Zeigen; das Gerät wartet, bis das andere scannt und sich verbindet.
    func makePairingCode() -> PairingCode {
        if let pendingCode { return pendingCode }
        let code = PairingCode.make(name: deviceName)
        LocalPairingStore.storeSecret(code.secret, for: code.id)
        pendingCode = code
        state = .waitingForScan
        listen(for: code.id)
        return code
    }

    func cancelPairing() {
        guard let pendingCode else { return }
        listeners.removeValue(forKey: pendingCode.id)?.cancel()
        LocalPairingStore.removeSecret(for: pendingCode.id)
        self.pendingCode = nil
        if state == .waitingForScan { state = .idle }
    }

    /// Code des anderen Geräts gescannt: koppeln und gleich abgleichen.
    func pair(with code: PairingCode) {
        LocalPairingStore.storeSecret(code.secret, for: code.id)
        let pairing = LocalPairing(id: code.id, peerName: code.name)
        pairings.removeAll { $0.id == code.id }
        pairings.append(pairing)
        LocalPairingStore.save(pairings)
        listen(for: code.id)
        sync(pairing)
    }

    func remove(_ pairing: LocalPairing) {
        listeners.removeValue(forKey: pairing.id)?.cancel()
        LocalPairingStore.removeSecret(for: pairing.id)
        pairings.removeAll { $0.id == pairing.id }
        LocalPairingStore.save(pairings)
    }

    // MARK: Abgleich

    /// Das andere Gerät suchen (ClassBuddy muss dort geöffnet sein) und abgleichen.
    func sync(_ pairing: LocalPairing) {
        guard !isBusy, let secret = LocalPairingStore.secret(for: pairing.id) else { return }
        state = .syncing(peer: pairing.peerName)
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self, self.browser === browser else { return }
                guard let result = results.first(where: { self.isPeerService($0.endpoint, pairingID: pairing.id) }) else { return }
                self.stopSearching()
                let connection = NWConnection(to: result.endpoint, using: Self.parameters(id: pairing.id, secret: secret))
                self.run(connection, pairingID: pairing.id)
            }
        }
        browser.start(queue: .main)
        searchTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, !Task.isCancelled, self.browser === browser else { return }
            self.stopSearching()
            self.state = .failed(loc("\(pairing.peerName) wurde nicht gefunden. Ist ClassBuddy dort geöffnet und im selben WLAN?"))
        }
    }

    private func stopSearching() {
        searchTimeout?.cancel()
        browser?.cancel()
        browser = nil
    }

    private func isPeerService(_ endpoint: NWEndpoint, pairingID: String) -> Bool {
        guard case .service(let name, _, _, _) = endpoint else { return false }
        return name.hasPrefix(pairingID) && !name.hasSuffix(deviceTag)
    }

    private func listen(for pairingID: String) {
        guard let secret = LocalPairingStore.secret(for: pairingID),
              let listener = try? NWListener(using: Self.parameters(id: pairingID, secret: secret))
        else { return }
        listener.service = NWListener.Service(name: "\(pairingID)-\(deviceTag)", type: Self.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.run(connection, pairingID: pairingID) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed = state { self?.listeners.removeValue(forKey: pairingID)?.cancel() }
            }
        }
        listener.start(queue: .main)
        listeners[pairingID] = listener
    }

    private func run(_ connection: NWConnection, pairingID: String) {
        guard let context else {
            connection.cancel()
            return
        }
        let session = LocalSyncSession(connection: connection, context: context, deviceName: deviceName) { [weak self] session, outcome in
            self?.finish(session, pairingID: pairingID, outcome: outcome)
        }
        sessions[ObjectIdentifier(session)] = session
        if case .syncing = state {} else { state = .syncing(peer: peerName(for: pairingID)) }
        session.start()
    }

    private func finish(_ session: LocalSyncSession, pairingID: String, outcome: LocalSyncSession.Outcome) {
        sessions.removeValue(forKey: ObjectIdentifier(session))
        switch outcome {
        case .success(let peerName, let result):
            completePairing(pairingID, peerName: peerName)
            state = .finished(Self.summary(peer: peerName, result: result))
        case .failure(let message):
            state = .failed(message)
        }
    }

    /// Erste Verbindung nach dem Zeigen des Codes: jetzt erst ist das andere Gerät bekannt.
    private func completePairing(_ pairingID: String, peerName: String) {
        if pendingCode?.id == pairingID { pendingCode = nil }
        if let index = pairings.firstIndex(where: { $0.id == pairingID }) {
            pairings[index].lastSync = .now
            if !peerName.isEmpty { pairings[index].peerName = peerName }
        } else {
            pairings.append(LocalPairing(id: pairingID, peerName: peerName, lastSync: .now))
        }
        LocalPairingStore.save(pairings)
    }

    private func peerName(for pairingID: String) -> String {
        pairings.first { $0.id == pairingID }?.peerName ?? loc("anderem Gerät")
    }

    static func summary(peer: String, result: SyncResult) -> String {
        let changes = result.inserted + result.updated + result.deleted
        guard changes > 0 else { return loc("Mit \(peer) abgeglichen, alles war schon aktuell.") }
        return loc("Mit \(peer) abgeglichen: \(result.inserted) neu, \(result.updated) aktualisiert, \(result.deleted) gelöscht.")
    }

    /// TCP mit TLS 1.2 über den gemeinsamen Schlüssel (PSK); auch direkt zwischen Geräten (Peer-to-Peer-WLAN).
    nonisolated static func parameters(id: String, secret: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        let key = secret.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data(id.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, key as __DispatchData, identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// Eine Verbindung: Hallo (Version, Name, Manifest) austauschen, Pakete austauschen, fertig. Beide Seiten gleich.
@MainActor
final class LocalSyncSession {
    enum Outcome {
        case success(peerName: String, result: SyncResult)
        case failure(String)
    }

    private let connection: NWConnection
    private let context: ModelContext
    private let deviceName: String
    private let onFinish: (LocalSyncSession, Outcome) -> Void
    private var peerName = ""
    private var result: SyncResult?
    private var peerIsDone = false
    private var isFinished = false

    init(connection: NWConnection, context: ModelContext, deviceName: String, onFinish: @escaping (LocalSyncSession, Outcome) -> Void) {
        self.connection = connection
        self.context = context
        self.deviceName = deviceName
        self.onFinish = onFinish
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.handle(state) }
        }
        connection.start(queue: .main)
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            do {
                send(.hello(.init(appVersion: AppInfo.version, deviceName: deviceName, manifest: try SyncEngine.manifest(in: context))))
                receive()
            } catch {
                fail(error.localizedDescription)
            }
        case .failed(let error):
            fail(loc("Verbindung unterbrochen: \(error.localizedDescription)"))
        case .cancelled:
            if !isFinished { fail(loc("Verbindung unterbrochen.")) }
        default:
            break
        }
    }

    private func handle(_ message: LocalSyncMessage) {
        switch message {
        case .hello(let hello):
            peerName = hello.deviceName
            guard hello.appVersion == AppInfo.version else {
                let error = SyncError.versionMismatch(remote: hello.appVersion, local: AppInfo.version)
                send(.failure(error.localizedDescription))
                fail(error.localizedDescription)
                return
            }
            do {
                send(.package(try SyncEngine.makePackage(for: hello.manifest, in: context)))
            } catch {
                fail(error.localizedDescription)
            }
        case .package(let package):
            do {
                result = try SyncEngine.apply(package, in: context)
                send(.done)
                finishIfComplete()
            } catch {
                send(.failure(error.localizedDescription))
                fail(error.localizedDescription)
            }
        case .done:
            peerIsDone = true
            finishIfComplete()
        case .failure(let message):
            fail(message)
        }
    }

    private func finishIfComplete() {
        guard let result, peerIsDone, !isFinished else { return }
        isFinished = true
        connection.cancel()
        onFinish(self, .success(peerName: peerName, result: result))
    }

    private func fail(_ message: String) {
        guard !isFinished else { return }
        isFinished = true
        connection.cancel()
        onFinish(self, .failure(message))
    }

    // MARK: Nachrichten (4 Byte Länge, dann JSON)

    private func send(_ message: LocalSyncMessage) {
        guard let body = try? JSONEncoder().encode(message) else { return }
        var length = UInt32(body.count).bigEndian
        let frame = Data(bytes: &length, count: 4) + body
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, _, error in
            MainActor.assumeIsolated {
                guard let self, !self.isFinished else { return }
                guard error == nil, let header, header.count == 4 else { return }
                let length = Int(header.reduce(0) { $0 << 8 | UInt32($1) })
                self.connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                    MainActor.assumeIsolated {
                        guard error == nil, let body, let message = try? JSONDecoder().decode(LocalSyncMessage.self, from: body) else {
                            self.fail(loc("Die Daten des anderen Geräts konnten nicht gelesen werden."))
                            return
                        }
                        self.handle(message)
                        if !self.isFinished { self.receive() }
                    }
                }
            }
        }
    }
}
