# iOS 26 design decisions

The app deliberately uses native SwiftUI containers first. On iOS 26, `TabView`,
`NavigationStack`, toolbars, sheets, lists, forms, pickers, and system controls
receive the platform's current Liquid Glass treatment and accessibility behavior
without recreating those controls.

## Structure

- Two top-level tabs only: **总览** and **设置**.
- The total-spend summary is the only custom content surface that explicitly
  uses `glassEffect`. Ordinary list content remains on the content layer.
- The add and edit flow is a modal sheet, not a third top-level page.
- Semantic system colors, SF Symbols, Dynamic Type, VoiceOver labels, and native
  destructive confirmations are used throughout.
- Light, dark, and tinted app-icon appearances are included.

## Product decisions

- Monthly, quarterly, and annual totals count every projected renewal occurrence
  in the selected calendar period.
- Different currencies are shown separately. The app never implies a live
  exchange rate that it did not fetch.
- Reminder permission is requested in context when the user enables or saves a
  reminder, not immediately at first launch.
- The default reminder is three days before renewal at 09:00 and is adjustable.
- Data and notification scheduling stay on device. JSON backup is explicit and
  user initiated.

## Primary references

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)
- [Materials and Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials)
- [SwiftUI `glassEffect`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Scheduling a local notification](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
