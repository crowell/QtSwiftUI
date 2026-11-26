# QtSwiftUI

QtSwiftUI is a Linux implementation of part of SwiftUI for the Serein port. Applications import `SwiftUI`. Swift evaluates view bodies, tracks state and computes layout. Qt 6 Widgets supplies the window, native controls, input handling, text measurement and shape painting.

![Conversation example running on Ubuntu](Screenshots/conversation.png)

## Run the examples

From a checkout with Docker running, this command builds the Ubuntu 24.04 image, runs the tests and captures both example windows.

```sh
./Scripts/verify-linux.sh
```

Pass a Serein checkout to render its device-link screens, leave-call dialog, call diagnostics window, device card and artwork.

```sh
./Scripts/verify-linux.sh ../serein
```

The script writes PNGs to `Screenshots/`. It compiles ten unchanged Serein source files in a temporary Swift package. The device card uses `AxoContainer`, `CSSFlex`, `CSSGrid`, `AxoTheme`, `AxoColor`, `SuperellipseRect`, `QrCode` and `QRCodeGenerator`. The sample QR encodes `qtswiftui:device-preview`. The account artwork uses `SVGPathData` and `SignalLoginIllustration`. Both fixtures were exercised with Serein revision `ae84e2b`.

The call diagnostics fixture compiles Serein’s original `CallDiagnosticWindow`, localization environment and `SignalI18n` package. A sample WebRTC report exercises the production JSON formatter. The fixture runs the production Axo button, focus ring and spinner with the original theme tokens. Portable text and glyph views stand in for Serein’s CoreText renderer and load its bundled fonts. The integration test checks that Qt selects Inter for the title. A shared Apple and Linux test checks the update order of nested dynamic properties. Its Ubuntu integration test scrolls the report, reads the German title, clicks Close and sends Escape.

![Serein call diagnostics running on Ubuntu](Screenshots/call-diagnostics.png)

Serein’s leave-call fixture runs its unchanged `ConfirmLeaveCallModal`, `AxoConfirmDialog`, `AxoAlertDialog` and `AxoPopper`. It uses the original dialog host, panel, scrolling layout and actions. Linux omits the optional AppKit backdrop blur, which Serein disables by default. The preview uses the same portable text leaves as the diagnostics window. The Ubuntu tests click both buttons through Qt. Apple and Ubuntu tests check the panel edges, shadow and floating-layer placement. To save the Apple rendering of this fixture, set `QTSWIFTUI_DIALOG_REFERENCE` to an absolute PNG path when running `Scripts/check-apple.sh ../serein`.

![Serein leave-call confirmation running on Ubuntu](Screenshots/confirm-leave-call.png)

The device-link fixture runs Serein’s `InstallScreenLinkInProgressStep` and `InstallScreenErrorStep` with the production Signal logo, localized text, masks, buttons and title-bar drag region. The Linux fixture routes two AppKit URL calls through `openURL` and uses a repeating Qt rotation in place of Core Animation. A test checks that the spinner advances while the Swift view graph is idle. Ubuntu tests click through all four error variants and read the combined sync announcement through Qt accessibility. Shared pixel checks cover the logo, button and progress arc. Set `QTSWIFTUI_LINK_REFERENCE` to an existing directory to capture the Apple references. Desktop window movement requires a compositor and is outside the offscreen test.

![Serein device-link error on Ubuntu](Screenshots/link-error.png)

![Serein syncing contacts and groups on Ubuntu](Screenshots/link-device.png)

![Serein device card running on Ubuntu](Screenshots/serein-components.png)

![Serein account artwork drawn with Qt](Screenshots/account-artwork.png)

The key transparency fixture renders the original illustration declaration from Serein’s onboarding dialog in both color schemes. The dialog itself uses AppKit. The artwork exercises transformed clips, even-odd fills and round stroke caps.

![Serein key transparency artwork drawn with Qt](Screenshots/key-transparency.png)

On a Linux desktop with Swift 6.2, `pkg-config` and `qt6-base-dev` installed, run `swift run Conversation` or `swift run Controls`. Qt selects the desktop platform plugin. For headless rendering, set `QT_QPA_PLATFORM=offscreen` and `QTSWIFTUI_SCREENSHOT` to a writable PNG path. `QTSWIFTUI_CAPTURE_DELAY_MS` allows time for asynchronous content before capture.

## Use the library

For a client package alongside this checkout, add `.package(path: "../QtSwiftUI")` to the package dependencies. This product dependency on the app target lets the same source use Apple's SDK on macOS.

```swift
.product(name: "SwiftUI", package: "QtSwiftUI", condition: .when(platforms: [.linux]))
```

## Compatibility and verification

The target is source compatibility with Apple's public SwiftUI APIs. The implementation is partial. The conversation and preferences windows are standalone examples. Serein's complete SignalUI target and app still require more SwiftUI APIs and Linux replacements for direct Apple framework dependencies, including CoreText and AppKit.

| Area | Exercised behavior |
| --- | --- |
| App and views | A single window, view builders, custom views, conditional content and keyed collections |
| Model data | State survives row reordering, bindings edit text, observable models invalidate the view, typed environment injection |
| Layout | Stacks, frames, padding, scrolling, geometry, size proposals, placement and custom layout values used by Serein. Preferences reduce in view-tree order after layout. Anchors position Serein’s floating content in a geometry reader. |
| Controls and rendering | Buttons and custom pressed-state styles, check boxes, text fields, sliders, text, colored surfaces and paths painted by Qt |
| Graphics | Canvas fills and strokes, even-odd paths, gradient stops, affine transforms and path hit testing. The Linux CoreGraphics module supplies geometry for these APIs. |
| Animation | Cubic timing curves interpolate opacity, offsets, rotation angles and trimmed shapes. A shared fixture exercises Serein’s original Axo progress ring. Rotation currently affects painting, while native mouse hit regions retain the unrotated geometry. |
| Links and pointer input | Link activation, accessible link labels, custom URL handling, Qt tooltips and hover callbacks. Ubuntu uses the desktop URL handler for system actions. |
| Scrolling | Native Qt scrolling updates scroll geometry observers. Apple and Ubuntu tests scroll 240 points of content through an 80-point viewport and check old and new values as the offset crosses a threshold. |
| Keyboard input | Programmatic composer focus, native focus changes, sending with Return, Escape commands and selectable monospaced diagnostic text. |
| Lifecycle | An async view task updates an observable model while the Qt event loop runs. An on-change handler observes the result. A timeline also advances to a scheduled date inside the Qt event loop. |

`./Scripts/check-apple.sh ../serein` type-checks the example source with Apple's SwiftUI module on a Mac with Xcode. `./Scripts/check-api.sh` extracts public symbol graphs from Xcode and the Linux image. Pass `--missing` to list missing declaration paths. The inventory groups declarations by symbol kind and path, counts overload spellings separately, and excludes underscored and synthesized members. A shared name alone cannot establish matching signatures, constraints, availability or behavior.

The inventory against the macOS 27.2 SDK found 824 shared declaration paths out of 7,627 and 468 identical declaration spellings out of 8,735. The examples exercise a smaller set at runtime. Navigation, multiwindow scenes, broader animation support, text shaping parity, gestures and platform integration remain substantial gaps. Font metrics, control appearance and several layout behaviors differ from Apple's implementation.

After capturing the Linux examples, run `./Scripts/compare-artwork.sh ../serein` on macOS to render both illustrations with Apple's `ImageRenderer`. At a threshold of 8/255 in any RGB channel, 208 of 119,680 account artwork pixels (0.174%) and 251 of 49,928 key transparency pixels (0.503%) differed. The mean absolute channel differences were 0.128/255 and 0.129/255 respectively. Both reference images are saved in `.build/artwork/`.

The diagnostics package also compiles Serein’s complete `AxoShadow.swift` and generated token definitions. A test draws a clipped, blurred box shadow using its production modifier. Six grayscale samples through the shadow were 0, 90, 143, 201, 244 and 255 on Qt. Apple produced 245 at the fifth sample and matched the other five.

The calling fixture also compiles Serein’s original `CallingAudioIndicator`, SVG parser and icon table. Tests compare the speaking bars’ path bounds on Apple and Ubuntu and sample their pixels during a 200 ms audio-level animation in Qt.

The same package runs Serein’s `AxoChatDateSection` inside a native scroll view. The Apple and Linux tests measure a 204-point scroll, and a separate pixel test checks nested visual offsets, opacity and sibling drawing order. The scrolled label is visible in the Ubuntu capture. The macOS offscreen view cache captures the underlying document at that location, so the live header’s pixel parity remains unverified.

The call-lobby fixture compiles Serein’s original hidden microphone and video shortcut buttons. Native Qt key events exercise Shift+M and Shift+V. Tests also cover duplicate shortcuts in view order, disabled controls, toggles, removal and reassignment. Button styles read their assigned shortcut on Apple and Ubuntu. On Linux, `.command` maps to Meta, `.control` to Ctrl and `.option` to Alt. International keyboard-layout remapping and the Caps Lock and Function modifiers remain unverified.

The framework reference is [Apple's SwiftUI documentation](https://developer.apple.com/documentation/swiftui).
