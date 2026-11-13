/// Platform constants that SwiftUI does not document. Every value here must be backed by a
/// fixture in `Fixtures/Sources` and recorded in `Docs/elements/`; until measured, a value is
/// marked `// unverified`. The values below are macOS's (the reference profile); `iOS` in
/// PlatformMetricsIOS.swift overrides the ones measured on iOS goldens. Nodes read them through
/// `PlatformMetrics.<name>` (PlatformMetricsAccessors.swift, generated), which resolves against
/// the table of the profile currently laying out: `ViewNode` selects it from its environment's
/// `platformProfile` on every layout and paint entry, so a subtree can render in another
/// platform's look (`.environment(\.platformProfile, .iOS)`).
package final class PlatformMetricsTable: @unchecked Sendable {
    package init() {}

    /// `.padding()` with no length.
    package var defaultPadding: CGFloat = 16          // macOS 26.2: fixture layout/padding-default
    /// Default stack spacing and `Spacer` minimum length.
    package var defaultSpacing: CGFloat = 8           // macOS 26.2: fixtures layout/spacing-default, layout/spacer-min-length
    /// `Divider` thickness.
    package var dividerThickness: CGFloat = 1         // macOS 26.2: fixture layout/divider

    // Bordered buttons (macOS 26.2: fixtures button/basic, button/styles; pixels sampled from goldens)
    package var buttonHeight: CGFloat = 24
    package var buttonHorizontalPadding: CGFloat = 12
    package var buttonLabelSize: CGFloat = 13              // label line is 16 pt: point-size metrics, not .body
    package var buttonCornerRadius: CGFloat = 6
    package var buttonFill = Color(storage: .system(.controlInk), opacityMultiplier: 19.0 / 255)
    package var buttonPressedFill = Color(storage: .system(.controlInk), opacityMultiplier: 50.0 / 255)   // unverified
    /// A bordered button is its label plus 4 pt above and below (32 for a 24 pt Label, label/basic).
    package var buttonVerticalPadding: CGFloat = 4
    // Control sizes (button/looks on macOS 26.6: mini 13, small 16, regular 20, large 28 tall, so
    // the 26.2 regular's 24 shifts by the same amounts; the fonts are AppKit's control fonts;
    // approximate). iOS overrides measure ios/button/looks.
    package var buttonMiniHeight: CGFloat = 17
    package var buttonSmallHeight: CGFloat = 20
    package var buttonLargeHeight: CGFloat = 32
    package var buttonMiniFontSize: CGFloat = 10
    package var buttonSmallFontSize: CGFloat = 11
    package var buttonLargeFontSize: CGFloat = 15
    package var buttonMiniHorizontalPadding: CGFloat = 8
    package var buttonSmallHorizontalPadding: CGFloat = 10
    package var buttonLargeHorizontalPadding: CGFloat = 12
    package var buttonMiniVerticalPadding: CGFloat = 2.5             // a 12 pt line in 17
    package var buttonSmallVerticalPadding: CGFloat = 3.5            // a 13 pt line in 20
    package var buttonLargeVerticalPadding: CGFloat = 7              // an 18 pt line in 32
    package var buttonSmallUsesTextStyle = false                     // iOS: mini and small labels are the subheadline
    // The disabled look (button/looks: a 26.6 inactive window reads the label at 30 % and a
    // plain button's at 50 %; the bezel's fill is unverified). iOS overrides measure ios/button/looks.
    package var buttonDisabledLabelAlpha = 0.3
    package var buttonProminentDisabledLabelAlpha = 0.3
    package var buttonPlainDisabledAlpha = 0.5
    package var buttonDisabledFillAlpha = 0.5
    package var buttonProminentDisabledUsesPlainFill = false         // iOS: a disabled prominent button wears the bordered fill
    package var buttonDestructiveTintsLabel = true                   // a destructive bordered button's red label (unverified on macOS: the inactive window shows none)

    // Toggle (macOS 26.2: fixtures toggle/basic, toggle/styles; pixels sampled from goldens, Docs/elements/Toggle.md)
    package var checkboxSize: CGFloat = 16
    package var checkboxBaseline: CGFloat = 13                   // a bare checkbox's first text baseline (a LabeledContent row puts it 1 below the label's top, label/corners)
    package var checkboxLabelSpacing: CGFloat = 5
    package var checkboxCornerRadius: CGFloat = 5                // from the corner ramp at 2×, approximate
    package var checkboxFillOn = 36.0 / 255
    package var checkboxFillOff = 25.0 / 255
    package var checkboxDisabledFillOn = 18.0 / 255              // approximate
    package var checkboxDisabledFillOff = 13.0 / 255
    // Control sizes and the mixed state (toggle/looks on macOS 26.6: 10 / 12 / 14 / 16 pt boxes for
    // mini / small / regular / large with 9 / 11 / 13 / 13 pt labels, a 2 pt dash across the box's
    // middle when mixed; the 26.2 goldens' 16 pt regular shifts the others; approximate).
    package var checkboxMiniSize: CGFloat = 12
    package var checkboxSmallSize: CGFloat = 14
    package var checkboxLargeSize: CGFloat = 18
    package var controlMiniFontSize: CGFloat = 9
    package var controlSmallFontSize: CGFloat = 11
    package var checkboxMixedDashInset: CGFloat = 4                 // the dash from 4 to 12 of a 16 pt box
    package var checkboxMixedDashWidth: CGFloat = 2
    // Switch sizes (toggle/looks, 26.6: the mini and small switches 15 and 18 tall with 13 and 16 pt
    // knobs next to a 22 pt regular; the 26.2 regular is 24 with a 32 × 20 pill knob; approximate).
    package var switchMiniSize = CGSize(width: 36, height: 16)
    package var switchMiniKnobSize = CGSize(width: 22, height: 14)
    package var switchSmallSize = CGSize(width: 45, height: 20)
    package var switchSmallKnobSize = CGSize(width: 27, height: 16)
    // The knob's soft shadow (toggle/styles pixels: the track reads 51 / 255 next to the knob and
    // 44 two points away, over its 36): two rings around the knob.
    package var switchKnobShadowRingAlpha = 0.045
    package var switchKnobShadowRingSpread: CGFloat = 1
    package var checkboxAccentCheckAlpha = 1.0                      // an active window's checkbox: the accent fill with a white check (unverified)
    package var checkMarkWidth: CGFloat = 2                       // approximate
    package var checkMarkAlpha = 222.0 / 255
    package var checkMarkDisabledAlpha = 66.0 / 255               // approximate
    package var switchSize = CGSize(width: 54, height: 24)
    package var switchKnobSize = CGSize(width: 32, height: 20)
    package var switchKnobInset: CGFloat = 2
    package var switchLabelSpacing: CGFloat = 8
    package var switchTrackOn = 36.0 / 255
    package var switchTrackOff = 25.0 / 255
    /// Disabled control labels keep 30 % of their alpha (66/216 for the primary label colour).
    package var disabledLabelOpacity = 0.3

    // TextField (macOS 26.2: fixtures textfield/basic, textfield/styles; pixels sampled, Docs/elements/TextField.md)
    package var textFieldHeight: CGFloat = 24
    /// A vertical field with several lines: the padding around its lines (textfield/vertical,
    /// ios/textfield/vertical `rounded`).
    package var textFieldMultilinePadding: CGFloat = 8
    /// The ideal width adds this each side of the shown text (textfield/formatted, macOS; iOS unmeasured).
    package var textFieldIdealInset: CGFloat = 2
    package var textFieldHorizontalPadding: CGFloat = 6
    package var textFieldVerticalPadding: CGFloat = 4
    package var textFieldCornerRadius: CGFloat = 5                // approximate: the border ramp reads 5–6 pt
    package var textFieldBorderWidth: CGFloat = 1                 // drawn outside the frame
    package var textFieldBorderAlpha = 23.0 / 255
    package var textFieldDisabledFillAlpha = 192.0 / 255
    package var secureBulletDiameter: CGFloat = 5.5
    package var secureBulletPitch: CGFloat = 8
    package var secureBulletInset: CGFloat = 1.5                  // first bullet's ink starts 7.5 pt in
    package var secureBulletBaselineOffset: CGFloat = 5           // centre 5 pt above the baseline
    // AppKit's keyboard focus ring, measured 2026-10-04 by drawing `NSFocusRingPlacement.only`
    // into a bitmap: a solid 3 pt band outside the shape in `keyboardFocusIndicatorColor` at
    // 50 % ((0, 103, 244) light, (26, 169, 255) dark; Docs/elements/Keyboard.md).
    // hoverEffect (iPadOS pointer effects, approximate: the simulator has no pointer; sw-hover-looks 2026-10-11)
    package var hoverEffectDuration = 0.2
    package var hoverHighlightAlpha = 0.1                         // the translucent rounded rect under a highlighted view
    package var hoverHighlightPadding: CGFloat = 4
    package var hoverHighlightCornerRadius: CGFloat = 8
    package var hoverHighlightScale: CGFloat = 1.03
    package var hoverLiftScale: CGFloat = 1.15
    package var hoverLiftShadowAlpha = 0.2
    package var hoverLiftShadowRadius: CGFloat = 12
    package var hoverLiftShadowOffset: CGFloat = 8
    package var focusRingWidth: CGFloat = 3
    package var focusRingOpacity = 0.5
    package var focusRingColor = Color(storage: .dynamic(light: RGBA(r: 0, g: 103, b: 244, a: 1), dark: RGBA(r: 26, g: 169, b: 255, a: 1)))   // NSColor.keyboardFocusIndicatorColor in Aqua and Dark Aqua (read 2026-10-11; both at 0.498, the opacity above)
    package var focusRingCornerRadius: CGFloat = 6                // unverified: the ring follows the control's own corners
    package var listFocusedSelectionFill = RGBA(r: 52, g: 122, b: 225)   // macOS 27, measured in a key window with the list first responder: the selected row's band, its text white
    package var listFocusedSelectionCornerRadius: CGFloat = 8     // the band's corners (its inset is the selection's 10)
    package var menuHighlightAlpha = 0.1                          // unverified: the keyboard-highlighted menu row
    package var menuHighlightInset: CGFloat = 5
    package var menuHighlightCornerRadius: CGFloat = 4

    // List (macOS 26.2: fixtures list/*, pixels sampled, Docs/elements/List.md)
    package var listInsetMargin: CGFloat = 16
    package var listPlainMargin: CGFloat = 8
    package var listBorderedMargin: CGFloat = 7
    package var listBorderWidth: CGFloat = 1
    package var listBorderColor = Color(storage: .system(.controlInk), opacityMultiplier: 63.0 / 255)
    package var listTopInset: CGFloat = 10
    package var listRowVerticalInset: CGFloat = 4
    package var listRowMinimumHeight: CGFloat = 24
    package var listSidebarRowHeight: CGFloat = 32
    package var listSidebarBackground = Color(red: 240.0 / 255, green: 240.0 / 255, blue: 240.0 / 255)
    package var listSidebarForeground = Color(red: 0, green: 0, blue: 0, opacity: 0.7)
    package var listSectionHeaderPadding: CGFloat = 6
    package var listSectionSpacing: CGFloat = 20
    package var listSeparatorThickness: CGFloat = 1
    package var listSeparatorAlpha = 25.0 / 255
    package var listSelectionInset: CGFloat = 10
    package var listSelectionCornerRadius: CGFloat = 7                 // approximate
    package var listSelectionAlpha = 35.0 / 255
    package var listPinnedHeaderHeight: CGFloat = 27
    package var listPinnedHeaderTextTop: CGFloat = 6                    // list/prominence: the pinned title's line starts 6 down
    package var listAlternateRowFill: RGBA = RGBA(r: 244, g: 245, b: 245)   // list/alternating: every other row, no separators
    package var listOutlineIndent: CGFloat = 9                          // list/outline: rows move in for the chevron column
    package var listOutlineLevelIndent: CGFloat = 13                    // and 13 more per level
    package var listOutlineChevronCentre: CGFloat = 18.5                // the chevron's centre from the list's leading edge, 1 pt grey (127)
    package var listOutlineChevronSize = CGSize(width: 5, height: 5.5)
    package var listOutlineChevronHitRadius: CGFloat = 8                // a press this close to the chevron's centre toggles; the rest of the row selects (sw-list-looks-rest)
    package var listOutlineChevronAlpha = 128.0 / 255
    package var listPinnedHeaderLine: CGFloat = 1
    package var listPinnedHeaderShadowAlpha = 7.0 / 255
    package var listPinnedHeaderLineAlpha = 48.0 / 255
    package var listLabelIconWidth: CGFloat = 16                        // 13 pt font; list/basic `label`
    package var listLabelIconSpacing: CGFloat = 6
    package var listLabelIconScale: Image.Scale? = nil                  // iOS: .large (ios/label/list)
    package var listIdealWidth: CGFloat = 200                           // unverified

    // Controls with labels (Picker, Slider, Stepper; macOS 26.2, Docs/elements/{Picker,Slider,Stepper}.md)
    package var controlLabelSpacing: CGFloat = 8

    // Picker: pop-up button (fixtures picker/*)
    package var popUpHeight: CGFloat = 24
    package var popUpBaseline: CGFloat = 16.75                          // the pop-up's first text baseline (a LabeledContent row puts it 2.75 above an 18.5 label line, label/corners)
    package var popUpTextInset: CGFloat = 12
    package var popUpChevronGap: CGFloat = 18                           // widest option to chevron
    package var popUpChevronWidth: CGFloat = 7
    package var popUpChevronTrailing: CGFloat = 10.5
    package var popUpChevronHalfHeight: CGFloat = 3.5                    // one chevron's rise
    package var popUpChevronOffset: CGFloat = 2.5                        // centre line to chevron base
    package var popUpChevronStroke: CGFloat = 1.5
    package var popUpCornerRadius: CGFloat = 6
    package var popUpFill = 20.0 / 255
    package var popUpDisabledFill = 10.0 / 255
    package var popUpDisabledTextAlpha = 73.0 / 255
    // Picker: segmented control
    package var segmentPadding: CGFloat = 21                             // segment = widest option + 21
    package var segmentedHeight: CGFloat = 24
    package var segmentedFill = 20.0 / 255
    package var segmentedSelectedFill = 50.0 / 255
    package var segmentedCornerRadius: CGFloat = 6
    package var segmentedTextAlpha = 137.0 / 255
    package var segmentedSelectedTextAlpha = 152.0 / 255
    package var segmentedDividerAlpha = 43.0 / 255
    package var segmentedDividerInset: CGFloat = 6                       // approximate
    // Picker: radio group
    package var radioSize: CGFloat = 16
    package var radioLabelSpacing: CGFloat = 5
    package var radioRowSpacing: CGFloat = 6
    package var radioFillOff = 25.0 / 255
    package var radioFillOn = 36.0 / 255
    package var radioDotSize: CGFloat = 5
    package var radioDotAlpha = 216.0 / 255

    // Slider (fixtures slider/*)
    package var sliderHeight: CGFloat = 16
    package var sliderTrackHeight: CGFloat = 5
    package var sliderKnobSize = CGSize(width: 22, height: 16)
    package var sliderKnobInset: CGFloat = 11                            // knob centre travel, each end
    package var sliderFilledAlpha = 58.0 / 255
    package var sliderTrackAlpha = 25.0 / 255
    package var sliderDisabledFilledAlpha = 42.0 / 255
    package var sliderKnobShadowAlpha = 25.0 / 255                       // the knob's blurred shadow (sw-slider-stepper, measured)
    package var sliderKnobShadowRadius: CGFloat = 2
    package var sliderKnobShadowOffset: CGFloat = 1
    package var sliderTickSize: CGFloat = 2
    package var sliderTickTop: CGFloat = 14
    package var sliderIdealWidth: CGFloat = 100                          // unverified

    // Stepper (fixtures stepper/*)
    package var stepperSize = CGSize(width: 20, height: 26)
    package var stepperBaseline: CGFloat = 18.5                             // the control's first text baseline: a grouped form row aligns its label on it, the control 4.5 above the label (form/grouped, macOS 27)
    /// A held stepper repeats after the delay, once per interval (NSStepper's autorepeat).
    package var stepperRepeatDelay: Double = 0.5
    package var stepperRepeatInterval: Double = 0.1
    package var stepperCornerRadius: CGFloat = 5
    package var stepperFill = 20.0 / 255
    package var stepperDisabledFill = 10.0 / 255
    package var stepperChevronAlpha = 137.0 / 255
    package var stepperDisabledChevronAlpha = 132.0 / 255
    package var stepperChevronInset: CGFloat = 4.5                       // x, each side
    package var stepperChevronRise: CGFloat = 5                          // chevron height
    package var stepperChevronStroke: CGFloat = 1.5
    package var stepperUpChevronBase: CGFloat = 9.25                     // y of the up chevron's feet
    package var stepperDownChevronBase: CGFloat = 17.25                  // y of the down chevron's feet
    package var stepperDividerAlpha = 43.0 / 255
    package var stepperDividerInset: CGFloat = 3

    // Default stack spacing of controls (macOS 26.2: form/basic, form/sections row gaps; the 13 pt
    // text spacings 4.7421875 above / 8.15087890625 below, Docs/elements/Form.md)
    package var controlSpacingAbove: CGFloat = 4.7421875
    package var controlSpacingBelow: CGFloat = 8.15087890625
    package var checkboxSpacing: CGFloat = 6
    package var textFieldSpacing: CGFloat = 6

    // Form (macOS 26.2: fixtures form/*, Docs/elements/Form.md)
    package var formSliderRowHeight: CGFloat = 23
    package var formSliderLabelTop: CGFloat = 7
    package var formSliderTrackTop: CGFloat = 1
    package var formGroupedInset: CGFloat = 20
    package var formGroupedRowPadding: CGFloat = 10
    package var formGroupedRowMinimumHeight: CGFloat = 0                    // a row is its content plus the padding (form/grouped: a 16 pt text makes a 36 pt row); 38.5 for a label line
    package var formGroupedCardCornerRadius: CGFloat = 10                  // approximate
    package var formGroupedCardFill = 8.0 / 255
    package var formGroupedSeparatorAlpha = 20.0 / 255
    package var formGroupedSeparatorAlphaDark = 10.0 / 255                   // white over the 37 card (dark/chrome: 47)
    package var formGroupedSeparatorHeight: CGFloat = 1                     // between rows, not overlapping
    package var formLabeledContentRowOffset: CGFloat = 0.125                // a LabeledContent row sits this much lower in its cell (label/corners, macOS 27)
    package var formGroupedSwitchSize = CGSize(width: 36, height: 16)        // approximate (form/styles pixels)
    package var formGroupedSwitchKnobSize = CGSize(width: 22, height: 14)    // approximate
    package var formGroupedSectionSpacing: CGFloat = 10                     // form/grouped (26.6 lays the grouped form out as 26.2): cards 10 apart, a footer 10 under its card
    package var formGroupedHeaderSpacing: CGFloat = 10                      // a header's bottom to its card, a footer's top from its card
    package var formGroupedHeaderTop: CGFloat = 20                          // extra room above a header that follows another section (30 from a footer or card)
    package var formGroupedFooterTrailing = false                           // macOS 27: footers sit at the leading edge under the card in the subheadline font, secondary (26.2: right-aligned, 13 pt); headers body bold

    // Presentations (approximate: separate windows on macOS, Docs/elements/Presentation.md)
    // iOS sheets, alerts, dialogs, the tab bar, the date pills and list selection (iOS 26 on the
    // iPhone SE simulator: ios/sheet/, ios/alert/, ios/dialog/, ios/tabs/, ios/datepicker/compact,
    // ios/list/selection; Docs/elements/iOS.md). macOS keeps its own looks: these defaults are
    // the switches off and the values macOS's nodes never read.
    package var sheetsFillWindow = false                          // iOS: the sheet is the window's width, its content centred
    package var sheetTopInset: CGFloat = 0                        // iOS 27 21 (iOS 26: 31): where the large detent's card starts
    package var sheetCornerRadius: CGFloat = 10                   // iOS 39
    package var sheetMediumHeightFraction: CGFloat = 0.5          // iOS 351/667: the medium detent's height over the window's
    package var sheetMediumSideInset: CGFloat = 0                 // iOS 6: the medium card floats in from the sides
    package var sheetMediumBottomInset: CGFloat = 0               // iOS 6: and from the bottom
    package var sheetGrabberSize: CGSize = CGSize(width: 36, height: 5)
    package var sheetGrabberTop: CGFloat = 5
    package var sheetGrabberAlpha = 0.25                          // iOS: (180) over the card's 239
    package var presentationGlassFill: RGBA = RGBA(r: 239, g: 239, b: 239)   // iOS: the regular material over the dimmed white
    package var alertCornerRadius: CGFloat = 10                   // iOS 34
    package var alertInsets: EdgeInsets = EdgeInsets(top: 21.5, leading: 13.5, bottom: 13, trailing: 13.5)   // iOS: the buttons' insets
    package var alertTextInset: CGFloat = 15                      // iOS: the texts sit 15 further in than the buttons
    package var alertTitleSize: CGFloat = 17
    package var alertMessageSize: CGFloat = 15
    package var alertTitleMessageGap: CGFloat = 10.5
    package var alertMessageButtonsGap: CGFloat = 27
    package var alertButtonHeight: CGFloat = 46.5
    package var alertButtonGap: CGFloat = 8.5
    package var alertButtonFillAlpha = 16.0 / 255                 // iOS: (224) over the card's 239
    package var alertFill: RGBA? = nil                            // iOS 27: the alert's own glass (237) when set, else presentationGlassFill
    package var alertStackedButtonGap: CGFloat = 8                // iOS 27: one or three or more buttons stack 8 apart; two share a row
    package var alertRowButtonInset: CGFloat = 0                  // iOS 27: the two-button row sits 4 further in than the stack
    package var alertTitleLineSpacing: CGFloat = 0                // iOS 27: a wrapped title's lines 5 further apart (one sample)
    package var alertCancelFilled = true                          // iOS 26: the cancel button filled with the accent under white; 27: grey like the rest, bold
    package var alertPlainButtonColorIsAccent = true              // iOS 26: plain buttons in the accent; 27: primary
    package var alertDestructiveColor: RGBA = RGBA(r: 255, g: 56, b: 60)
    package var dialogsArePopovers = false                        // iOS: a confirmation dialog is a glass panel above its source
    package var dialogWidth: CGFloat = 238
    package var dialogCornerRadius: CGFloat = 32.5
    package var dialogInsets: EdgeInsets = EdgeInsets(top: 21.5, leading: 13.5, bottom: 13.5, trailing: 13.5)
    package var dialogTextInset: CGFloat = 15
    package var dialogTitleSize: CGFloat = 17
    package var dialogMessageSize: CGFloat = 17
    package var dialogTitleMessageGap: CGFloat = 4
    package var dialogMessageButtonsGap: CGFloat = 19
    package var dialogButtonHeight: CGFloat = 45.5
    package var dialogButtonGap: CGFloat = 10.5
    package var dialogArrowHeight: CGFloat = 13
    package var dialogArrowWidth: CGFloat = 24                    // approximate: the base of the arrow at the panel's edge
    package var dialogSourceGap: CGFloat = 1.25                   // from the arrow's tip to the source's edge
    package var dialogCentredOnSource = false                     // iOS 27: the panel is centred on its source (no arrow), clamped to the window
    package var dialogGlassFill: RGBA = RGBA(r: 245, g: 246, b: 246)    // iOS: the material over white, no dim
    package var dialogButtonFillAlpha = 16.0 / 255                // (230) over the panel's 245
    package var tabBarAtBottom = false                            // iOS: the floating capsule at the window's bottom
    package var tabBarContentBottomInset: CGFloat = 83            // iOS: the content area ends 83 above the window's bottom
    package var tabBarCapsuleSideInset: CGFloat = 52.5
    package var tabBarCapsuleBottomInset: CGFloat = 23
    package var tabBarCapsuleHeight: CGFloat = 58
    /// The capsule's tint over its blurred ground: white at 31 % (251 over white;
    /// ios/representable/hostingsafearea-tabs over yellow). The glass's refraction is not drawn.
    package var tabBarCapsuleFill: RGBA = RGBA(red: 1, green: 1, blue: 1, alpha: 0.31)
    /// The blur under the capsule (2026-10-09: the UIKit platters' glass, Docs/elements/UIKit/UIView.md).
    package var tabBarGlassSigma: CGFloat = 20
    package var tabBarInnerPadding: CGFloat = 5.625               // the slots share the capsule's width less this at each end
    package var tabPillSize: CGSize = CGSize(width: 93.5, height: 53.5)   // the selected tab's pill, 2 below the capsule's top
    package var tabPillTop: CGFloat = 2
    package var tabPillAlpha = 22.0 / 255                         // (233) over the capsule's 252
    package var tabIconSize: CGFloat = 24                         // the symbol's point size (a house is 26.5 × 23.5)
    package var tabIconTop: CGFloat = 7.5                         // from the pill's top
    package var tabLabelSize: CGFloat = 10
    package var tabLabelBaseline: CGFloat = 44                    // from the pill's top
    package var datePills = false                                 // iOS: the compact picker's values sit in tinted pills
    package var datePillPadding: CGFloat = 13.5                   // each side of the text
    package var datePillCornerRadius: CGFloat = 8
    package var datePillAlpha = 16.0 / 255                        // (239) over white
    package var datePillGap: CGFloat = 5
    package var datePillHeight: CGFloat = 38.5                    // a date alone
    package var dateTimePillHeight: CGFloat = 40                  // rows holding a time
    package var dateTextSize: CGFloat = 17
    package var listSelectionFill: RGBA? = nil                    // iOS (209, 209, 214): an opaque fill over the row
    // iOS edit mode (ios/list/editing): the delete circle and the reorder grip.
    package var listEditLeadingInset: CGFloat = 0                 // iOS 40: the row content moves right of the delete circle
    package var listEditGripWidth: CGFloat = 0                    // iOS 40: the reorder grip's slot at the trailing edge
    package var listEditCircleSize: CGFloat = 22                  // the red disc, 17 in from the card's edge, centred on the row
    package var listEditCircleInset: CGFloat = 17
    package var listEditCircleFill: RGBA = RGBA(r: 255, g: 58, b: 62)
    package var listEditMinusSize: CGSize = CGSize(width: 10.5, height: 2)
    package var listEditGripLineSize: CGSize = CGSize(width: 21.5, height: 1)   // three lines 5 apart, 18 in from the card's trailing edge
    package var listEditGripPitch: CGFloat = 5
    package var listEditGripTrailingInset: CGFloat = 18
    package var listEditGripFill: RGBA = RGBA(r: 197, g: 197, b: 199)
    package var listSelectionCircleFill: RGBA = RGBA(r: 59, g: 134, b: 247)     // ios/list/multiselect (iOS 27): the checked circle; the ring is the grip grey
    package var listSelectionCircleStroke: CGFloat = 1.5
    // Swipe actions and pull to refresh (approximate: no golden can hold a swipe or a pull).
    package var swipeActionMinimumWidth: CGFloat = 74            // a cell is at least this wide
    package var swipeActionPadding: CGFloat = 16                 // each side of the label
    package var swipeFullFraction: CGFloat = 0.6                 // a swipe past this fraction of the row performs the first action
    package var swipeSettleDuration: Double = 0.25               // the row eases to rest (or shut) after a swipe (unmeasured; ease-out)
    package var swipeWheelThreshold: CGFloat = 30                // macOS: a trackpad's sideways scroll past this opens the row's strip
    package var reorderLiftShadowRadius: CGFloat = 8             // the lifted row's shadow while reordering (unmeasured)
    package var reorderLiftShadowAlpha: Double = 0.18
    package var reorderLiftScale: CGFloat = 1.02
    package var refreshRubberBandConstant: CGFloat = 0.55        // UIScrollView's rubber band: offset = (1 − 1 / (x·c/d + 1)) · d
    package var refreshThreshold: CGFloat = 60                   // the resisted pull that starts a refresh
    package var refreshHeight: CGFloat = 60                      // the band the content moves down while refreshing
    package var refreshPullResistance: CGFloat = 0.5             // the finger's distance past the top counts this much

    package var presentationPadding: CGFloat = 20                 // secondary windows and iOS; macOS 27 sheets, alerts and popovers pad nothing (`sheetsCentred`)
    package var sheetsCentred = true                              // macOS 27: sheets and alerts are windows centred in the window, popovers windows with a margin (sw-mac-presentation-looks)
    package var popoverWindowMargin: CGFloat = 13                 // macOS 27 (presentation/mac-popover): the popover window around its content (the arrow and shadow live in it)
    package var presentationCornerRadius: CGFloat = 10
    package var presentationDimAlpha = 0.0                        // macOS 27 (presentation/mac-sheet, mac-alert): the parent window is not dimmed behind a sheet or an alert; iOS dims 20 %
    package var presentationShadowAlpha = 0.12
    package var presentationBorderAlpha = 0.15
    package var sheetMargin: CGFloat = 20
    package var alertWidth: CGFloat = 260                         // macOS 27 (presentation/mac-alert): 260 wide, title 13 bold then 13 the message, 28 pt capsule buttons
    package var alertMacTopInset: CGFloat = 20.5
    package var alertMacTitleMessageGap: CGFloat = 13
    package var alertMacMessageButtonsGap: CGFloat = 17.5
    package var alertMacButtonHeight: CGFloat = 28
    package var alertMacButtonGap: CGFloat = 8
    package var alertMacSideInset: CGFloat = 16
    package var alertMacBottomInset: CGFloat = 16                 // 127 in all with the 20.5 top (the capture: labels centred at 183, the window ending at 213)
    package var alertMacDestructiveFill: RGBA = RGBA(r: 255, g: 220, b: 220)   // the destructive button's capsule (approximate: the capture shows the label's tint)
    package var alertMacButtonFill: RGBA = RGBA(r: 229, g: 229, b: 229)
    package var popoverArrowHeight: CGFloat = 10
    package var popoverArrowWidth: CGFloat = 24
    package var menuGap: CGFloat = 2
    package var menuCornerRadius: CGFloat = 6
    package var menuRowHeight: CGFloat = 22
    package var menuCheckWidth: CGFloat = 22
    package var menuTrailingPadding: CGFloat = 16
    package var menuMinimumWidth: CGFloat = 92.5
    package var menuVerticalPadding: CGFloat = 4
    package var menuSeparatorHeight: CGFloat = 11                       // 5 above and below the line
    package var menuSeparatorInset: CGFloat = 8
    package var menuSeparatorAlpha = 0.1
    package var menuSubmenuChevronGap: CGFloat = 12
    package var menuSubmenuChevronSize = CGSize(width: 4, height: 8)
    package var menuSubmenuChevronStroke: CGFloat = 1.5

    // Menu pull-down button (macOS 26.2: fixture menu/basic, Docs/elements/Menu.md). Shares the
    // pop-up's box, insets and chevron gap; one chevron centred 12 pt before the trailing edge.
    package var pullDownChevronTrailing: CGFloat = 12
    package var pullDownChevronHalfHeight: CGFloat = 1.75
    package var menuSplitGap: CGFloat = 8                               // label to divider
    package var menuSplitDividerWidth: CGFloat = 1
    package var menuSplitDividerInset: CGFloat = 5
    package var menuSplitDividerAlpha = 0.12
    package var menuSplitTrailing: CGFloat = 24                         // divider to trailing edge
    package var menuSplitChevronTrailing: CGFloat = 11.25
    package var menuSplitChevronStroke: CGFloat = 1

    // ProgressView (macOS 26.2: fixtures progress/*, Docs/elements/ProgressView.md; the greys of
    // the inactive golden window)
    package var progressRowHeight: CGFloat = 20
    package var progressTrackColor: RGBA? = nil                        // nil: the ink at progressTrackAlpha
    package var progressFillsWithAccent = false
    package var progressLabelSpacing: CGFloat = 0                      // the linear style's label to its bar
    package var progressCircularIsSpinner = false                      // iOS: the circular style is always the spinner
    package var progressRingRegularDiameter: CGFloat = 32
    package var progressBarHeight: CGFloat = 8
    package var progressBarIdealWidth: CGFloat = 100                  // unverified: no fixture proposes nothing
    package var progressTrackAlpha = 15.0 / 255
    package var progressFillAlpha = 85.0 / 255
    package var progressFillDark = RGBA(r: 170, g: 170, b: 170)                          // opaque in the dark appearance (dark/controls)
    package var progressIndeterminateSegment: CGFloat = 8
    package var progressRingStroke: CGFloat = 5
    package var progressRingTrackAlpha = 13.0 / 255
    package var progressRingFillAlpha = 70.0 / 255
    package func progressRingDiameter(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini: return 12          // unverified
        case .small: return 16
        case .regular: return progressRingRegularDiameter
        case .large, .extraLarge: return progressRingRegularDiameter   // unverified
        }
    }
    package var spinnerSpokes = 8
    package var spinnerPeriod = 1.0                                 // one revolution a second: the dark spoke steps every eighth (approximate)
    package var progressIndeterminatePeriod = 1.5                   // the indeterminate bar's segment crosses the track in 1.5 s (approximate)
    package var spinnerInnerRadius: CGFloat = 6.5                     // approximate: the spinner animates
    package var spinnerOuterRadius: CGFloat = 14
    package var spinnerSpokeWidth: CGFloat = 3
    package var spinnerMaxAlpha = 53.0 / 255
    package var spinnerMinAlpha = 17.0 / 255

    // TabView (macOS 26.2: fixtures tabview/*, Docs/elements/TabView.md)
    package var tabBarHeight: CGFloat = 24
    package var tabBarCornerRadius: CGFloat = 6
    package var tabSegmentPadding: CGFloat = 12                   // each side of a title
    package var tabDividerWidth: CGFloat = 1
    package var tabSelectedInset: CGFloat = 0.5
    package var tabBoxTop: CGFloat = 10
    package var tabBoxCornerRadius: CGFloat = 4.5
    package var tabBoxFillAlpha = 8.0 / 255
    package var tabBoxBorderAlpha = 10.0 / 255                    // approximate: the 245 edge on the 247 fill

    // Gauge (macOS 26.2: fixtures gauge/basic, gauge/accessory, Docs/elements/Gauge.md)
    package var gaugeBarHeight: CGFloat = 16
    package var gaugeBarCornerRadius: CGFloat = 1.5                  // from the corner ramp at 2×
    package var gaugeTrackAlpha = 18.0 / 255
    package var gaugeTrackAlphaDark = 26.0 / 255                     // white in the dark appearance (dark/chrome, macOS 27)
    package var gaugeBoundsSpacing: CGFloat = 8                      // bounds labels to the bar
    package var gaugeAccessoryBarHeight: CGFloat = 8
    package var gaugeAccessorySpacing: CGFloat = 6                   // label, capsule and value in the accessory capacity style
    package var gaugeAccessoryValueSize: CGFloat = 17                // semibold, the accessory linear labels
    package var gaugeAccessoryCapacityValueSize: CGFloat = 12        // the secondary value under the capsule
    package var gaugeAccessoryValueExtraGap: CGFloat = 1             // that value sits 7 under the capsule, not 6
    package var gaugePrimaryAlpha = 216.0 / 255                      // the primary label black (39 over white)
    package var gaugeKnobRadius: CGFloat = 4
    package var gaugeKnobHaloRadius: CGFloat = 8
    package var gaugeRingDiameter: CGFloat = 58
    package var gaugeRingRadius: CGFloat = 26
    package var gaugeRingStroke: CGFloat = 6
    package var gaugeRingTrackAlpha = 76.0 / 255                     // 179 over white
    package var gaugeRingTrimDegrees: Double = 14                    // each end, with bounds labels
    package var gaugeMarkerRadius: CGFloat = 2.5
    package var gaugeMarkerHaloRadius: CGFloat = 4.5                 // approximate
    package var gaugeRingValueSize: CGFloat = 24                     // medium, the centre value
    package var gaugeRingLabelSize: CGFloat = 11
    package var gaugeRingValueLift: CGFloat = 1                      // the centre value sits 1 pt above the centre
    package var gaugeRingEndOffset: CGFloat = 18.385                 // 26 / √2: the arc ends' x and y from the centre

    // DatePicker (macOS 26.2: fixtures datepicker/*, Docs/elements/DatePicker.md; the compact height from 27)
    package var dateFieldHeight: CGFloat = 21                        // the field style
    package var dateCompactHeight: CGFloat = 20                      // the compact and stepper-field styles (macOS 27, regenerated 2026-10-11; 26.2 drew them 22)
    package var dateFieldBorderAlpha = 12.0 / 255                    // 243 over white, drawn outside like a text field's
    package var dateDigitWidth: CGFloat = 8                          // tabular digits at 13 pt
    package var dateSeparatorWidth: CGFloat = 4                      // "/", ":" and the space
    package var dateCommaWidth: CGFloat = 8                          // ", " between the date and the time
    package var datePeriodWidth: CGFloat = 17                        // the AM/PM slot
    package var datePeriodLead: CGFloat = 1                          // the period's text starts a point before its slot
    package var dateFieldInset: CGFloat = 3                          // the field style's content insets
    package var dateFieldTextTop: CGFloat = 1                        // the field style's text line sits 1 pt down, not centred
    package var dateCompactTextTop: CGFloat = 1                      // the compact styles' body line (18.5, baseline 14) sits 1 pt down in the 20: digits bottom at 15 (macOS 27)
    package var dateStepperBezelInset: CGFloat = 1                   // the stepper styles' bezel starts a point in
    package var dateStepperGap: CGFloat = 9.5
    package var dateStepperSize = CGSize(width: 12.5, height: 20)
    package var dateStepperOffset: CGFloat = -0.5                    // the stepper sits half a point above the 20 pt field's top (macOS 27, datepicker/basic)
    package var dateStepperDividerTop: CGFloat = 9.5                 // the divider's top below the stepper's (macOS 27)
    package var dateStepperCornerRadius: CGFloat = 4.5               // approximate
    package var dateStepperDividerInset: CGFloat = 2.5               // approximate
    package var dateStepperChevronInset: CGFloat = 3
    package var dateStepperChevronRise: CGFloat = 3
    package var dateStepperUpChevronBase: CGFloat = 5.5              // y of the up chevron's feet (macOS 27; 26.2: 6.5 in the 22 pt field)
    package var dateStepperDownChevronBase: CGFloat = 13.5           // y of the down chevron's feet
    package var dateSelectionCornerRadius: CGFloat = 2               // unverified: the focused component's highlight
    package var calendarSize = CGSize(width: 138.5, height: 148)
    package var calendarBoxInset = CGSize(width: 0.5, height: 0)
    package var calendarBoxSize = CGSize(width: 137.5, height: 148)
    package var calendarBoxCornerRadius: CGFloat = 3                 // approximate
    package var calendarBoxBorderAlpha = 5.0 / 255                   // approximate: the border is barely there
    package var calendarBoxFillDark = 13.0 / 255                     // the dark appearance fills the box white at 13/255 under a 20/255 edge (dark/chrome)
    package var calendarBoxBorderAlphaDark = 20.0 / 255
    package var calendarHeaderLeading: CGFloat = 3
    package var calendarHeaderCenter: CGFloat = 10                   // the header line's centre below the box's top
    package var calendarWeekdayCenter: CGFloat = 30
    package var calendarFirstRowCenter: CGFloat = 47
    package var calendarCellMargin: CGFloat = 4
    package var calendarCellSize = CGSize(width: 18.5, height: 18)
    package var calendarDayTrailing: CGFloat = 2
    package var calendarWeekdaySize: CGFloat = 10                    // bold
    package var calendarDaySize: CGFloat = 11
    package var calendarMutedAlpha = 66.0 / 255                      // weekday names and the neighbouring months' days (189)
    package var calendarMutedAlphaDark = 146.0 / 255                 // white in the dark appearance (dark/chrome)
    package var calendarHighlightDark = RGBA(r: 70, g: 70, b: 70)    // the selected day's box in the dark appearance (opaque; dark/chrome)
    package var dateFieldFillDark = RGBA(red: 22.0 / 255, green: 22.0 / 255, blue: 22.0 / 255, alpha: 217.0 / 255)   // the dark field's capsule (dark/chrome)
    package var dateFieldBorderDark = RGBA(red: 35.0 / 255, green: 35.0 / 255, blue: 35.0 / 255, alpha: 219.0 / 255)  // its 1 pt edge outside
    package var calendarOutOfRangeAlpha = 66.0 / 255                 // days outside the picker's range (datepicker/looks: 189 on 26.6, which greys the neighbouring months lighter, 230)
    package var graphicalDateTimeSpacing: CGFloat = 18               // the calendar to the clock when both components are graphical (datepicker/looks `both`: 275.5 wide)
    // The iOS wheel (ios/datepicker/wheel, iPhone SE simulator, iOS 26): a 320 × 216 picker whose
    // rows sit on a cylinder (31, 58.5 and 76.5 from the centre), the 23 pt labels shrinking and
    // fading away from the selected row, which lies on a 30 pt band 9 in from both sides.
    package var wheelSize = CGSize(width: 320, height: 216)
    package var wheelRowOffsets: [CGFloat] = [0, 31, 58.5, 76.5]
    package var wheelRowScales: [CGFloat] = [1, 0.9, 0.8, 0.7]
    package var wheelRowAlphas: [Double] = [1, 0.35, 0.33, 0.19]
    package var wheelFontSize: CGFloat = 23
    package var wheelBandHeight: CGFloat = 30
    package var wheelBandInset: CGFloat = 9
    package var wheelBandCornerRadius: CGFloat = 12
    package var wheelBandFill = RGBA(r: 115, g: 115, b: 128, a: 0.08)
    package var wheelMonthLeading: CGFloat = 28.5                    // the month names' left edge
    package var wheelDayTrailing: CGFloat = 192.5                    // the day numbers' right edge
    package var wheelYearLeading: CGFloat = 230
    package var wheelHourTrailing: CGFloat = 94
    package var wheelMinuteLeading: CGFloat = 142
    package var wheelPeriodLeading: CGFloat = 200.5
    package var calendarHighlightAlpha = 35.0 / 255                  // 220
    package var calendarHighlightInset: CGFloat = 1
    package var calendarHighlightCornerRadius: CGFloat = 3           // approximate
    package var calendarArrowSize = CGSize(width: 5.5, height: 7)
    package var calendarDotDiameter: CGFloat = 7
    package var calendarControlGap: CGFloat = 8
    package var calendarControlTrailing: CGFloat = 6
    package var clockSize = CGSize(width: 119, height: 119)
    package var clockCenter = CGPoint(x: 60.25, y: 61.5)             // the dial overflows the view a little
    package var clockRadius: CGFloat = 60
    package var clockRingWidth: CGFloat = 6
    package var clockRingTop = RGBA(red: 209.0 / 255, green: 231.0 / 255, blue: 237.0 / 255, alpha: 1)
    package var clockRingBottom = RGBA(red: 118.0 / 255, green: 118.0 / 255, blue: 118.0 / 255, alpha: 1)
    package var clockInnerShadowWidth: CGFloat = 1.5                 // approximate
    package var clockInnerShadowAlpha = 70.0 / 255                   // 185 at the top, fading out at the bottom
    package var clockFaceColor = RGBA(red: 252.0 / 255, green: 253.0 / 255, blue: 254.0 / 255, alpha: 1)
    package var clockNumeralRadius: CGFloat = 48.5
    package var clockPeriodOffset: CGFloat = 17.5
    package var clockPeriodAlpha = 85.0 / 255                        // 170
    package var clockHourHandLength: CGFloat = 36                    // approximate
    package var clockMinuteHandLength: CGFloat = 52
    package var clockHourHandWidth: CGFloat = 3.5                    // approximate
    package var clockMinuteHandWidth: CGFloat = 2.5                  // approximate
    package var clockCapRadius: CGFloat = 4.5

    // TextEditor (macOS 26.2: fixtures texteditor/*, Docs/elements/TextEditor.md)
    package var textEditorInset: CGFloat = 5                          // the text view's line fragment padding
    package var textEditorLineFactor: CGFloat = 0.955                 // 13 pt → a 12 pt pitch, 22 pt → 21 (unverified)
    package var textEditorBaseSize: CGFloat = 13
    package var textEditorTopGrowth: CGFloat = 0.944                  // the 22 pt title's cap top sits 8.5 down; 13 pt's at the top
    package var textEditorTextColor = RGBA(red: 0, green: 0, blue: 0, alpha: 1)   // pure black, unlike SwiftUI text
    package var textEditorIdealSize = CGSize(width: 100, height: 100)  // unverified

    // Table (macOS 26.2: fixtures table/*, Docs/elements/Table.md)
    package var tableHeaderHeight: CGFloat = 28
    package var tableHeaderTitleInset: CGFloat = 10
    package var tableLineAlpha = 26.0 / 255                          // the header's bottom line and dividers (229)
    package var tableDividerInset: CGFloat = 6                       // the dividers run from 6 to 22
    package var tableRowsTop: CGFloat = 5                            // rows start 33 down
    package var tableRowHeight: CGFloat = 24
    package var tableCellInset: CGFloat = 8                          // a cell's leading inset in its column
    package var tableCellTrailingInset: CGFloat = 6                  // NSTableColumn.width = the SwiftUI width + 14
    package var tableIntercellSpacing: CGFloat = 3                   // between columns; the divider is its last point
    package var tableCellTop: CGFloat = 4
    package var tableLeadingMargin: CGFloat = 8
    package var tableTrailingMargin: CGFloat = 7                     // columns fill the width less 15
    package var tableColumnIdealWidth: CGFloat = 100                 // automatic columns: pitch 117
    package var tableColumnMinWidth: CGFloat = 10                    // unverified (NSTableColumn's default)
    package var tableBandInset: CGFloat = 10
    package var tableBandCornerRadius: CGFloat = 6                   // approximate
    package var tableBandAlpha = 11.0 / 255                          // 244
    package var tableSelectionAlpha = 35.0 / 255                     // 220, the inactive window's selection
    package var tableChevronSize = CGSize(width: 7, height: 4)
    package var tableChevronTrailing: CGFloat = 8                    // from the header cell's end (the next column, or the last column's content end)
    package var tableChevronStroke: CGFloat = 1.5
    package var tableIdealSize = CGSize(width: 300, height: 200)     // unverified
    // sw-table (macOS 27, table/corners and table/outline, 2026-10-11)
    package var tableHiddenHeadersRowsTop: CGFloat = 5               // without headers the rows start 5 down
    package var tableBorderAlpha = 63.0 / 255                        // the bordered style's 1 pt border (192)
    package var tableBorderedMargin: CGFloat = 1                     // its columns run from the border to the border
    package var tableBorderedHeaderTitleOffset: CGFloat = 1          // its titles a point lower
    package var tableHeaderFontSize: CGFloat = 11                    // the titles (26.2 too; drawn at 13 before sw-table)
    package var tableHeaderLineThickness: CGFloat = 1.5              // macOS 27: the header line is 1.5 pt (26.2: 1), from 27; from 28 in the bordered style
    package var tableBorderedFirstColumnIndent: CGFloat = -2         // its first column's title and cells 2 pt less in (9 and 7 from the edge)
    package var tableBorderedRowsTop: CGFloat = 1                    // its rows start 29 down, under a 1 pt line at 28
    package var tableSeparatorAlpha = 25.0 / 255                     // the bordered style's row separators (230)
    package var tableOutlineIndent: CGFloat = 9                      // an outline table's first column: title and cells 9 further in
    package var tableOutlineLevelIndent: CGFloat = 16                // each level of children (unmeasured: the harness cannot expand a row)
    package var tableOutlineChevronOffset: CGFloat = 8.5             // the disclosure chevron's outer edge from the first column's (16.5 to 21.5)
    package var tableOutlineChevronSize = CGSize(width: 5, height: 8)
    package var tableOutlineChevronAlpha = 0.5

    // Painting: a scroll view skips subtrees further than this outside its viewport.
    package var scrollCullMargin: CGFloat = 256

    // ColorPicker (macOS 26.2: fixtures colorpicker/*, Docs/elements/ColorPicker.md)
    package var colorWellSize = CGSize(width: 48, height: 24)
    package var colorWellCornerRadius: CGFloat = 11
    package var colorWellAlpha = 25.0 / 255                          // the well's grey (230)
    package var colorWellActiveColor = Color(storage: .dynamic(light: RGBA(r: 71, g: 145, b: 248, a: 1), dark: RGBA(r: 26, g: 169, b: 255, a: 1)))   // the 3 pt frame while the colour panel targets the well (macOS 27, probed 2026-10-11; dark unverified)
    package var colorWellSwatchInset: CGFloat = 3                    // 42 × 18, concentric corners
    package var colorWellStrokeAlpha = 0.1                           // the 0.5 pt inner stroke
    package var colorWellTopShadeAlpha = 0.15                        // the extra shade along the swatch's top
    package var colorWellDisabledOpacity = 0.5
    package var colorWellBaseline: CGFloat = 22.5                    // the label sits 1.5 pt above the well's bottom in a form
    package var colorPanelSwatchSize: CGFloat = 22                   // unverified: the popover cannot be captured
    package var colorPanelSwatchSpacing: CGFloat = 6

    // NavigationSplitView (macOS 27, regenerated 2026-10-11: fixtures splitview/*, Docs/elements/NavigationSplitView.md;
    // 26.2 floated a white 140 pt panel inset 8 with 7.5 pt corners)
    package var sidebarDefaultWidth: CGFloat = 144                // the sidebar column, from the window's edge
    package var splitContentDefaultWidth: CGFloat = 200
    package var sidebarInset: CGFloat = 0
    package var sidebarCornerRadius: CGFloat = 0
    package var sidebarPanelColor = RGBA(red: 251.0 / 255, green: 251.0 / 255, blue: 251.0 / 255, alpha: 1)   // the sidebar's fill (dark unverified)
    package var sidebarDividerColor = RGBA(red: 201.0 / 255, green: 201.0 / 255, blue: 201.0 / 255, alpha: 1)  // the half-point line after the sidebar
    package var sidebarDividerThickness: CGFloat = 0.5
    package var splitDividerAlpha = 25.0 / 255                    // the 1 pt divider after the content column; black, unverified hue

    // ContentUnavailableView (macOS 26.2: fixture unavailable/basic, Docs/elements/ContentUnavailableView.md)
    package var unavailableSpacing: CGFloat = 12
    package var unavailableTopPadding: CGFloat = 20
    /// macOS 27 / iOS (unavailable/corners, probed 2026-10-11): the symbol's size (36 pt: the
    /// tray is 50 × 37.5 against Apple's 50.5 × 36.5) and its gap to the title; the description
    /// 6 below the label and 12 above what follows; the actions 6 below; the bottom padding of
    /// the view's own height, 20 when there are actions (label 129.5, + description 169.5,
    /// + actions 153.5, all three 193.5).
    package var unavailableIconSize: CGFloat = 36
    package var unavailableIconGap: CGFloat = 24
    package var unavailableDescriptionGap: CGFloat = 6
    package var unavailableDescriptionBottom: CGFloat = 12
    package var unavailableActionsGap: CGFloat = 6
    package var unavailableBottomPadding: CGFloat = 26
    package var unavailableActionsBottomPadding: CGFloat = 20

    // Lazy grids (macOS 26.2: fixture lazy/grids, Docs/elements/Lazy.md)
    package var gridItemSpacing: CGFloat = 8

    // DisclosureGroup (macOS 26.2: fixture disclosure/basic, Docs/elements/DisclosureGroup.md)
    package var disclosureRowPadding: CGFloat = 4
    package var disclosureChevronWidth: CGFloat = 6.5              // the chevron's slot before the 5 pt gap
    package var disclosureChevronHeight: CGFloat = 8
    package var disclosureAnimation: Animation = .default                // the row's press expands or collapses with it (unverified timing)
    package var disclosureChevronSpacing: CGFloat = 5
    package var disclosureChevronSpan: CGFloat = 5.5               // approximate: the chevron's width across its arms
    package var disclosureChevronRise: CGFloat = 3
    package var disclosureChevronStroke: CGFloat = 1.5
    package var disclosureChevronAlpha = 64.0 / 255                // 191 over white

    // Link (macOS 26.2: fixture link/basic, Docs/elements/Link.md)
    package var linkDisabledOpacity = 0.5                            // a disabled link: the plain button style's 50 % (`buttonPlainDisabledAlpha`)

    // GroupBox (macOS 26.2: fixture groupbox/basic, Docs/elements/GroupBox.md)
    package var groupBoxPadding: CGFloat = 5
    package var groupBoxCornerRadius: CGFloat = 12
    package var groupBoxFillAlpha = 8.0 / 255
    package var groupBoxLabelInset: CGFloat = 10
    package var groupBoxLabelSpacing: CGFloat = 3

    // Label (macOS 26.2: fixture label/basic, Docs/elements/Label.md)
    package var labelIconSpacing: CGFloat = 8

    // Text fields' caret and selection (Docs/elements/TextField.md), painted by the scene so the
    // native and browser renders match; unverified (the goldens never focus a field).
    package var textCaretWidth: CGFloat = 1
    package var textCaretUsesAccent = false                   // macOS: the text colour; iOS: the accent
    package var textSelectionColor = RGBA(r: 179, g: 215, b: 255, a: 1)   // NSColor.selectedTextBackgroundColor (approximate)

    // Menu rows (Docs/elements/Menu.md): the check mark in the check column, section headers.
    // Approximate: macOS opens menus in windows the goldens cannot capture.
    package var menuCheckSize = CGSize(width: 9, height: 8)
    package var menuCheckStroke: CGFloat = 1.8
    package var menuCheckInset: CGFloat = 7
    package var menuSectionHeaderSize: CGFloat = 11
    package var menuSectionHeaderHeight: CGFloat = 20
    package var menuIconSize: CGFloat = 13
    package var menuIconGap: CGFloat = 6
    package var menuOpenFillAlpha = 0.08

    // The iOS tab bar's badges (ios/tabs/badges, 2026-10-04): a 20 pt red capsule whose left
    // edge sits 7.5 right of the symbol's centre and whose top 4.5 above the symbol, at least
    // 19.5 wide, its 13 pt text centred.
    package var tabBadgeFontSize: CGFloat = 13
    package var tabBadgeHeight: CGFloat = 20
    package var tabBadgeMinimumWidth: CGFloat = 19.5
    package var tabBadgePadding: CGFloat = 3.75                   // "New" at 13 pt is 27 wide in a 34.5 capsule
    package var tabBadgeLeading: CGFloat = 7.5
    package var tabBadgeRise: CGFloat = 4.5
    package var tabBadgeFill = RGBA(red: 1, green: 59.0 / 255, blue: 48.0 / 255, alpha: 1)

    // The page tab view style's indicator (ios/tabs/page, 2026-10-04): 7 pt dots 18 apart on a
    // row 21.5 above the bottom, the current one white, the others white at 45 % (invisible
    // over a white ground: the window behind them is clear).
    package var pageIndicatorDotDiameter: CGFloat = 7
    package var pageIndicatorDotPitch: CGFloat = 18
    package var pageIndicatorBottomInset: CGFloat = 21.5
    package var pageIndicatorColor = RGBA(red: 1, green: 1, blue: 1, alpha: 1)
    package var pageIndicatorCurrentAlpha = 1.0
    package var pageIndicatorAlpha = 0.45
    package var pageSwipeThreshold: CGFloat = 40

    // Scrolling (Docs/elements/ScrollView.md). Overlay scrollers only show while scrolling, so the
    // goldens cannot show them; the knob was measured from `NSScroller.drawKnob` (2026-09-19).
    package var scrollerThickness: CGFloat = 7            // the knob's core across the track
    package var scrollerInset: CGFloat = 2                // the core's gap to the trailing edge
    package var scrollerEndInset: CGFloat = 4             // the core's gap to the ends of the track
    package var scrollerHaloWidth: CGFloat = 1            // the light rim around the core
    package var scrollerHalo = RGBA(red: 1, green: 1, blue: 1, alpha: 0.15)
    package var scrollerMinimumKnobLength: CGFloat = 20   // unverified
    package var scrollerKnob = RGBA(red: 0, green: 0, blue: 0, alpha: 0.5)
    package var scrollerHoldSeconds = 0.6                 // unverified
    package var scrollerFadeSeconds = 0.25                // unverified
    /// A scroll target behaviour carries the content to its target this long (ease out).
    package var scrollTargetSettleSeconds = 0.35          // unverified
    /// A scroll target behaviour's settle as a critically damped spring of this angular
    /// frequency (per second), started at the finger's speed; 0 eases over the seconds above.
    package var scrollTargetSpring = 0.0
    /// Wheel deltas this far apart belong to separate scrolls (the phase ends, a behaviour settles).
    package var scrollWheelIdleSeconds = 0.15             // unverified
    /// Touch momentum: velocity multiplier per millisecond (UIScrollView's `normal` rate).
    package var scrollDecelerationRate = 0.998
    /// Momentum stops below this speed (points per second).
    package var scrollVelocityFloor: CGFloat = 5
    /// Distance a touch travels before it becomes a pan rather than a press.
    package var panSlop: CGFloat = 10                     // unverified
    /// A finger resting this long before lifting leaves no momentum (seconds).
    package var panRestInterval = 0.1                     // unverified
    /// A finger resting this long on a drag-tracking control (a slider) before moving keeps
    /// the touch from the scroll view around it (UIScrollView's content-touch delay, seconds).
    package var touchHoldInterval = 0.15

    // Geometry and colours only the iOS code paths read (PlatformMetricsIOS.swift sets them from
    // the ios/ goldens); macOS keeps its look through the values above.
    package var switchFrameSize = CGSize(width: 54, height: 24)     // the switch's layout frame; the painted capsule is switchSize
    package var switchOnColor = RGBA(r: 52, g: 199, b: 89)          // iOS systemGreen
    package var switchOffAlpha = 0.09
    package var switchOffAlphaDark = 0.22                            // iOS dark: (57, 57, 60) on black, not measured (Catalyst's switch is Mac-shaped)
    package var switchKnobShadowAlpha = 0.15
    package var sliderFillsWithAccent = false
    package var sliderDisabledAccentAlpha = 0.5
    package var stepperPillInset = CGSize(width: 0, height: 0)
    package var stepperDividerVerticalInset: CGFloat = 4.5
    package var stepperGlyphSize: CGFloat = 13
    package var stepperGlyphStroke: CGFloat = 2
    package var stepperGlyphAlpha = 218.0 / 255
    package var stepperMinusCenterX: CGFloat = 23.5
    package var stepperPlusCenterX: CGFloat = 70
    package var textFieldTextOffset: CGFloat = 0
    package var textFieldPlainExtraHeight: CGFloat = 0
    package var textFieldPlainEmptyExtraHeight: CGFloat = 0
    /// iOS: controls keep the plain 8 pt spacing to their neighbours and let a text's own
    /// distances win (ios/layout/controls: 14.54 under a body text, 8.04 above one).
    package var controlsUsePlainSpacing = false
    package var textFieldPlainTextOffset: CGFloat = 0
    package var textFieldBorderInside = false
    package var textFieldPlaceholder: RGBA? = nil
    package var textFieldPlaceholderDark: RGBA? = nil
    package var segmentedSelectedInset = CGSize(width: 0, height: 0)
    package var segmentedSelectedIsWhite = false
    package var segmentedFontSize: CGFloat = 13
    package var segmentedFontWeight = 400
    package var segmentedSelectedFontWeight = 400
    package var segmentedTextTop: CGFloat = 0                        // 0: centred in the segment
    package var popUpChevronRise: CGFloat = 0                        // 0: the macOS chevron pair
    package var destructiveColor = RGBA(r: 255, g: 57, b: 59)
    // iOS lists, forms and navigation bars (ios/list/*, ios/form/basic, ios/nav/*; Docs/elements/iOS.md).
    package var segmentedSelectedDark = RGBA(r: 191, g: 191, b: 204, a: 120.0 / 255)   // ios/dark/controls: the selected segment over the fill
    package var listGroupedMargin: CGFloat = 16                        // the card's inset from the list's edges
    package var listGroupedContentInset: CGFloat = 16                  // a row's content inside the card
    package var listGroupedCornerRadius: CGFloat = 26
    package var listGroupedRowHeight: CGFloat = 56                     // minimum; else content + 2 × padding
    package var listGroupedRowPadding: CGFloat = 15
    package var listGroupedTopInset: CGFloat = 35                      // above a first card without a header
    package var listGroupedHeaderTop: CGFloat = 27.5                   // card bottom to the next header's text
    package var listGroupedFirstHeaderTop: CGFloat = 10
    package var listGroupedFooterTop: CGFloat = 8                      // card bottom to the footer text (ios/list/footer)
    package var listGroupedFooterToHeader: CGFloat = 16                // a footer's slot to the next header's text (ios/list/footer-header)
    package var menuIsPlainLabel = false                               // iOS: a menu button is its label in the accent colour (ios/menu/basic)
    package var menuDisabledLabelAlpha = 0.0                           // iOS: black at 67/255 when disabled
    package var listGroupedFooterBottom: CGFloat = 23.5                // the footer slot to the next card
    package var listFooterSlotHeight: CGFloat = 21                     // UIKit's footer label for an 18.5 pt footnote line
    package var listGroupedHeaderBottom: CGFloat = 10
    package var listGroupedSectionSpacing: CGFloat = 17.5              // ios/list/spacing: the default `listSectionSpacing`; a header block is 10 + text + 10 below it
    package var listGroupedHeaderPadding: CGFloat = 10
    package var listGroupedCompactSectionSpacing: CGFloat = 12         // ios/list/compact (iOS 27): `.compact` cards 12 apart
    package var listGroupedCompactHeaderTop: CGFloat = 16              // and a header's text 16 below the previous card (27.5 by default)
    package var listPlainHeaderTop: CGFloat = 32
    package var listPlainContentInset: CGFloat = 16
    package var listLinkChevronSize = CGSize(width: 7, height: 12)
    package var listLinkChevronTrailing: CGFloat = 2
    package var listLinkChevronAlpha = 0.3
    package var navigationBarLargeHeight: CGFloat = 117
    package var navigationBarInlineHeight: CGFloat = 64
    package var navigationLargeTitleTop: CGFloat = 65.5
    package var navigationTitleInset: CGFloat = 20
    package var navigationLargeTitleCollapse: CGFloat = 53             // the large title's own height: scrolled past it, the bar is the inline one (ios/nav/scroll)
    package var navigationGlassHeight: CGFloat = 80                    // iOS 26: the bar's tint over scrolled content eases out this far down (ios/nav/scroll)
    // The back button of a pushed screen (ios/nav/push, ios/nav/push-inline): a glass circle at the
    // bar's leading edge with a chevron; the slide of a push or pop is not measurable from goldens.
    // Toolbar items in an iOS navigation bar (ios/sheet/nav, iOS 27 on the iPhone SE, 2026-10-12):
    // 36 pt glass pills 14 down from the bar's top and 20 in from the window's sides, the label in
    // the body size (semibold for a confirmation action), 12 pt of pill either side of it.
    package var navigationBarItemTop: CGFloat = 14
    package var navigationBarItemHeight: CGFloat = 36
    package var navigationBarItemInset: CGFloat = 20
    package var navigationBarItemPadding: CGFloat = 12
    package var navigationBarItemSpacing: CGFloat = 8                  // between two pills of a group (unmeasured)
    // A navigation stack inside a sheet (ios/sheet/nav): its bar, title and items sit 5.5 lower
    // than at the window's top (the row under an inline untitled bar at 104.5 from the card's
    // top, under the large title at 122; 99 and 116.5 at the window's top).
    package var sheetNavigationBarTopInset: CGFloat = 0
    package var navigationBackButtonInset: CGFloat = 10
    package var navigationBackButtonDiameter: CGFloat = 44
    package var navigationBackFill = RGBA(r: 246, g: 246, b: 246, a: 0.66)    // white → 249.5, the grey ground → 243
    package var navigationBackFillDark = RGBA(r: 70, g: 70, b: 70, a: 0.66)   // unmeasured
    package var navigationBackPressedAlpha = 0.1
    package var navigationBackChevronSize = CGSize(width: 8, height: 16)      // tip to tip; 11 × 19 with the stroke
    package var navigationBackChevronOffset = CGPoint(x: -1.5, y: 0.5)        // its centre from the circle's
    package var navigationBackChevronStroke: CGFloat = 3
    package var navigationPushDuration = 0.35
    package var navigationPushParallax: CGFloat = 0.3                         // the lower screen's travel, as a fraction of the width
    package var navigationPushDim = 0.1                                       // black over the lower screen at the end of a push
    // Search (ios/search, iPhone SE simulator, iOS 26, 2026-10-04): a navigation stack's
    // `searchable` field is a 46 pt capsule at the bottom of the screen; presented, it moves
    // down next to a 48 pt cancel circle, the bar hides and the content starts 10 down (54 with
    // the scope bar's band); suggestions replace the content as a plain list in the accent
    // colour. macOS keeps the field in the window toolbar (these metrics are iOS's).
    package var searchBandHeight: CGFloat = 76                                // the band the field takes at rest
    package var searchPresentedBandHeight: CGFloat = 60                       // while presented (the capture has no keyboard)
    package var searchPresentedTopInset: CGFloat = 10                         // the content's top while the bar hides
    package var searchFieldHeight: CGFloat = 46
    package var searchFieldInset: CGFloat = 28                                // from the window's sides at rest
    package var searchPresentedFieldInset: CGFloat = 12
    package var searchFieldTop: CGFloat = 1                                   // below the band's top at rest
    package var searchPresentedFieldTop: CGFloat = 0.5
    package var searchFieldFill = RGBA(r: 252, g: 253, b: 255, a: 0.8)        // (250, 251, 254) over the grey ground, 252 over white
    package var searchFieldShadowAlpha = 0.08
    package var searchFieldShadowRadius: CGFloat = 8
    package var searchFieldShadowOffset: CGFloat = 4
    package var searchMagnifierInset: CGFloat = 20                            // the magnifier's left edge from the capsule's
    package var searchMagnifierSize: CGFloat = 17                             // its symbol's point size (a 16 × 16.5 glyph)
    package var searchTextInset: CGFloat = 48                                 // the text's left edge from the capsule's
    package var searchTextLineHeight: CGFloat = 24.5                          // the body line, centred in the capsule
    package var searchCancelDiameter: CGFloat = 48
    package var searchCancelGap: CGFloat = 12                                 // between the capsule and the cancel circle
    package var searchCancelGlyphSize: CGFloat = 17
    package var searchClearDiameter: CGFloat = 17
    package var searchClearTrailing: CGFloat = 21                             // the clear circle's right edge from the capsule's
    package var searchClearGlyphSize: CGFloat = 9
    package var searchTokenHeight: CGFloat = 28.5
    package var searchTokenPadding: CGFloat = 4.5
    package var searchTokenGap: CGFloat = 3
    package var searchTokenTextGap: CGFloat = 4                               // from the last token to the text
    package var searchTokenCornerRadius: CGFloat = 6
    package var searchTokenFill = RGBA(r: 142, g: 142, b: 147)
    package var searchScopeBandHeight: CGFloat = 44
    package var searchScopeBandInk = 7.0 / 255                                // (248) over white
    package var searchScopeBarTop: CGFloat = 2
    package var searchScopeBarHeight: CGFloat = 32
    package var searchScopeInset: CGFloat = 16
    package var searchScopeSelectedInset: CGFloat = 2
    package var searchScopeFill = RGBA(r: 252, g: 252, b: 252)
    package var searchScopeSelectedFill = RGBA(r: 234, g: 234, b: 234)
    package var searchScopeFontSize: CGFloat = 15
    package var searchScopeShadowAlpha = 0.08
    package var searchScopeShadowRadius: CGFloat = 5
    package var searchScopeShadowOffset: CGFloat = 4
    package var searchSuggestionSeparatorInset: CGFloat = 16                  // the list's top separator, from both sides
}

/// The metrics of the profile currently laying out or painting (see `PlatformMetricsTable`).
package enum PlatformMetrics {
    nonisolated(unsafe) package static var current: PlatformMetricsTable = .macOS

    /// Makes `profile`'s table current; returns the previous one for `restore`.
    @inline(__always)
    package static func select(_ profile: PlatformProfile) -> PlatformMetricsTable {
        let previous = current
        if previous !== profile.metrics { current = profile.metrics }
        return previous
    }
}

extension PlatformMetricsTable {
    package static let macOS = PlatformMetricsTable()
}
