# Window capture load protection

Window thumbnails must remain responsive without allowing a new macOS release to continuously overload the system capture stack.

- On macOS 27 and newer, background capture is suppressed. Opening the switcher still captures fresh thumbnails even when the background preference is enabled.
- On macOS 27 and newer, capture work is limited to two concurrent operations.
- On macOS 27 and newer, startup permission detection uses the lightweight CoreGraphics preflight instead of creating a ScreenCaptureKit shareable-content session.
- Titles and App Icons styles capture only the selected preview and its cycling neighbors; windows without visible thumbnails are skipped.
- Queued work rechecks whether capture is still allowed immediately before entering WindowServer.
