# QtSwiftUI

QtSwiftUI is a Linux implementation of part of SwiftUI for the Serein port. Applications import `SwiftUI`. Swift evaluates view bodies, tracks state and computes layout. Qt 6 Widgets supplies the window, native controls, input handling, text measurement and shape painting.

![Conversation example running on Ubuntu](Screenshots/conversation.png)

## Run the examples

From a checkout with Docker running, build the Ubuntu 24.04 image, run the tests and capture both example windows with:

```sh
./Scripts/verify-linux.sh
```

To also render the device card from a Serein checkout:

```sh
./Scripts/verify-linux.sh ../serein
```

The script writes PNGs to `Screenshots/`. The device card compiles eight source files directly from Serein in a temporary Swift package. They provide `AxoContainer`, `CSSFlex`, `CSSGrid`, `AxoTheme`, `AxoColor`, `SuperellipseRect`, `QrCode` and `QRCodeGenerator`. The sample QR contains the preview string `qtswiftui:device-preview`. This fixture was exercised with Serein revision `ae84e2b`.

![Serein device card running on Ubuntu](Screenshots/serein-components.png)

On a Linux desktop with Swift 6.2, `pkg-config` and `qt6-base-dev` installed, run `swift run Conversation` or `swift run Controls`. Qt selects the desktop platform plugin. For headless rendering, set `QT_QPA_PLATFORM=offscreen` and `QTSWIFTUI_SCREENSHOT` to a writable PNG path. `QTSWIFTUI_CAPTURE_DELAY_MS` allows time for asynchronous content before capture.

## Use the library

For a client package alongside this checkout, add `.package(path: "../QtSwiftUI")` to the package dependencies. Add the following product dependency to the app target so the same source can use Apple's SDK on macOS:

```swift
.product(name: "SwiftUI", package: "QtSwiftUI", condition: .when(platforms: [.linux]))
```

## Compatibility and verification

The target is source compatibility with Apple's public SwiftUI APIs. The implementation is partial. The conversation and preferences windows are standalone examples. Serein's complete SignalUI target and app still require more SwiftUI APIs and Linux replacements for direct Apple framework dependencies, including CoreText and AppKit.

| Area | Exercised behavior |
| --- | --- |
| App and views | A single window, view builders, custom views, conditional content and keyed collections |
| Model data | State survives row reordering, bindings edit text, observable models invalidate the view, typed environment injection |
| Layout | Stacks, frames, padding, scrolling, geometry, size proposals, placement and custom layout values used by Serein |
| Controls and rendering | Buttons, check boxes, text fields, sliders, text, colored surfaces and paths painted by Qt |
| Lifecycle | An async view task updates an observable model while the Qt event loop runs. An on-change handler observes the result. |

`./Scripts/check-apple.sh ../serein` type-checks the example source with Apple's SwiftUI module on a Mac with Xcode. `./Scripts/check-api.sh` extracts public symbol graphs from Xcode and the Linux image. Pass `--missing` to list missing declaration paths. The inventory groups declarations by symbol kind and path, counts overload spellings separately, and excludes underscored and synthesized members. A shared name alone cannot establish matching signatures, constraints, availability or behavior.

The initial inventory against the macOS 27.2 SDK found 386 shared declaration paths out of 7,627 and 154 identical declaration spellings out of 8,735. The examples exercise a smaller set at runtime. Navigation, multiwindow scenes, animation, text shaping parity, gestures and platform integration remain substantial gaps. Font metrics, control appearance and several layout behaviors differ from Apple's implementation.

The framework reference is [Apple's SwiftUI documentation](https://developer.apple.com/documentation/swiftui).
