import Foundation
import JavaScriptCore
import Network

/// Programmierbare Kachel: JavaScript (JavaScriptCore) bestimmt Titel, Wert, Untertitel
/// und was beim Antippen passiert. Das Icon bleibt fest.
///
/// Das Skript definiert zwei Funktionen:
/// - `render(ctx)` → `{ title, value, subtitle }` (alles optional, Texte) – synchron
/// - `tap(ctx)` → läuft beim Antippen (darf `async` sein), danach wird neu gezeichnet
///
/// `ctx.state` wird gespeichert (JSON), `ctx.schoolClass` und `ctx.network` sind nur lesbar.
/// Helfer: `open(url)` öffnet einen Link (nur https und App-Links), `toast(text)` zeigt eine Meldung,
/// `await fetch(url, { method, headers, body })` lädt Text – nur in `tap`, nur https, ohne Cookies,
/// eine Anfrage pro Antippen. Keine Dateien, kein Zugriff auf die App-Daten.
nonisolated enum CardScript {
    /// Beispiel, mit dem jede neue Skript-Kachel startet – in der App-Sprache.
    static var example: String {
        AppLanguage.current.resolved == .english ? englishExample : germanExample
    }

    private static let germanExample = """
        // Programmierbare Kachel (JavaScript)
        //
        // render(ctx) bestimmt, was die Kachel zeigt:
        //   { title, value, subtitle }
        // tap(ctx) läuft beim Antippen, danach wird neu gezeichnet.
        //
        // ctx.state        wird gespeichert (z. B. Zähler)
        // ctx.schoolClass  { name, schoolYear, studentCount }
        // ctx.network      { online, type }  type: wifi, cellular, wired, other, none
        // ctx.now          aktuelles Datum
        //
        // open("https://…")  öffnet einen Link oder eine App
        // toast("Text")      zeigt eine kurze Meldung
        //
        // Internet nur in tap – eine Anfrage pro Antippen, höchstens 5 s, nur Text:
        //   async function tap(ctx) {
        //     const res = await fetch("https://…");  // wirft offline einen Fehler
        //     ctx.state.data = await res.json();      // oder res.text(), res.ok, res.status
        //   }
        // render bleibt synchron und zeigt, was in ctx.state steht.

        function render(ctx) {
          const count = ctx.state.count ?? 0;
          return {
            title: "Zähler",
            value: String(count),
            subtitle: `Klasse ${ctx.schoolClass.name} · Antippen zählt hoch`,
          };
        }

        function tap(ctx) {
          ctx.state.count = (ctx.state.count ?? 0) + 1;
          if (ctx.state.count % 10 === 0) {
            toast(`Schon ${ctx.state.count}-mal getippt!`);
          }
        }
        """

    private static let englishExample = """
        // Programmable card (JavaScript)
        //
        // render(ctx) decides what the card shows:
        //   { title, value, subtitle }
        // tap(ctx) runs when the card is tapped, then the card is redrawn.
        //
        // ctx.state        is saved (e.g. a counter)
        // ctx.schoolClass  { name, schoolYear, studentCount }
        // ctx.network      { online, type }  type: wifi, cellular, wired, other, none
        // ctx.now          current date
        //
        // open("https://…")  opens a link or an app
        // toast("Text")      shows a short message
        //
        // Internet only in tap – one request per tap, at most 5 s, text only:
        //   async function tap(ctx) {
        //     const res = await fetch("https://…");  // throws an error when offline
        //     ctx.state.data = await res.json();      // or res.text(), res.ok, res.status
        //   }
        // render stays synchronous and shows what is in ctx.state.

        function render(ctx) {
          const count = ctx.state.count ?? 0;
          return {
            title: "Counter",
            value: String(count),
            subtitle: `Class ${ctx.schoolClass.name} · Tap to count up`,
          };
        }

        function tap(ctx) {
          ctx.state.count = (ctx.state.count ?? 0) + 1;
          if (ctx.state.count % 10 === 0) {
            toast(`Tapped ${ctx.state.count} times already!`);
          }
        }
        """

    struct ClassInfo: Sendable {
        var name: String
        var schoolYear: String
        var studentCount: Int
    }

    struct Output: Sendable, Equatable {
        var title: String?
        var value: String?
        var subtitle: String?
        /// Neuer Zustand als JSON.
        var state: String
        /// Ziel von `open(…)`, ungeprüft – geprüft wird über `urlToOpen`.
        var openTarget: String?
        var toasts: [String] = []
        var error: String?
    }

    enum Mode: String, Sendable {
        case render
        case tap
    }

    /// Längste erlaubte Laufzeit (inkl. Anfrage) – danach zeigt die Kachel einen Fehler.
    static let timeLimit: Duration = .seconds(7)
    private static let requestTimeout: TimeInterval = 5
    private static let maxResponseBytes = 1_000_000
    /// Ohne Cookies und Cache auf der Platte.
    private static let session = URLSession(configuration: .ephemeral)

    /// Führt das Skript im Hintergrund aus. Endlosschleifen blockieren nur ihren eigenen Thread,
    /// nie die Oberfläche; nach `timeLimit` gilt der Lauf als fehlgeschlagen.
    static func run(_ source: String, mode: Mode, state: String, schoolClass: ClassInfo) async -> Output {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Thread.detachNewThread {
                once.resume(evaluate(source, mode: mode, state: state, schoolClass: schoolClass))
            }
            Task {
                try? await Task.sleep(for: timeLimit)
                once.resume(Output(state: state, error: loc("Zeitüberschreitung – läuft das Skript endlos?")))
            }
        }
    }

    /// Synchroner Lauf in einer frischen JavaScript-Umgebung.
    static func evaluate(_ source: String, mode: Mode, state: String, schoolClass: ClassInfo) -> Output {
        guard let context = JSContext() else { return Output(state: state, error: loc("JavaScript nicht verfügbar")) }
        var exception: String?
        context.exceptionHandler = { _, value in
            if exception == nil { exception = value?.toString() }
        }

        let input: [String: Any] = [
            "state": state,
            "schoolClass": ["name": schoolClass.name, "schoolYear": schoolClass.schoolYear, "studentCount": schoolClass.studentCount],
            "mode": mode.rawValue,
            "network": NetworkStatus.shared.snapshot,
        ]
        context.setObject(input, forKeyedSubscript: "__input" as NSString)
        installFetch(in: context)
        context.evaluateScript(prelude)
        context.evaluateScript(source)
        if let exception { return Output(state: state, error: exception) }

        // `__run` ist async; `fetch` antwortet synchron, daher ist alles fertig, sobald der Aufruf zurückkehrt.
        context.evaluateScript("__run()")
        if let exception { return Output(state: state, error: exception) }
        if let error = context.objectForKeyedSubscript("__error"), !error.isUndefined {
            return Output(state: state, error: error.toString())
        }
        guard let result = context.objectForKeyedSubscript("__result"), result.isString else {
            return Output(state: state, error: loc("tap wird nie fertig"))
        }
        guard let data = result.toString().data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return Output(state: state, error: loc("Unerwartetes Ergebnis")) }

        let rendered = json["render"] as? [String: Any] ?? [:]
        let effects = json["effects"] as? [[String: String]] ?? []
        return Output(
            title: text(rendered["title"]),
            value: text(rendered["value"]),
            subtitle: text(rendered["subtitle"]),
            state: json["state"] as? String ?? state,
            openTarget: effects.last(where: { $0["type"] == "open" })?["value"],
            toasts: effects.filter { $0["type"] == "toast" }.compactMap { $0["value"] }
        )
    }

    /// `__fetch(url, options)` für das `fetch` im Prelude: blockiert nur den Skript-Thread.
    /// Fehler (kein https, zu viele Anfragen, Netzwerk) werden als JavaScript-Fehler geworfen.
    private static func installFetch(in context: JSContext) {
        var remaining = 1
        let fetch: @convention(block) (String, JSValue) -> [String: Any]? = { urlString, options in
            func fail(_ message: String) -> [String: Any]? {
                let current = JSContext.current()
                current?.exception = JSValue(newErrorFromMessage: message, in: current)
                return nil
            }
            guard remaining > 0 else { return fail(loc("Nur eine Anfrage pro Antippen")) }
            remaining -= 1
            guard let url = URL(string: urlString), url.scheme?.lowercased() == "https", url.host() != nil else {
                return fail(loc("fetch erlaubt nur https-Adressen"))
            }

            var request = URLRequest(url: url, timeoutInterval: requestTimeout)
            if let method = options.forProperty("method"), method.isString {
                request.httpMethod = method.toString().uppercased()
            }
            if let headers = options.forProperty("headers")?.toDictionary() {
                for (key, value) in headers { request.setValue("\(value)", forHTTPHeaderField: "\(key)") }
            }
            if let body = options.forProperty("body"), body.isString {
                request.httpBody = Data(body.toString().utf8)
            }

            let box = FetchResult()
            let done = DispatchSemaphore(value: 0)
            session.dataTask(with: request) { data, response, error in
                box.set(FetchResult.Value(data: data, response: response as? HTTPURLResponse, error: error))
                done.signal()
            }.resume()
            done.wait()

            let result = box.get()
            if let error = result.error { return fail(loc("fetch fehlgeschlagen: \(error.localizedDescription)")) }
            guard let response = result.response else { return fail(loc("fetch: keine Antwort")) }
            let data = result.data ?? Data()
            guard data.count <= maxResponseBytes else { return fail(loc("fetch: Antwort größer als 1 MB")) }
            guard let body = String(bytes: data, encoding: .utf8) else { return fail(loc("fetch: Antwort ist kein Text")) }
            return [
                "ok": (200..<300).contains(response.statusCode),
                "status": response.statusCode,
                "body": body,
            ]
        }
        context.setObject(fetch, forKeyedSubscript: "__fetch" as NSString)
    }

    /// Zahlen und Texte als Text, alles andere (undefined, Objekte) als „nicht gesetzt“.
    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    /// Text als JavaScript-String-Literal (für übersetzte Fehlermeldungen im Prelude).
    private static func jsString(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let array = String(bytes: data, encoding: .utf8)
        else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    /// Helfer und Ablauf; Ergebnis als JSON, damit nur einfache Werte die Umgebung verlassen.
    /// Bei jedem Lauf neu gebaut, damit Fehlermeldungen in der aktuellen App-Sprache sind.
    private static var prelude: String { """
        const __effects = [];
        function open(url) { __effects.push({ type: "open", value: String(url) }); }
        function toast(text) { __effects.push({ type: "toast", value: String(text) }); }
        var __canFetch = false;
        function fetch(url, options) {
          if (!__canFetch) throw new Error(\(jsString(loc("fetch nur in tap(ctx) – render ist synchron"))));
          const res = __fetch(String(url), options ?? {});
          return Promise.resolve({
            ok: res.ok, status: res.status,
            text: async () => res.body, json: async () => JSON.parse(res.body),
          });
        }
        function __render(ctx) {
          const rendered = typeof render === "function" ? render(ctx) : {};
          if (rendered instanceof Promise) throw new Error(\(jsString(loc("render muss synchron sein – fetch nur in tap(ctx)"))));
          return rendered ?? {};
        }
        var __result, __error;
        function __run() {
          let state = {};
          try { state = JSON.parse(__input.state) ?? {}; } catch (e) {}
          const ctx = { state, schoolClass: __input.schoolClass, network: __input.network, now: new Date() };
          (async () => {
            if (__input.mode === "tap" && typeof tap === "function") {
              __canFetch = true;
              await tap(ctx);
              __canFetch = false;
            }
            const rendered = __render(ctx);
            __result = JSON.stringify({ render: rendered, state: JSON.stringify(ctx.state ?? {}), effects: __effects });
          })().catch(e => { __error = String(e); });
        }
        """
    }
}

extension CardScript.Output {
    /// Nur https und App-Links (wie bei Website-Kacheln), kein http, file, javascript …
    var urlToOpen: URL? { openTarget.flatMap(URL.web) }
}

/// Netzwerkstatus für `ctx.network` (vom System, ohne Anfrage).
private nonisolated final class NetworkStatus: Sendable {
    static let shared = NetworkStatus()
    private let monitor = NWPathMonitor()

    private init() {
        monitor.start(queue: DispatchQueue(label: "CardScript.network"))
    }

    var snapshot: [String: Any] {
        let path = monitor.currentPath
        let online = path.status == .satisfied
        let type = if !online {
            "none"
        } else if path.usesInterfaceType(.wifi) {
            "wifi"
        } else if path.usesInterfaceType(.cellular) {
            "cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            "wired"
        } else {
            "other"
        }
        return ["online": online, "type": type]
    }
}

/// Antwort einer Anfrage, vom URLSession-Thread an den Skript-Thread übergeben.
private nonisolated final class FetchResult: @unchecked Sendable {
    struct Value {
        var data: Data?
        var response: HTTPURLResponse?
        var error: Error?
    }

    private var value = Value()
    private let lock = NSLock()

    func set(_ newValue: Value) {
        lock.withLock { value = newValue }
    }

    func get() -> Value {
        lock.withLock { value }
    }
}

/// Setzt eine Continuation genau einmal fort (Ergebnis oder Zeitüberschreitung, was zuerst kommt).
private nonisolated final class ResumeOnce: @unchecked Sendable {
    private var continuation: CheckedContinuation<CardScript.Output, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<CardScript.Output, Never>) {
        self.continuation = continuation
    }

    func resume(_ output: CardScript.Output) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: output)
    }
}
