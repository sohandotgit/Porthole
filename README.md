# Porthole

In-app network inspector for iOS/macOS. Captures HTTP/HTTPS and WebSocket traffic and lets you view it with a built-in SwiftUI viewer — no proxy, no certificates, no desktop app.

Fork of [Proxyman/Atlantis](https://github.com/ProxymanApp/atlantis). Original Atlantis streamed captured traffic over Bonjour to the Proxyman desktop app; Porthole removes that dependency and views traffic in-app instead.

### Changes from Atlantis
- Removed the Bonjour transport layer and remote Proxyman integration
- Added a built-in SwiftUI viewer: traffic list + detail view
- Added body search and traffic filtering
- Added export as cURL command and HAR file
- Added clear/pause and a bounded in-memory store (`Atlantis.trafficStore`)
- Replaced the `AtlantisSwiftUIApp` example with `PortholeExample`, wired to the new viewer

## Features
- Automatic HTTP/HTTPS capture, no proxy or certificate trust needed
- WebSocket capture (`URLSessionWebSocketTask`)
- Built-in SwiftUI viewer: list + detail, search, filter
- Export as cURL command or HAR file
- Pause/resume and clear captured traffic

## Requirements
- iOS 16.0+ / macOS 11+ / Mac Catalyst 13.0+ / tvOS 13.0+ / watchOS 10.0+
- Xcode 14+, Swift 5.0+

## Install

Swift Package Manager — add this repo's URL to your project.

## Usage

```swift
import SwiftUI
#if DEBUG
import Atlantis
#endif

@main
struct MyApp: App {
    init() {
        #if DEBUG
        Atlantis.start()
        #endif
    }
}
```

UIKit: call `Atlantis.start()` in `application(_:didFinishLaunchingWithOptions:)`.

### Viewing traffic

```swift
struct DebugTrafficView: View {
    var body: some View {
        NavigationStack {
            AtlantisTrafficListView()
        }
    }
}
```

`AtlantisTrafficListView()` observes `Atlantis.trafficStore` and lists captured requests newest-first; tap a row for full request/response detail.

### Store controls

- `Atlantis.trafficStore.clear()` — wipe captured entries
- `Atlantis.trafficStore.isPaused` — pause/resume capture
- `Atlantis.trafficStore.capacity` — max entries held (default 500)

### Export

- cURL: from the detail view, or `package.curlCommand()`
- HAR: from the list's Export action, or `Atlantis.trafficStore.exportHAR()`

## Example app

`Example/PortholeExample` demonstrates integration end to end.

## Notes

- Debugging tools (Map Local, Breakpoint, Scripting) aren't supported — use a normal proxy for those.
- All captured data lives in memory only; nothing leaves the device and nothing persists after the app closes.

## License

Apache-2.0. See [LICENSE](LICENSE).
