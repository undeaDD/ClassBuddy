#!/usr/bin/env python3
# Startseite der Website (GitHub Pages) in beiden Sprachen erzeugen: site/index.html (de) und site/index.en.html (en).
# Alle Texte stehen hier nebeneinander, das Markup nur einmal. Aussehen: site/landing.css.
#
#   python3 scripts/landing-page.py
#
# Texte für Kunden: keine Gedankenstriche, keine Emojis, kein „Fehler“, Feedback über „einen der Feedback-Wege“.
# Store-Links: APP_STORE_URL / PLAY_URL setzen, sobald die Apps veröffentlicht sind (bis dahin Sprung zu #download).
# Stimmen: REVIEWS füllen (nur echte Zitate mit Erlaubnis); leere Einträge erscheinen als Platzhalter.

from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_STORE_URL = ""
PLAY_URL = ""

SCREENS = ["dashboard", "calendar", "notes", "checklists", "students"]
# Leichte Neigung und Versatz je Bild (fest je Bild, damit die Kopien beim Endlos-Durchlauf gleich aussehen)
TILTS = [(-2, 0), (1.5, 10), (-1, -6), (2.2, 4), (-1.6, 8)]
# Pixelgrößen der Geräte-Bilder (feste Breite/Höhe, damit die Galerie schon vor dem Laden richtig steht)
SIZES = {"ipad": (760, 991), "iphone": (420, 859)}

# Stimmen: (Sterne 0 bis 5, Zitat de, Zitat en, Name, Zusatz de, Zusatz en)
REVIEWS = [
    (0, "", "", "", "", ""),
    (0, "", "", "", "", ""),
    (0, "", "", "", "", ""),
]

T = {
    "lang": {"de": "de", "en": "en"},
    "file": {"de": "index.html", "en": "index.en.html"},
    "title": {"de": "ClassBuddy · Der digitale Begleiter für Lehrkräfte", "en": "ClassBuddy · The digital companion for teachers"},
    "description": {
        "de": "Stundenplan, Sitzplan, Bewertungen und Checklisten für Lehrkräfte. Alles lokal auf Ihrem iPad oder iPhone und mit Face ID geschützt.",
        "en": "Timetable, seating plans, assessments and checklists for teachers. Everything stays on your iPad or iPhone, protected by Face ID.",
    },
    "og": {
        "de": "Ihr digitaler Begleiter für den Schulalltag. Alles lokal auf dem Gerät, kein Konto, keine Cloud.",
        "en": "Your digital companion for everyday school life. Everything stays on your device, no account, no cloud.",
    },
    "nav": {
        "de": [("funktionen", "Funktionen"), ("bilder", "Bilder"), ("download", "Download"), ("stimmen", "Stimmen"), ("fragen", "Fragen")],
        "en": [("funktionen", "Features"), ("bilder", "Screenshots"), ("download", "Download"), ("stimmen", "Reviews"), ("fragen", "FAQ")],
    },
    "language": {"de": "Sprache", "en": "Language"},
    "theme": {"de": "Hell oder dunkel", "en": "Light or dark"},
    "toTop": {"de": "Nach oben", "en": "Back to top"},
    "h1": {"de": "Ihr digitaler Begleiter für den <span>Schulalltag</span>", "en": "Your digital companion for <span>school days</span>"},
    "mascotAlt": {"de": "Buddy, das Maskottchen von ClassBuddy", "en": "Buddy, the ClassBuddy mascot"},
    "tabletAlt": {"de": "ClassBuddy auf dem iPad: Übersicht mit Kacheln", "en": "ClassBuddy on iPad: dashboard with cards"},
    "phoneAlt": {"de": "ClassBuddy auf dem iPhone: Kalender", "en": "ClassBuddy on iPhone: calendar"},
    "appStoreAlt": {"de": "Laden im App Store", "en": "Download on the App Store"},
    "playAlt": {"de": "Jetzt bei Google Play", "en": "Get it on Google Play"},
    "stepsEyebrow": {"de": "In drei Schritten startklar", "en": "Ready in three steps"},
    "stepsTitle": {"de": "Einrichten in einer Freistunde", "en": "Set up in a free period"},
    "stepLabel": {"de": "Schritt", "en": "Step"},
    "steps": {
        "de": [
            ("Klasse anlegen", "Kürzel, Fächer und Farbe, dann die Schülerliste. Mit „Weitere anlegen“ geht das in einem Rutsch."),
            ("Stundenplan eintragen", "Leere Stunde antippen, Klasse und Fach wählen, „Jede Woche“. Die Ferien Ihres Bundeslands kommen per Import."),
            ("Sitzplan füllen", "Raum zeichnen, Tische belegen. Ab dann öffnet jede Stunde direkt ihren Sitzplan."),
        ],
        "en": [
            ("Create a class", "Short name, subjects and color, then the student list. With “Add more” it all goes in one go."),
            ("Enter your timetable", "Tap an empty period, choose class and subject, “Every week”. School holidays for your state come in with one import."),
            ("Fill the seating plan", "Draw the room, seat your students. From then on every lesson opens its seating plan directly."),
        ],
    },
    "stepsGuide": {"de": "Schritt für Schritt erklärt in der <a href=\"guide.html\">Anleitung</a>.", "en": "Explained step by step in the <a href=\"guide.en.html\">guide</a>."},
    "featuresEyebrow": {"de": "Funktionen", "en": "Features"},
    "featuresTitle": {"de": "Alles, was Sie im Unterricht brauchen", "en": "Everything you need in class"},
    "featuresLead": {
        "de": "Gemacht für Lehrkräfte an deutschen Schulen und laufend weiterentwickelt, oft direkt aus Wünschen aus dem Lehrerzimmer.",
        "en": "Made for teachers at German schools and constantly improved, often straight from requests in the staff room.",
    },
    "features": {
        "de": [
            ("home-alt", "Übersicht", ["Nächste Stunde, aktueller Raum, Ferien-Countdown, Wetter am Schulort", "Timer, Zufallsauswahl, Gruppen und Lautstärke-Ampel", "Eigene Kacheln für Websites, Dokumente und Kurzbefehle"]),
            ("calendar", "Stundenplan und Kalender", ["Wöchentliche und einmalige Stunden, Doppelstunden, Termine", "Schulferien und Feiertage per Import", "Widget „Jetzt &amp; Als Nächstes“ mit Restzeit"]),
            ("floor-layout", "Räume und Sitzpläne", ["Grundriss zeichnen, auch mit schrägen Tischen", "Schüler per Tipp oder Ziehen setzen, zufällig verteilen", "Sitzplan als PDF"]),
            ("notes", "Bewertungen", ["Mündliche Beobachtungen mit eigener Skala, direkt aus dem Sitzplan", "Klassenarbeiten und Tests mit Notenspiegel", "Notenübersicht als PDF oder Excel. Die Bewertung bleibt bei Ihnen."]),
            ("checkmark-on", "Checklisten und Anwesenheit", ["Wer hat den Elternbrief abgegeben? Mit Fortschritt und Enddatum", "Fehlzeiten und Verspätungen mit wenigen Tipps"]),
            ("board", "Tafelbilder", ["Tafel am Ende der Stunde scannen", "Je Klasse und Fach abgelegt, in der nächsten Stunde griffbereit"]),
        ],
        "en": [
            ("home-alt", "Dashboard", ["Next lesson, current room, holiday countdown, weather at your school", "Timer, random pick, groups and noise meter", "Your own cards for websites, documents and shortcuts"]),
            ("calendar", "Timetable and calendar", ["Weekly and one-off lessons, double lessons, appointments", "School and public holidays by import", "“Now &amp; Next” widget with time remaining"]),
            ("floor-layout", "Rooms and seating plans", ["Draw the floor plan, even with angled tables", "Seat students by tap or drag, or shuffle them", "Seating plan as PDF"]),
            ("notes", "Assessments", ["Oral observations on your own scale, right from the seating plan", "Exams and tests with grade distribution", "Grade overview as PDF or Excel. The grading stays with you."]),
            ("checkmark-on", "Checklists and attendance", ["Who handed in the parent letter? With progress and due date", "Absences and late arrivals in a few taps"]),
            ("board", "Board photos", ["Scan the board at the end of the lesson", "Filed per class and subject, ready for the next lesson"]),
        ],
    },
    "privacyEyebrow": {"de": "Datenschutz an erster Stelle", "en": "Privacy first"},
    "privacyTitle": {"de": "Ihre Daten bleiben im Klassenzimmer", "en": "Your data stays in the classroom"},
    "privacyLead": {
        "de": "ClassBuddy hat keinen Server. Was Sie eintragen, verlässt Ihr Gerät nur, wenn Sie es selbst exportieren.",
        "en": "ClassBuddy has no server. What you enter only leaves your device when you export it yourself.",
    },
    "privacyChecks": {
        "de": ["Kein Konto, kein Tracking, keine Werbung", "Alle Daten lokal, mit der höchsten Datenschutzklasse des Geräts verschlüsselt", "App-Sperre mit Face ID oder Touch ID", "Privatsphäre-Modus blendet Namen und Noten aus, etwa am Beamer", "Export und Import als Excel-Datei", "Quellcode öffentlich einsehbar"],
        "en": ["No account, no tracking, no ads", "All data stays local, encrypted with the device’s highest protection class", "App lock with Face ID or Touch ID", "Privacy mode hides names and grades, for example on a projector", "Export and import as an Excel file", "Source code publicly available"],
    },
    "galleryEyebrow": {"de": "Bilder", "en": "Screenshots"},
    "galleryTitle": {"de": "So sieht ClassBuddy aus", "en": "See ClassBuddy in action"},
    "screenAlts": {
        "de": ["Übersicht", "Kalender", "Bewertungen", "Checklisten", "Schüler"],
        "en": ["Dashboard", "Calendar", "Assessments", "Checklists", "Students"],
    },
    "dotLabel": {"de": "Bild", "en": "Screenshot"},
    "close": {"de": "Schließen", "en": "Close"},
    "previous": {"de": "Vorheriges Bild", "en": "Previous screenshot"},
    "next": {"de": "Nächstes Bild", "en": "Next screenshot"},
    "enlarge": {"de": "Vergrößern", "en": "Enlarge"},
    "downloadEyebrow": {"de": "Download", "en": "Download"},
    "downloadTitle": {"de": "Jetzt kostenlos ausprobieren", "en": "Try it free today"},
    "downloadText": {
        "de": "<b>30 Tage alle Funktionen kostenlos</b>, danach schalten Sie die Vollversion mit einem einmaligen Kauf frei. Kein Abo, keine automatische Verlängerung.",
        "en": "<b>Every feature free for 30 days</b>, then unlock the full version with a one-time purchase. No subscription, no automatic renewal.",
    },
    "reviewsEyebrow": {"de": "Stimmen", "en": "Reviews"},
    "reviewsTitle": {"de": "Aus dem Lehrerzimmer", "en": "From the staff room"},
    "rating": {"de": "Bewertung", "en": "Rating"},
    "faqEyebrow": {"de": "Fragen", "en": "FAQ"},
    "faqTitle": {"de": "Häufige Fragen", "en": "Frequently asked questions"},
    "faq": {
        "de": [
            ("Wo liegen meine Daten?", "Ausschließlich auf Ihrem Gerät. Es gibt kein Konto und keinen ClassBuddy-Server, der Anbieter hat keinen Zugriff auf Ihre Daten. Details in der <a href=\"privacy.html\">Datenschutzerklärung</a>."),
            ("Brauche ich eine Internetverbindung?", "Nein. ClassBuddy funktioniert komplett offline. Nur der Import der Ferien und die Wetter-Kachel brauchen kurz eine Verbindung."),
            ("Darf ich Schülerdaten in ClassBuddy speichern?", "ClassBuddy ist für den datenschutzgerechten Einsatz an deutschen Schulen gebaut: Alles bleibt lokal, verschlüsselt und gesperrt. Ob und welche Daten Sie auf einem privaten Gerät verarbeiten dürfen, regeln Ihr Bundesland und Ihre Schule. Mehr dazu in den Hinweisen für Lehrkräfte in der <a href=\"privacy.html\">Datenschutzerklärung</a>."),
            ("Wie funktioniert die Testphase?", "Am Ende der Einführung starten Sie die Testphase: 30 Tage lang alle Funktionen kostenlos, ohne Abo und ohne automatische Verlängerung. Danach schalten Sie die Vollversion mit einem einmaligen Kauf frei. Möchten Sie nicht kaufen, exportieren Sie Ihre Daten vor dem Ende der Testphase."),
            ("Auf welchen Geräten läuft ClassBuddy?", "Auf iPad und iPhone ab iPadOS und iOS 17.7. Eine Version für Android folgt bei Google Play."),
            ("Kann ich mehrere Klassen und Fächer verwalten?", "Ja, beliebig viele Klassen mit jeweils mehreren Fächern. Stundenplan, Sitzpläne und Bewertungen gelten je Klasse und Fach."),
            ("Was, wenn Schüler auf meinen Bildschirm schauen?", "Ein Tipp auf das Auge oben rechts schaltet den Privatsphäre-Modus ein: Namen, Noten und Notizen sind ausgeblendet, zum Beispiel am Beamer. Ausschalten geht nur mit Face ID, Touch ID oder Code."),
            ("Wie sichere ich meine Daten oder ziehe auf ein neues Gerät um?", "Unter Einstellungen › App-Einstellungen › Exportieren entsteht eine Excel-Datei mit allen Daten. Auf dem neuen Gerät importieren Sie sie an derselben Stelle."),
            ("Was passiert mit meinen Daten, wenn ich die App lösche?", "Sie werden zusammen mit der App gelöscht, denn es gibt keine Kopie auf einem Server. Exportieren Sie vorher, was Sie behalten möchten."),
            ("Rechnet ClassBuddy Noten aus?", "Nein. ClassBuddy sammelt Beobachtungen und Leistungen übersichtlich, die Bewertung bleibt bei Ihnen."),
            ("Gibt es eine Anleitung?", "Ja, die <a href=\"guide.html\">Anleitung</a> erklärt die Einrichtung Schritt für Schritt. Sie finden sie auch in der App unter Einstellungen."),
            ("Gibt es Codes für unsere Schule?", "Ja. Schulen und Fachschaften können Codes für die Vollversion gerne in größeren Mengen anfragen, über einen der Feedback-Wege in der App oder per <a href=\"mailto:dominic.drees@live.de\">E-Mail</a>."),
        ],
        "en": [
            ("Where is my data stored?", "Only on your device. There is no account and no ClassBuddy server, the developer has no access to your data. Details in the <a href=\"privacy.en.html\">privacy policy</a>."),
            ("Do I need an internet connection?", "No. ClassBuddy works completely offline. Only the holiday import and the weather card briefly need a connection."),
            ("May I store student data in ClassBuddy?", "ClassBuddy is built for privacy-compliant use at German schools: everything stays local, encrypted and locked. Whether and which data you may process on a private device is up to your state and your school. More in the notes for teachers in the <a href=\"privacy.en.html\">privacy policy</a>."),
            ("How does the trial work?", "You start the trial at the end of the introduction: every feature free for 30 days, no subscription and no automatic renewal. Afterwards you unlock the full version with a one-time purchase. If you decide not to buy, export your data before the trial ends."),
            ("Which devices does ClassBuddy run on?", "On iPad and iPhone with iPadOS and iOS 17.7 or later. An Android version is coming to Google Play."),
            ("Can I manage several classes and subjects?", "Yes, as many classes as you like, each with several subjects. Timetable, seating plans and assessments apply per class and subject."),
            ("What if students look at my screen?", "One tap on the eye at the top right turns on privacy mode: names, grades and notes are hidden, for example on a projector. Turning it off needs Face ID, Touch ID or your passcode."),
            ("How do I back up my data or move to a new device?", "Settings › App Settings › Export creates an Excel file with all your data. On the new device, import it in the same place."),
            ("What happens to my data if I delete the app?", "It is deleted together with the app, since there is no copy on a server. Export anything you want to keep first."),
            ("Does ClassBuddy calculate grades?", "No. ClassBuddy keeps observations and assessments organized, the grading stays with you."),
            ("Is there a guide?", "Yes, the <a href=\"guide.en.html\">guide</a> explains the setup step by step. You also find it in the app under Settings."),
            ("Are there codes for our school?", "Yes. Schools and departments are welcome to request full version codes in larger quantities, through one of the feedback options in the app or by <a href=\"mailto:dominic.drees@live.de\">email</a>."),
        ],
    },
    "faqSearch": {"de": "Fragen durchsuchen", "en": "Search questions"},
    "faqEmpty": {"de": "Keine passende Frage gefunden. Schreiben Sie uns gern über einen der Feedback-Wege in der App.", "en": "No matching question. Feel free to write to us through one of the feedback options in the app."},
    "faqMore": {"de": "Weitere Antworten auf der <a href=\"support.html\">Support-Seite</a>.", "en": "More answers on the <a href=\"support.en.html\">support page</a>."},
    "footerText": {"de": "Der digitale Begleiter für Lehrkräfte. Gemacht in Deutschland, für den Schulalltag.", "en": "The digital companion for teachers. Made in Germany, for everyday school life."},
    "footerApp": {
        "de": [("guide.html", "Anleitung"), ("support.html", "Support"), ("#fragen", "Häufige Fragen"), ("https://github.com/undeaDD/ClassBuddy", "Quellcode auf GitHub")],
        "en": [("guide.en.html", "Guide"), ("support.en.html", "Support"), ("#fragen", "FAQ"), ("https://github.com/undeaDD/ClassBuddy", "Source code on GitHub")],
    },
    "footerLegalTitle": {"de": "Rechtliches", "en": "Legal"},
    "footerLegal": {
        "de": [("privacy.html", "Datenschutz"), ("imprint.html", "Impressum"), ("licenses.html", "Lizenzen"), ("collaborators.html", "Mitwirkende")],
        "en": [("privacy.en.html", "Privacy"), ("imprint.en.html", "Legal notice"), ("licenses.en.html", "Licenses"), ("collaborators.en.html", "Contributors")],
    },
}

SUN = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>'
MOON = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z"/></svg>'


def badges(lang: str) -> str:
    store = APP_STORE_URL or "#download"
    play = PLAY_URL or "#download"
    return f"""<div class="badges">
        <a class="badge" href="{store}"><img src="images/appstore-{lang}-black.svg" alt="{T['appStoreAlt'][lang]}"></a>
        <a class="badge" href="{play}"><img src="images/googleplay-{lang}.png" alt="{T['playAlt'][lang]}"></a>
      </div>"""


def themed(path: str, classes: str, alt: str) -> str:
    width, height = SIZES[path.split("/")[0]]
    size = f' width="{width}" height="{height}"'
    return (f'<img class="{classes} light-only" src="screenshots/de/{path}" alt="{alt}"{size}>'
            f'<img class="{classes} dark-only" src="screenshots/de-dark/{path}" alt="{alt}"{size}>')


def app_icon(classes: str = "") -> str:
    """App-Icon passend zum Erscheinungsbild (dunkle Variante im dunklen Modus)."""
    prefix = f"{classes} " if classes else ""
    return (f'<img class="{prefix}light-only" src="app-icon.png" alt="">'
            f'<img class="{prefix}dark-only" src="app-icon-dark.png" alt="">')


def gallery(device: str, lang: str) -> str:
    figures = "\n".join(
        f'        <figure style="--tilt: {tilt}deg; --lift: {lift}px" tabindex="0" role="button" aria-label="{alt}: {T["enlarge"][lang]}">'
        f'{themed(f"{device}/{screen}.png", "device", alt)}</figure>'
        for (screen, alt), (tilt, lift) in zip(zip(SCREENS, T["screenAlts"][lang]), TILTS)
    )
    dots = "".join(f'<button type="button" aria-label="{T["dotLabel"][lang]} {i + 1}"></button>' for i in range(len(SCREENS)))
    return f"""    <div class="gallery-wrap {device}">
      <div class="gallery">
{figures}
      </div>
      <div class="dots">{dots}</div>
    </div>"""


def review(entry, lang: str) -> str:
    stars, quote_de, quote_en, name, note_de, note_en = entry
    quote = quote_de if lang == "de" else quote_en
    note = note_de if lang == "de" else note_en
    star_text = "★" * stars + "☆" * (5 - stars)
    cite = f"{escape(name)}<small>{escape(note)}</small>" if name else ""
    return f"""      <figure class="review">
        <div class="stars" aria-label="{T['rating'][lang]}: {stars}/5">{star_text}</div>
        <blockquote>{escape(quote)}</blockquote>
        <cite>{cite}</cite>
      </figure>"""


def page(lang: str) -> str:
    other = "en" if lang == "de" else "de"
    nav = "\n".join(f'      <a href="#{anchor}">{label}</a>' for anchor, label in T["nav"][lang])
    steps = "\n".join(
        f'      <li class="reveal"><span class="node"></span><small>{T["stepLabel"][lang]} {i + 1}</small><h3>{title}</h3><p>{text}</p></li>'
        for i, (title, text) in enumerate(T["steps"][lang])
    )
    features = "\n".join(
        f"""      <article class="feature reveal" style="--src: url(icons/{icon}.svg)">
        <h3>{title}</h3>
        <ul>{''.join(f'<li>{item}</li>' for item in items)}</ul>
      </article>"""
        for icon, title, items in T["features"][lang]
    )
    checks = "\n".join(f"        <li>{item}</li>" for item in T["privacyChecks"][lang])
    reviews = "\n".join(review(entry, lang) for entry in REVIEWS)
    faq = "\n".join(
        f'      <details class="reveal"><summary>{question}</summary><div class="answer"><p>{answer}</p></div></details>'
        for question, answer in T["faq"][lang]
    )
    footer_app = "\n".join(f'          <li><a href="{href}">{label}</a></li>' for href, label in T["footerApp"][lang])
    footer_legal = "\n".join(f'          <li><a href="{href}">{label}</a></li>' for href, label in T["footerLegal"][lang])
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{T['title'][lang]}</title>
<meta name="description" content="{T['description'][lang]}">
<meta property="og:title" content="ClassBuddy">
<meta property="og:description" content="{T['og'][lang]}">
<meta property="og:image" content="https://classbuddy.devsforge.de/app-icon.png">
<link rel="canonical" href="https://classbuddy.devsforge.de/{T['file'][lang] if lang == 'en' else ''}">
<meta property="og:type" content="website">
<meta name="theme-color" content="#f2f2f7">
<link rel="icon" href="app-icon.png">
<link rel="apple-touch-icon" href="app-icon.png">
<link rel="alternate" hreflang="{other}" href="{T['file'][other]}">
<script>
  // Erscheinungsbild vor dem ersten Zeichnen setzen: gespeicherte Wahl, sonst System (ohne Wahl folgt die Seite dem System).
  (function () {{
    var stored = null;
    try {{ stored = localStorage.getItem("theme"); }} catch (error) {{}}
    var dark = stored ? stored === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
    document.documentElement.dataset.theme = dark ? "dark" : "light";
  }})();
</script>
<link rel="stylesheet" href="landing.css">
</head>
<body>

<nav class="nav">
  <div class="wrap">
    <a class="brand" href="#top"><img class="brand-mascot" src="images/mascot-default.png" alt="">ClassBuddy</a>
    <div class="nav-links">
{nav}
    </div>
    <div class="nav-tools">
      <div class="menu" data-menu>
        <button type="button" class="tool" aria-haspopup="true" aria-expanded="false" aria-label="{T['language'][lang]}">{lang.upper()}<img src="icons/nav-arrow-down.svg" alt=""></button>
        <div class="menu-list" role="menu">
          <a role="menuitem" href="index.html" hreflang="de" lang="de"{' aria-current="page"' if lang == "de" else ""}>Deutsch</a>
          <a role="menuitem" href="index.en.html" hreflang="en" lang="en"{' aria-current="page"' if lang == "en" else ""}>English</a>
        </div>
      </div>
      <button type="button" class="tool icon-only" data-theme-toggle aria-label="{T['theme'][lang]}"><span class="light-only">{MOON}</span><span class="dark-only">{SUN}</span></button>
    </div>
  </div>
</nav>

<header class="hero" id="top">
  <div class="wrap">
    <div>
      <div class="wordmark">{app_icon()}<span>ClassBuddy</span></div>
      <h1>{T['h1'][lang]}</h1>
      {badges(lang)}
    </div>
    <div class="stage">
      {themed("ipad/dashboard.png", "device tablet", T['tabletAlt'][lang])}
      {themed("iphone/calendar.png", "device phone", T['phoneAlt'][lang])}
      <img class="mascot" src="images/mascot-default.png" alt="{T['mascotAlt'][lang]}">
    </div>
  </div>
</header>

<section id="so-gehts">
  <div class="wrap">
    <div class="center reveal">
      <span class="eyebrow">{T['stepsEyebrow'][lang]}</span>
      <h2>{T['stepsTitle'][lang]}</h2>
    </div>
    <ol class="timeline">
{steps}
    </ol>
    <p class="lead center reveal">{T['stepsGuide'][lang]}</p>
  </div>
</section>

<section id="funktionen">
  <div class="wrap">
    <div class="center reveal">
      <span class="eyebrow">{T['featuresEyebrow'][lang]}</span>
      <h2>{T['featuresTitle'][lang]}</h2>
      <p class="lead">{T['featuresLead'][lang]}</p>
    </div>
    <div class="features">
{features}
    </div>
  </div>
</section>

<section id="datenschutz">
  <div class="wrap">
    <div class="board reveal">
      <img class="mascot" src="images/mascot-defend.png" alt="">
      <div>
        <span class="eyebrow">{T['privacyEyebrow'][lang]}</span>
        <h2>{T['privacyTitle'][lang]}</h2>
        <p class="lead">{T['privacyLead'][lang]}</p>
      </div>
      <ul class="checks">
{checks}
      </ul>
    </div>
  </div>
</section>

<section id="bilder">
  <input class="gallery-input" type="radio" name="device" id="show-ipad" checked>
  <input class="gallery-input" type="radio" name="device" id="show-iphone">
  <div class="wrap center reveal">
    <span class="eyebrow">{T['galleryEyebrow'][lang]}</span>
    <h2>{T['galleryTitle'][lang]}</h2>
    <div class="tabs">
      <label for="show-ipad">iPad</label>
      <label for="show-iphone">iPhone</label>
    </div>
  </div>
{gallery("ipad", lang)}
{gallery("iphone", lang)}
</section>

<section id="download">
  <div class="wrap">
    <div class="download reveal">
      <img class="mascot" src="images/mascot-trial.png" alt="">
      <div>
        <span class="eyebrow">{T['downloadEyebrow'][lang]}</span>
        <h2>{T['downloadTitle'][lang]}</h2>
        <p class="price">{T['downloadText'][lang]}</p>
        {badges(lang)}
      </div>
    </div>
  </div>
</section>

<section id="stimmen">
  <div class="wrap">
    <div class="center reveal">
      <span class="eyebrow">{T['reviewsEyebrow'][lang]}</span>
      <h2>{T['reviewsTitle'][lang]}</h2>
    </div>
  </div>
  <div class="reviews">
    <div class="reviews-track">
{reviews}
    </div>
  </div>
</section>

<section id="fragen">
  <div class="wrap">
    <div class="faq-head reveal">
      <img class="mascot" src="images/mascot-feedback.png" alt="">
      <div>
        <span class="eyebrow">{T['faqEyebrow'][lang]}</span>
        <h2>{T['faqTitle'][lang]}</h2>
      </div>
    </div>
    <label class="faq-search reveal">
      <img src="icons/search.svg" alt="">
      <input type="search" placeholder="{T['faqSearch'][lang]}" aria-label="{T['faqSearch'][lang]}" autocomplete="off">
    </label>
    <div class="faq">
{faq}
    </div>
    <p class="faq-empty" hidden>{T['faqEmpty'][lang]}</p>
    <p class="lead center">{T['faqMore'][lang]}</p>
  </div>
</section>

<footer>
  <div class="wrap">
    <div class="foot">
      <div>
        <a class="brand" href="#top">{app_icon("brand-icon")}ClassBuddy</a>
        <p class="muted">{T['footerText'][lang]}</p>
      </div>
      <div>
        <h4>App</h4>
        <ul>
{footer_app}
        </ul>
      </div>
      <div>
        <h4>{T['footerLegalTitle'][lang]}</h4>
        <ul>
{footer_legal}
        </ul>
      </div>
    </div>
    <p class="legal">© 2026 Dominic Drees · <a href="https://devsforge.de">Devsforge.de</a></p>
  </div>
</footer>

<dialog class="lightbox" aria-label="{T['galleryTitle'][lang]}">
  <img alt="">
  <button type="button" class="lb-close" aria-label="{T['close'][lang]}"><img src="icons/xmark.svg" alt=""></button>
  <button type="button" class="lb-prev" aria-label="{T['previous'][lang]}"><img src="icons/nav-arrow-left.svg" alt=""></button>
  <button type="button" class="lb-next" aria-label="{T['next'][lang]}"><img src="icons/nav-arrow-right.svg" alt=""></button>
</dialog>

<a class="to-top" href="#top" aria-label="{T['toTop'][lang]}"><img src="icons/nav-arrow-up.svg" alt=""></a>

<script src="landing.js"></script>
</body>
</html>
"""


for lang in ("de", "en"):
    target = ROOT / "site" / T["file"][lang]
    target.write_text(page(lang), encoding="utf-8")
    print(f"✓ {target.relative_to(ROOT)}")
