# PhotosPicker

Apple docs: [PhotosPicker](https://developer.apple.com/documentation/photokit/photospicker),
[photosPicker(isPresented:selection:matching:)](https://developer.apple.com/documentation/swiftui/view/photospicker(ispresented:selection:matching:preferreditemencoding:)).
Planned and decided in new-website#667 and #624.

## API surface

| API | Notes |
|---|---|
| `PhotosPicker(selection:matching:…label:)` for one item or `[PhotosPickerItem]` with `maxSelectionCount`, the titled forms | implemented 2026-11-21: a button that presents the picker sheet |
| `.photosPicker(isPresented:selection:matching:…)`, one item or several | implemented 2026-11-21: the same sheet, presented by the binding |
| `PhotosPickerItem.loadTransferable(type:)`, `supportedContentTypes`, `itemIdentifier` | `Data` gives the photo's bytes; `Image` and other `Transferable` types import from them |
| `PHPickerFilter`, `PhotosPickerSelectionBehavior`, encoding policy | accepted; the library holds still images only, so every filter shows them all |

## The drawn phone's photos (`_PhotoLibrary`)

One library every picker in a page reads, newest first:

1. photos saved while the page runs (`save(_:)`, the share sheet's Save Image, #668);
2. the app's own demo photos: the app package's `Photos` folder (in an app repo, `web/Photos`), named so they sort newest first (`01-…`, `02-…`);
3. the everyday set every app shares, `Fixtures/Photos/Everyday` (freely licensed, credits in
   its `CREDITS.md`; never Apple's sample photos).

`scripts/build-wasm.sh` runs `scripts/photos.py`, which copies 2 and 3 into the bundle's
`assets/photos/` and writes `photos.json` (file, upright width and height). The list is read as
soon as a picker is on screen, and the first 24 photos are asked of the page's image cache
then, so the grid is full while the sheet slides up.

## Behaviour

iOS 27's full sheet (measured on the iPhone 16 simulator, 393 pt wide): a round X and the
Photos | Collections switch on one line, the Private Access banner quoting the app's name (its
display name, else its bundle name; closing it lasts for the page), the photos three across edge
to edge with 5/3 pt gaps, and the bottom bar with •••, Location Included and search, all on
iOS 27 glass (the fork's material plus a light rim and soft shadow, so it shows on white). The
sheet is the fork's standard sheet, so it slides up and is pulled down as on iOS. With one photo
asked for, a tap picks it and the sheet goes; with more, taps number the photos in order and the
check button hands them over. The X cancels and leaves the selection as it was. Collections
shows the library as one album, Recents, which opens Photos.

## Verification (2026-11-21)

`PhotosPickerTests`: saved photos first with their bytes, picked bytes as `Data`, the grid three
across edge to edge, one tap picks, several in order, the X cancels, the first screen
prefetched. Against the simulator (`PhotoProbe` in `swipe-harness/photo-probe-667`): the header,
banner and grid within a point. An unchanged iPhone app's three pickers
in WebKit (a chat's photo button, a camera screen's library button and a contact form's Add a
photo) each open the sheet and get the tapped photo back.

## Not yet covered

Videos and Live Photos, search, the ••• menu, real albums under Collections, the limited-access
flow, and the phone and other formats past the iPhone look.
