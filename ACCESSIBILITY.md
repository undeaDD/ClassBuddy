# Accessibility

ClassBuddy should be usable by every teacher, including those who rely on VoiceOver, larger text,
reduced motion or a hardware keyboard. This page describes what the app supports today, where it still
falls short, and how to report problems.

## What the app supports

**Built on system components.** The app uses native SwiftUI lists, forms, sheets, menus and toolbars, so most
screens inherit the iOS/iPadOS accessibility behaviour (VoiceOver, Voice Control, Switch Control, Full Keyboard Access).

**VoiceOver**

- Icon-only buttons (toolbars, the class badge, the privacy mode button, the floating controls) have spoken labels,
  and hints where the action isn't obvious
- Many decorative images are hidden from VoiceOver so it reads only what matters
- Selected states (tabs, chosen options) are announced as selected
- With "Tab-Titel ausblenden" the tab bar shows icons only, but VoiceOver still reads the titles
- On iOS/iPadOS 17 and 18 the app's own tab bar is announced as a tab bar

**Text size and display**

- Most text uses Dynamic Type text styles and follows the system text size; long texts shrink slightly instead of being cut off
- In the app's own tab bar (iOS/iPadOS 17 and 18), long-pressing a tab shows the large content viewer
  (big icon and title), as in the system tab bar
- Light and dark mode, plus a selectable accent colour (*Einstellungen → App-Einstellungen*)
- Icon style can be switched between Iconoir, SF Symbols and installed icon packs (*Einstellungen → App-Einstellungen → Icons*)
- **Reduce Motion:** animations such as the wiggling cards in *Anordnen* mode and the tab bar transitions are turned off
- **Reduce Transparency** and **Increase Contrast** are respected by the app's own tab bar (solid background, stronger border)

**Motor and input**

- Hardware keyboard shortcuts: ⌘S save (room editor), ⌘Z / ⇧⌘Z undo and redo (room editor), ⇧⌘P privacy mode,
  ⌘1 to ⌘4 switch tabs (iOS/iPadOS 17 and 18)
- Pointer (trackpad, mouse) hover effects on iPad
- Haptic feedback is optional (*Einstellungen → App-Einstellungen → Haptisches Feedback*, off by default)
- "UI Minimieren" can be turned off so the tab bar never shrinks while scrolling
- "Bildschirm wach halten" keeps the screen on, e.g. while presenting on a board

**Hearing**

- No information is conveyed by sound alone (no spoken audio or video); the timer alarm can be set to vibrate only
  (*Timer nur vibrieren*)

## Known limitations

- **Room editor and seating plan:** both are drawn on a canvas. Tables are chosen by tapping them on the plan,
  so drawing rooms and assigning seats is not yet practical with VoiceOver
- **Icons:** most icons have a fixed size (in every icon style) and don't grow with the text size
- **Very large text sizes:** some cards and calendar cells have limited space; at the largest accessibility sizes,
  texts are shortened or scaled down
- **No full audit yet:** the app has not been formally tested against WCAG or with assistive-technology users.
  Feedback is very welcome (see below)

## Reporting a problem

If something is hard or impossible to use with your setup, please tell us:

- open an [issue](https://github.com/undeaDD/ClassBuddy/issues/new) and mention "Accessibility" in the title, or
- use one of the feedback options in the app

Helpful details: device and iOS/iPadOS version, the assistive technology or setting you use
(e.g. VoiceOver, text size, Voice Control), the screen and what you expected to happen.
Please never include real student data in reports or screenshots.
