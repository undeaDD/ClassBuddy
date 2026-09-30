import SwiftUI
import UIKit

/// Geräteweiche nach verfügbarer Breite statt nach Gerätetyp: Ein iPad in einem schmalen
/// Fenster (Stage Manager, Split View, Slide Over) verhält sich wie ein iPhone.
/// Wird bei jeder Größenänderung und Drehung neu berechnet (`RootView`).
/// Lesen per `@Environment(\.device)`; alles, was nicht `isPhone` prüft, bleibt beim iPad-Verhalten.
struct Device: Equatable {
    var isPhone: Bool
    var isPad: Bool { !isPhone }

    /// Ein iPhone bleibt auch quer (Pro Max ist dann „regular“) beim iPhone-Layout.
    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        isPhone = horizontalSizeClass == .compact || UIDevice.current.userInterfaceIdiom == .phone
    }
}

extension EnvironmentValues {
    @Entry var device = Device(horizontalSizeClass: .regular)
}
