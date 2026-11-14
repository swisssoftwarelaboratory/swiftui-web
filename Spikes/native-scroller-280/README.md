# PROTOTYPE: a real Safari scroller driving the canvas (new-website#280)

Throwaway. Never merge.

- `scroller-proto.js` goes into a test page before the app's scripts. `?scroll=native` pins the
  canvas inside an invisible `overflow-y: scroll` box; vertical wheel events reach only the box, so
  Safari scrolls it with its own momentum, bounce and scrolling thread, and each frame the app's
  scroll view is moved to the box's position by one synthetic wheel event. `?scroll=nobounce` adds
  `overscroll-behavior: none`. `?scroll=ours` is unchanged.
- The debug bridge's `scrollViews()` rows gain `maxX, maxY, reached` (ScrollNodes.swift), so the page
  can size the box and skip hidden tabs' scroll views.
- `scroller-280.mjs` checks the three modes in Playwright's WebKit.
