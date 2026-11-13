// WebFoundation: the Foundation the substrate and the frameworks import (decision 0017).
//
// On Apple platforms and Linux it is Foundation itself. On wasm it is FoundationEssentials plus
// stand-ins for the value types whose FoundationEssentials members drag the whole library into
// the bundle: `Data`, `URL`, `Calendar`, `TimeZone`, `Locale`, `DateComponents`, `IndexPath`
// and the sort comparators (6.3 MB of wasm for a calendar, measured 2026-09-18). A declaration
// here shadows FoundationEssentials' of the same name for every file that imports this module,
// because this module re-exports FoundationEssentials; a type declared anywhere else would be
// ambiguous next to it. `Date` stays FoundationEssentials' (its member stands alone).
#if os(WASI)
@_exported import FoundationEssentials
// Selector, NSObject and NSObjectProtocol, as Apple's Foundation re-exports them: the Objective-C
// runtime's with the interop SDK (decision 0023), Packages/ObjectiveC's stand-ins without it
// (decision 0026).
@_exported import ObjectiveC
#else
@_exported import Foundation
#endif
