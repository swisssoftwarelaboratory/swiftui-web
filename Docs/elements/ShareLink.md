# ShareLink

Apple docs: [ShareLink](https://developer.apple.com/documentation/swiftui/sharelink).

## API surface

| API | Notes |
|---|---|
| `ShareLink(item:)`, `ShareLink(items:)`, `ShareLink(_ title, item:)`, `ShareLink(item:label:)`, `ShareLink(items:label:)` with `subject`/`message` | implemented for `URL` and `String` items |
| `ShareLink(item:preview:)`, `ShareLink(items:preview:)`, `ShareLink(_ title, item:preview:)` and the `label:` forms for `Transferable` items; `SharePreview(_:image:icon:)` and the shorter forms | implemented 2026-10-11: an item becomes a `_ShareItem` from its representations in declaration order — a proxy to a `URL` or `String` as a link or text, data with its content type as a file (never imported across types); the preview's title travels, its image and icon are kept for the sheet (which the hosts own) |
| The drawn share sheet (iOS profile, new-website#668) | implemented 2026-11-22: on iOS a press opens iOS 27's share panel (`_ShareSheet`) instead of the host's sharer; see "The drawn share sheet" below |
| `DataRepresentation(exportedContentType:exporting:)` with an `async` exporter | kept (`_TransferExporter.exportAsync`) and awaited by the drawn share sheet (`_PendingShareItem`); drags and pastes still get nothing from it |
| `ShareAction.systemHandler` (`_ShareRequest`: items, subject, message, preview title) | the host's sharer: the browser's Web Share (`navigator.share` with the subject as the title, the message before the texts, the first link as `url`, data as `File`s where `navigator.canShare` accepts them), the native host's `NSSharingServicePicker` (links, texts, the message, image data as `NSImage`s, other data as temporary files) |

## Behaviour

A `ShareLink` is a bordered `Button` whose default label is `Label("Share…", systemImage:
"square.and.arrow.up")`; a press hands a `_ShareRequest` (the items as links, texts or typed
data, the subject, the message, the preview title) to the host's share handler;
`_ShareRequest.files` names data items after the preview title with the content type's
extension and MIME type (PNG, JPEG, text, JSON; else octet-stream). Layout and looks are the
button's and the label's. A `Link` shows the pointing hand while hovered (`pointerStyle(.link)`;
macOS SwiftUI underlines nothing on hover).

## The drawn share sheet (iOS, new-website#668)

On the iOS profile a share link opens iOS 27's share panel over the app. In iOS 27 a ShareLink
shows a glass popover, not a sheet: the panel floats 9 pt from the window's sides and bottom
(375 wide on a 393 pt iPhone), scales up from a hundredth of its size about its own centre while
it fades in (stiffness 331.90, damping 29.149, the popover's spring) and back (283.97, 28.648),
and nothing behind it is dimmed. Its top corners are 38, its bottom corners 46 (the screen's 55,
9 pt in). Inside, 25.67 from its sides and top: the preview (64 pt, `SharePreview`'s image, else a
plain white tile; iOS's own placeholder is never copied) and the title (15 pt semibold); four
made-up people (Anna, Marco, Lea, Nils); the drawn home screen's first two made-up apps and More;
the round actions Copy, Save Image and Assign to Contact (the last two for images) and View More,
on four columns 85.67 apart, 66 pt tiles and circles, 12 pt labels. View More moves the panel to
the full sheet (x 0, y 60, 393 wide, bottom corners 55, 29.33 in) on stiffness 322.27, damping
35.90, with the grouped list (Print, Add to Shared Album, Create Watch Face, Save to Files),
Edit Actions and a close button; View Less moves it back.

A person or an app closes it as if sent; Copy puts the item on the viewer's clipboard
(`ShareAction._copyText`, `_copyImage`: images as PNG, a JPEG redrawn into one, handed to
`navigator.clipboard.write` as a promise); Save Image puts it first in the drawn phone's photos
(`_PhotoLibrary.save`); the rest, a press beside it and the close button close it. An item an
app renders when shared (an async exporter) is asked for once the panel has settled, or at once
when Copy or Save Image needs it: the app's rendering runs on the page's main thread and would
otherwise cost the opening frames. Measured in the iOS 27 simulator with a probe app reading the
panel's layers (swipe-harness `share-probe-668`): the panel's frame, corners and springs exactly,
the rows by pixel from 3x screenshots (the content is drawn by the share service's own process).
`ShareSheetTests` cover opening, Copy, Save Image, a person, View More and a press beside it.

## Measured (macOS 26.2, `sharelink/basic`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Default button | 92 × 25.58: 12 + the 14.5 × 17.5 symbol + 8 + "Share…" (45.5) + 12; the label's 17.5 + 8 | `plain`, pixels |
| Titled | 77.5 wide with "Send" (31) | `titled` |
| Custom label | a 24 pt `Label` makes a 103 × 32 button | `custom`, `customLabel` |

## Verification (2026-09-04)

Tier A: `sharelink/basic` exact. Tier B: Chromium 0.56 %, WebKit 0.50 %, Firefox 0.57 % (the
symbol is the Lucide stand-in). Tier C: 0.39 %. `UnavailableAndShareTests` cover the size and the handler.

## Not yet covered

On the iOS profile the share sheet is our own (above); elsewhere its looks are the host's. Not
drawn: a link's own header (iOS shows the host name in grey and a compass tile), an app's sheet
sliding over the panel when an app is tapped (ours closes as if sent), the preview's icon, a
link inside menus and toolbars. `UnavailableAndShareTests.shareLink` covers the request's items,
message, preview title and files, and the link's pointer.
