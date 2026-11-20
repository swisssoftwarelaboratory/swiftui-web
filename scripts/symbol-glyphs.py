#!/usr/bin/env python3
"""Generate Packages/WebGraphics/Sources/WebGraphics/Text/SystemSymbolGlyphs.swift: the glyphs `Image(systemName:)`
draws, taken from the Lucide icon set (ISC licence, https://lucide.dev) and mapped by SF Symbol
name. SF Symbols themselves are never shipped (Docs/ROADMAP.md); the glyphs are approximate.

    python3 scripts/symbol-glyphs.py path/to/icon-nodes.json   # lucide-static 1.40.0 made the committed table

`icon-nodes.json` is Lucide's published node table (npm `lucide-static`, `icon-nodes.json`):
{ "<icon>": [["path", {"d": "…"}], ["circle", {"cx": …}], …] } on a 24 × 24 grid, stroked 2
wide with round caps and joins. Each mapped glyph is emitted as a flat command list in that
grid (0 move x y, 1 line x y, 2 curve x1 y1 x2 y2 x y, 3 close) with its outline bounds
including the stroke, and a fill mode: 0 stroke only, 1 fill and stroke (`.fill` symbols),
2 fill the first element and stroke the rest in the knockout colour (`.circle.fill` symbols).
"""
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Packages/WebGraphics/Sources/WebGraphics/Text/SystemSymbolGlyphs.swift"

# SF Symbol name -> (Lucide icon, fill mode). Fill mode 1 fills the whole glyph, 2 fills its
# first element and knocks the rest out (the marks inside filled circles), 0 strokes only.
MAPPING = {
    # Ember (decision 0021): its appearance picker, account rows, saved and filter chips.
    "person.crop.circle.badge.plus": ("user-round-plus", 0), "person.crop.circle.badge.checkmark": ("user-round-check", 0),
    "checkmark.seal.fill": ("badge-check", 2), "star.slash.fill": ("star-off", 1), "text.bubble.fill": ("message-square-text", 2),
    "iphone.radiowaves.left.and.right": ("vibrate", 0), "square.fill.text.grid.1x2": ("layout-list", 0),
    "star": ("star", 0), "star.fill": ("star", 1), "heart": ("heart", 0), "heart.fill": ("heart", 1),
    "checkmark": ("check", 0), "xmark": ("x", 0), "plus": ("plus", 0), "minus": ("minus", 0),
    "chevron.right": ("chevron-right", 0), "chevron.left": ("chevron-left", 0), "chevron.down": ("chevron-down", 0), "chevron.up": ("chevron-up", 0),
    "gear": ("settings", 0), "gearshape": ("settings", 0), "gearshape.fill": ("settings", 0), "magnifyingglass": ("search", 0),
    "trash": ("trash-2", 0), "trash.fill": ("trash-2", 0), "pencil": ("pencil", 0), "folder": ("folder", 0), "folder.fill": ("folder", 1),
    "doc": ("file", 0), "doc.text": ("file-text", 0), "person": ("user", 0), "person.fill": ("user", 0), "person.circle": ("circle-user", 0),
    "house": ("house", 0), "house.fill": ("house", 0), "bell": ("bell", 0), "bell.fill": ("bell", 1),
    "envelope": ("mail", 0), "calendar": ("calendar", 0), "clock": ("clock", 0), "info.circle": ("info", 0), "info.circle.fill": ("info", 2),
    "exclamationmark.triangle": ("triangle-alert", 0), "arrow.right": ("arrow-right", 0), "arrow.left": ("arrow-left", 0),
    "arrow.up": ("arrow-up", 0), "arrow.down": ("arrow-down", 0), "square.and.arrow.up": ("share", 0), "ellipsis": ("ellipsis", 0),
    "circle": ("circle", 0), "circle.fill": ("circle", 1), "square": ("square", 0), "square.fill": ("square", 1),
    "photo": ("image", 0), "camera": ("camera", 0), "play.fill": ("play", 1), "pause.fill": ("pause", 1), "bookmark": ("bookmark", 0),
    "bookmark.fill": ("bookmark", 1), "tag": ("tag", 0), "lock": ("lock", 0), "lock.open": ("lock-open", 0), "paperplane": ("send", 0),
    "cart": ("shopping-cart", 0), "map": ("map", 0), "globe": ("globe", 0), "link": ("link", 0), "eye": ("eye", 0), "eye.slash": ("eye-off", 0),
    "questionmark.circle": ("circle-question-mark", 0), "questionmark.circle.fill": ("circle-question-mark", 2),
    "checkmark.circle": ("circle-check", 0), "checkmark.circle.fill": ("circle-check", 2),
    "xmark.circle": ("circle-x", 0), "xmark.circle.fill": ("circle-x", 2), "plus.circle": ("circle-plus", 0), "plus.circle.fill": ("circle-plus", 2),
    "minus.circle": ("circle-minus", 0), "minus.circle.fill": ("circle-minus", 2), "line.3.horizontal": ("menu", 0), "list.bullet": ("list", 0),
    "sun.max": ("sun", 0), "moon": ("moon", 0), "moon.fill": ("moon", 1), "cloud": ("cloud", 0), "cloud.fill": ("cloud", 1), "bolt": ("zap", 0),
    "bolt.fill": ("zap", 1), "flame": ("flame", 0), "flame.fill": ("flame", 1), "leaf": ("leaf", 0), "wifi": ("wifi", 0),
    "speaker.wave.2": ("volume-2", 0), "mic": ("mic", 0), "phone": ("phone", 0), "phone.fill": ("phone", 1), "message": ("message-circle", 0),
    "message.fill": ("message-circle", 1), "bubble.left": ("message-square", 0), "bubble.left.fill": ("message-square", 1),
    "hand.thumbsup": ("thumbs-up", 0), "flag": ("flag", 0), "flag.fill": ("flag", 1), "pin": ("pin", 0), "pin.fill": ("pin", 1),
    "location": ("navigation", 0), "location.fill": ("navigation", 1), "car": ("car", 0), "airplane": ("plane", 0), "gift": ("gift", 0),
    "creditcard": ("credit-card", 0), "chart.bar": ("chart-bar", 0), "square.grid.2x2": ("layout-grid", 0),
    "slider.horizontal.3": ("sliders-horizontal", 0), "arrow.clockwise": ("rotate-cw", 0), "arrow.counterclockwise": ("rotate-ccw", 0),
    "arrow.up.arrow.down": ("arrow-up-down", 0), "arrow.uturn.left": ("undo-2", 0), "sidebar.left": ("panel-left", 0),
    "square.and.pencil": ("square-pen", 0), "ellipsis.circle": ("circle-ellipsis", 0), "arrow.down.circle": ("circle-arrow-down", 0),
    "arrow.up.circle": ("circle-arrow-up", 0), "arrow.right.circle": ("circle-arrow-right", 0), "arrow.left.circle": ("circle-arrow-left", 0),
    "chevron.right.circle": ("circle-chevron-right", 0), "checkmark.square": ("square-check", 0), "square.dashed": ("square-dashed", 0),
    "rectangle": ("rectangle-horizontal", 0), "rectangle.fill": ("rectangle-horizontal", 1), "rectangle.portrait": ("rectangle-vertical", 0),
    "triangle": ("triangle", 0), "triangle.fill": ("triangle", 1), "exclamationmark.circle": ("circle-alert", 0),
    "exclamationmark.circle.fill": ("circle-alert", 2), "exclamationmark.triangle.fill": ("triangle-alert", 2),
    "number": ("hash", 0), "at": ("at-sign", 0), "percent": ("percent", 0), "dollarsign.circle": ("circle-dollar-sign", 0),
    "textformat": ("type", 0), "bold": ("bold", 0), "italic": ("italic", 0), "underline": ("underline", 0),
    "text.alignleft": ("text-align-start", 0), "text.aligncenter": ("text-align-center", 0), "text.alignright": ("text-align-end", 0),
    "text.justify": ("text-align-justify", 0), "list.number": ("list-ordered", 0), "checklist": ("list-checks", 0), "quote.opening": ("quote", 0),
    "square.and.arrow.down": ("download", 0), "arrow.down.to.line": ("arrow-down-to-line", 0), "arrow.up.to.line": ("arrow-up-to-line", 0),
    "doc.on.doc": ("copy", 0), "doc.on.clipboard": ("clipboard", 0), "printer": ("printer", 0), "scissors": ("scissors", 0),
    "paperclip": ("paperclip", 0), "key": ("key", 0), "shield": ("shield", 0), "shield.fill": ("shield", 1), "ant": ("bug", 0),
    "chevron.left.forwardslash.chevron.right": ("code", 0), "terminal": ("terminal", 0), "cylinder": ("database", 0),
    "desktopcomputer": ("monitor", 0), "iphone": ("smartphone", 0), "headphones": ("headphones", 0), "music.note": ("music", 0),
    "video": ("video", 0), "video.fill": ("video", 1), "mic.slash": ("mic-off", 0), "bell.slash": ("bell-off", 0), "battery.100": ("battery-full", 0),
    "antenna.radiowaves.left.and.right": ("radio-tower", 0), "drop": ("droplet", 0), "drop.fill": ("droplet", 1), "wind": ("wind", 0),
    "snowflake": ("snowflake", 0), "thermometer": ("thermometer", 0), "chart.line.uptrend.xyaxis": ("trending-up", 0), "chart.pie": ("chart-pie", 0),
    "tablecells": ("table", 0), "wallet.pass": ("wallet", 0), "briefcase": ("briefcase", 0), "building.2": ("building-2", 0),
    "storefront": ("store", 0), "truck.box": ("truck", 0), "bicycle": ("bike", 0), "bus": ("bus", 0), "tram": ("train-front", 0),
    "trophy": ("trophy", 0), "crown": ("crown", 0), "sparkles": ("sparkles", 0), "paintpalette": ("palette", 0), "paintbrush": ("brush", 0),
    "ruler": ("ruler", 0), "safari": ("compass", 0), "lightbulb": ("lightbulb", 0), "power": ("power", 0), "archivebox": ("archive", 0),
    "tray": ("inbox", 0), "shippingbox": ("package", 0), "square.3.layers.3d": ("layers", 0), "folder.badge.plus": ("folder-plus", 0),
    "doc.badge.plus": ("file-plus", 0), "book": ("book-open", 0), "book.closed": ("book", 0), "newspaper": ("newspaper", 0),
    "graduationcap": ("graduation-cap", 0), "tv": ("tv", 0), "radio": ("radio", 0), "gamecontroller": ("gamepad-2", 0),
    "puzzlepiece": ("puzzle", 0), "waveform.path.ecg": ("activity", 0), "pills": ("pill", 0), "dog": ("dog", 0), "cat": ("cat", 0),
    "tree": ("trees", 0), "mountain.2": ("mountain", 0), "wrench": ("wrench", 0), "hammer": ("hammer", 0), "person.2": ("users", 0),
    "person.badge.plus": ("user-plus", 0), "face.smiling": ("smile", 0), "hand.raised": ("hand", 0), "hand.thumbsdown": ("thumbs-down", 0),
    "cursorarrow": ("mouse-pointer", 0), "arrow.up.and.down.and.arrow.left.and.right": ("move", 0),
    "arrow.up.left.and.arrow.down.right": ("expand", 0), "crop": ("crop", 0), "plus.magnifyingglass": ("zoom-in", 0),
    "minus.magnifyingglass": ("zoom-out", 0), "qrcode": ("qr-code", 0), "touchid": ("fingerprint", 0), "xmark.square": ("square-x", 0),
    "plus.square": ("square-plus", 0), "minus.square": ("square-minus", 0), "bell.badge": ("bell-ring", 0),
    "star.leadinghalf.filled": ("star-half", 0), "arrow.up.right": ("arrow-up-right", 0), "arrow.down.left": ("arrow-down-left", 0),
    "arrow.turn.up.left": ("corner-up-left", 0), "repeat": ("repeat", 0), "shuffle": ("shuffle", 0), "backward.fill": ("rewind", 1),
    "forward.fill": ("fast-forward", 1), "forward": ("fast-forward", 0), "backward": ("rewind", 0), "speaker.slash": ("volume-x", 0), "speaker.wave.1": ("volume-1", 0),
    "forward.end.fill": ("skip-forward", 1), "backward.end.fill": ("skip-back", 1), "sidebar.right": ("panel-right", 0),
    "rectangle.split.3x1": ("columns-3", 0), "link.badge.plus": ("link-2", 0), "eraser": ("eraser", 0), "highlighter": ("highlighter", 0),
    "eyedropper": ("pipette", 0), "hexagon": ("hexagon", 0), "pentagon": ("pentagon", 0), "seal": ("badge", 0),
    "star.circle": ("circle-star", 0), "heart.circle": ("circle-heart", 0), "trash.circle": ("circle-trash", 0),
    "play": ("play", 0), "pause": ("pause", 0), "stop.fill": ("square", 1), "trash.slash": ("trash", 0), "xmark.circle.fill.rtl": ("circle-x", 2),
    "arrow.up.right.square": ("square-arrow-out-up-right", 0), "arrow.right.square": ("square-arrow-right", 0), "gearshape.2": ("settings-2", 0),
    "person.crop.circle": ("circle-user-round", 0), "person.crop.circle.fill": ("circle-user-round", 2), "star.slash": ("star-off", 0),
    "heart.slash": ("heart-off", 0), "lock.fill": ("lock", 1), "lock.open.fill": ("lock-open", 1), "bookmark.slash": ("bookmark-x", 0),
    "square.stack": ("layers", 0), "rectangle.stack": ("layers", 0), "doc.fill": ("file", 1), "folder.circle": ("folder", 0),
    "clock.fill": ("clock", 2), "calendar.badge.plus": ("calendar-plus", 0), "envelope.fill": ("mail", 1), "envelope.open": ("mail-open", 0),
    "phone.down": ("phone-off", 0), "sun.min": ("sun-dim", 0), "cloud.sun": ("cloud-sun", 0), "cloud.rain": ("cloud-rain", 0),
    "cloud.bolt": ("cloud-lightning", 0), "umbrella": ("umbrella", 0), "waveform": ("audio-lines", 0), "speaker": ("volume", 0),
    "speaker.wave.3": ("volume-2", 0), "hourglass": ("hourglass", 0), "timer": ("timer", 0), "stopwatch": ("timer", 0), "alarm": ("alarm-clock", 0),
    "bed.double": ("bed-double", 0), "fork.knife": ("utensils", 0), "cup.and.saucer": ("coffee", 0), "wineglass": ("wine", 0),
    "birthday.cake": ("cake", 0), "figure.walk": ("footprints", 0), "bandage": ("bandage", 0), "cross.case": ("briefcase-medical", 0),
    "stethoscope": ("stethoscope", 0), "brain": ("brain", 0), "atom": ("atom", 0), "flask": ("flask-conical", 0), "testtube.2": ("test-tube", 0),
    "globe.americas": ("earth", 0), "network": ("network", 0), "server.rack": ("server", 0), "externaldrive": ("hard-drive", 0),
    "cpu": ("cpu", 0), "memorychip": ("memory-stick", 0), "keyboard": ("keyboard", 0), "computermouse": ("mouse", 0), "display": ("monitor", 0),
    "laptopcomputer": ("laptop", 0), "ipad": ("tablet", 0), "applewatch": ("watch", 0), "printer.fill": ("printer", 1),
    "cable.connector": ("cable", 0), "powerplug": ("plug", 0), "battery.25": ("battery-low", 0), "battery.50": ("battery-medium", 0),
    "bolt.slash": ("zap-off", 0), "lightbulb.fill": ("lightbulb", 1), "flashlight.on.fill": ("flashlight", 1), "magnet": ("magnet", 0),
    "scalemass": ("scale", 0), "gauge": ("gauge", 0), "speedometer": ("gauge", 0), "level": ("ruler", 0), "hammer.fill": ("hammer", 1),
    "screwdriver": ("wrench", 0), "paintbrush.pointed": ("brush", 0), "theatermasks": ("drama", 0), "ticket": ("ticket", 0),
    "film": ("film", 0), "photo.on.rectangle": ("images", 0), "camera.fill": ("camera", 1), "video.slash": ("video-off", 0),
    "mic.fill": ("mic", 1), "music.note.list": ("list-music", 0), "headphones.circle": ("headphones", 0), "hifispeaker": ("speaker", 0),
    "radio.fill": ("radio", 1), "tv.fill": ("tv", 1), "gamecontroller.fill": ("gamepad-2", 1), "dice": ("dice-5", 0),
    "bag": ("shopping-bag", 0), "bag.fill": ("shopping-bag", 1), "cart.fill": ("shopping-cart", 1), "basket": ("shopping-basket", 0),
    "giftcard": ("gift", 0), "banknote": ("banknote", 0), "dollarsign": ("dollar-sign", 0), "eurosign": ("euro", 0),
    "sterlingsign": ("pound-sterling", 0), "yensign": ("japanese-yen", 0), "bitcoinsign": ("bitcoin", 0), "creditcard.fill": ("credit-card", 1),
    "chart.bar.fill": ("chart-bar", 1), "chart.xyaxis.line": ("chart-line", 0), "chart.pie.fill": ("chart-pie", 1),
    "chart.line.downtrend.xyaxis": ("trending-down", 0), "percent.circle": ("badge-percent", 0), "target": ("target", 0),
    "scope": ("crosshair", 0), "binoculars": ("binoculars", 0), "eyeglasses": ("glasses", 0), "sunglasses": ("glasses", 0),
    "tshirt": ("shirt", 0), "shoe": ("footprints", 0), "backpack": ("backpack", 0), "suitcase": ("luggage", 0),
    "house.circle": ("house", 0), "building": ("building", 0), "building.columns": ("landmark", 0), "tent": ("tent", 0), "signpost.right": ("signpost", 0),
    "mappin": ("map-pin", 0), "mappin.and.ellipse": ("map-pin", 0), "map.fill": ("map", 1), "location.circle": ("locate", 0),
    "location.north": ("navigation", 0), "compass.drawing": ("drafting-compass", 0), "globe.europe.africa": ("earth", 0),
    "car.fill": ("car", 1), "bus.fill": ("bus", 1), "tram.fill": ("train-front", 1), "airplane.departure": ("plane-takeoff", 0),
    "airplane.arrival": ("plane-landing", 0), "ferry": ("ship", 0), "sailboat": ("sailboat", 0), "fuelpump": ("fuel", 0), "parkingsign": ("circle-parking", 0),
    "figure.run": ("footprints", 0), "sportscourt": ("land-plot", 0), "soccerball": ("volleyball", 0), "basketball": ("volleyball", 0),
    "dumbbell": ("dumbbell", 0), "medal": ("medal", 0), "rosette": ("award", 0), "trophy.fill": ("trophy", 1), "crown.fill": ("crown", 1),
    "gem": ("gem", 0), "wand.and.stars": ("wand-sparkles", 0), "wand.and.rays": ("wand", 0), "sparkle": ("sparkle", 0),
    "sun.max.fill": ("sun", 1), "moon.stars": ("moon-star", 0), "star.square": ("square-star", 0), "leaf.fill": ("leaf", 1),
    "tree.fill": ("trees", 1), "pawprint": ("paw-print", 0), "bird": ("bird", 0), "fish": ("fish", 0), "ant.fill": ("bug", 1),
    "ladybug": ("bug", 0), "tortoise": ("turtle", 0), "hare": ("rabbit", 0), "carrot": ("carrot", 0), "apple.logo": ("apple", 0),
    "hand.wave": ("hand", 0), "hand.point.up.left": ("pointer", 0), "hand.tap": ("pointer", 0), "hands.clap": ("hand-metal", 0),
    "person.3": ("users", 0), "person.2.fill": ("users", 1), "person.fill.checkmark": ("user-check", 0), "person.fill.xmark": ("user-x", 0),
    "person.badge.minus": ("user-minus", 0), "person.text.rectangle": ("id-card", 0), "person.crop.square": ("square-user", 0),
    "figure.stand": ("person-standing", 0), "accessibility": ("accessibility", 0), "ear": ("ear", 0), "eye.fill": ("eye", 1),
    "eyebrow": ("eye", 0), "mouth": ("smile", 0), "nose": ("smile", 0), "face.dashed": ("scan-face", 0), "faceid": ("scan-face", 0),
    "checkmark.shield": ("shield-check", 0), "xmark.shield": ("shield-x", 0), "exclamationmark.shield": ("shield-alert", 0), "lock.shield": ("shield-check", 0),
    "key.fill": ("key", 1), "lock.rotation": ("lock-keyhole", 0), "eye.trianglebadge.exclamationmark": ("eye-off", 0),
    "hand.raised.slash": ("hand", 0), "nosign": ("ban", 0), "exclamationmark.octagon": ("octagon-alert", 0),
    "exclamationmark.octagon.fill": ("octagon-alert", 2), "checkmark.seal": ("badge-check", 0), "xmark.seal": ("badge-x", 0),
    "xmark.octagon": ("octagon-x", 0), "questionmark.diamond": ("diamond", 0), "info": ("info", 0), "lightbulb.max": ("lightbulb", 0),
    "bookmark.circle": ("bookmark", 0), "tag.fill": ("tag", 1), "tag.circle": ("tag", 0), "bell.circle": ("bell", 0),
    "bell.badge.fill": ("bell-ring", 1), "flag.slash": ("flag-off", 0), "flag.checkered": ("flag", 0), "pin.slash": ("pin-off", 0),
    "paperplane.fill": ("send", 1), "tray.fill": ("inbox", 1), "tray.and.arrow.down": ("inbox", 0), "tray.and.arrow.up": ("inbox", 0),
    "archivebox.fill": ("archive", 1), "doc.text.fill": ("file-text", 1), "doc.richtext": ("file-text", 0), "doc.plaintext": ("file-text", 0),
    "doc.zipper": ("file-archive", 0), "doc.on.doc.fill": ("copy", 1), "folder.badge.minus": ("folder-minus", 0), "folder.badge.gearshape": ("folder-cog", 0),
    "externaldrive.fill": ("hard-drive", 1), "internaldrive": ("hard-drive", 0), "opticaldiscdrive": ("disc", 0), "icloud": ("cloud", 0),
    "icloud.fill": ("cloud", 1), "icloud.and.arrow.down": ("cloud-download", 0), "icloud.and.arrow.up": ("cloud-upload", 0),
    "arrow.down.doc": ("file-down", 0), "arrow.up.doc": ("file-up", 0), "square.and.arrow.up.fill": ("share", 1), "arrow.up.forward": ("arrow-up-right", 0),
    "arrow.down.forward": ("arrow-down-right", 0), "arrow.up.left": ("arrow-up-left", 0), "arrow.down.right": ("arrow-down-right", 0),
    "arrow.left.arrow.right": ("arrow-left-right", 0), "arrow.triangle.2.circlepath": ("refresh-cw", 0), "arrow.2.squarepath": ("repeat", 0),
    "arrow.3.trianglepath": ("recycle", 0), "arrow.uturn.right": ("redo-2", 0), "arrow.uturn.backward": ("undo-2", 0), "arrow.uturn.forward": ("redo-2", 0),
    "arrow.turn.down.right": ("corner-down-right", 0), "arrow.turn.up.right": ("corner-up-right", 0), "arrow.turn.down.left": ("corner-down-left", 0),
    "arrow.right.to.line": ("arrow-right-to-line", 0), "arrow.left.to.line": ("arrow-left-to-line", 0), "arrow.up.and.down": ("move-vertical", 0),
    "arrow.left.and.right": ("move-horizontal", 0), "arrow.down.left.and.arrow.up.right": ("shrink", 0), "arrow.up.backward": ("arrow-up-left", 0),
    "arrowshape.turn.up.left": ("reply", 0), "arrowshape.turn.up.right": ("forward", 0), "arrowshape.turn.up.left.2": ("reply-all", 0),
    "chevron.left.2": ("chevrons-left", 0), "chevron.right.2": ("chevrons-right", 0), "chevron.up.chevron.down": ("chevrons-up-down", 0),
    "chevron.compact.down": ("chevron-down", 0), "chevron.compact.up": ("chevron-up", 0), "chevron.forward": ("chevron-right", 0), "chevron.backward": ("chevron-left", 0),
    "arrow.forward": ("arrow-right", 0), "arrow.backward": ("arrow-left", 0), "arrowtriangle.right.fill": ("play", 1), "arrowtriangle.down.fill": ("triangle", 1),
    "arrowtriangle.left.fill": ("play", 1), "arrowtriangle.up.fill": ("triangle", 1), "play.circle": ("circle-play", 0), "play.circle.fill": ("circle-play", 2),
    "pause.circle": ("circle-pause", 0), "pause.circle.fill": ("circle-pause", 2), "stop.circle": ("circle-stop", 0), "record.circle": ("circle-dot", 0),
    "playpause": ("play", 0), "playpause.fill": ("play", 1), "gobackward": ("rotate-ccw", 0), "goforward": ("rotate-cw", 0),
    "gobackward.10": ("rotate-ccw", 0), "goforward.10": ("rotate-cw", 0), "speaker.wave.2.fill": ("volume-2", 1), "speaker.slash.fill": ("volume-x", 1),
    "airpods": ("headphones", 0), "airplayvideo": ("airplay", 0), "airplayaudio": ("airplay", 0), "shareplay": ("cast", 0),
    "rectangle.on.rectangle": ("app-window", 0), "rectangle.3.group": ("layout-dashboard", 0), "rectangle.grid.1x2": ("rows-2", 0),
    "rectangle.grid.2x2": ("layout-grid", 0), "square.grid.3x3": ("grid-3x3", 0), "square.grid.2x2.fill": ("layout-grid", 1),
    "square.split.2x1": ("columns-2", 0), "rectangle.split.2x1": ("columns-2", 0), "rectangle.split.1x2": ("rows-2", 0),
    "rectangle.split.3x3": ("grid-3x3", 0), "squares.below.rectangle": ("layout-template", 0), "sidebar.leading": ("panel-left", 0),
    "sidebar.trailing": ("panel-right", 0), "sidebar.left.fill": ("panel-left", 1), "macwindow": ("app-window-mac", 0), "menubar.rectangle": ("panel-top", 0),
    "uiwindow.split.2x1": ("columns-2", 0), "dock.rectangle": ("panel-bottom", 0), "rectangle.portrait.fill": ("rectangle-vertical", 1),
    "rectangle.inset.filled": ("rectangle-horizontal", 0), "square.on.square": ("copy", 0), "square.fill.on.square.fill": ("copy", 1),
    "square.dashed.inset.filled": ("square-dashed", 0), "circle.dashed": ("circle-dashed", 0), "circle.dotted": ("circle-dashed", 0),
    "circle.lefthalf.filled": ("contrast", 0), "circle.righthalf.filled": ("contrast", 0), "circle.grid.2x2": ("layout-grid", 0),
    "circle.grid.3x3": ("grip", 0), "circle.hexagongrid": ("grip", 0), "smallcircle.filled.circle": ("circle-dot", 0), "capsule": ("pill", 0),
    "oval": ("circle", 0), "diamond": ("diamond", 0), "diamond.fill": ("diamond", 1), "octagon": ("octagon", 0), "octagon.fill": ("octagon", 1),
    "hexagon.fill": ("hexagon", 1), "pentagon.fill": ("pentagon", 1), "shield.lefthalf.filled": ("shield-half", 0), "seal.fill": ("badge", 1),
    "line.horizontal.3": ("menu", 0), "line.3.horizontal.decrease": ("list-filter", 0), "line.3.horizontal.decrease.circle": ("list-filter", 0),
    "line.horizontal.3.decrease.circle": ("list-filter", 0), "list.dash": ("list", 0), "list.bullet.indent": ("list-tree", 0), "list.star": ("list", 0),
    "text.badge.plus": ("list-plus", 0), "text.badge.minus": ("list-minus", 0), "text.badge.checkmark": ("list-checks", 0), "text.insert": ("list-plus", 0),
    "text.append": ("list-end", 0), "text.quote": ("text-quote", 0), "textformat.size": ("a-large-small", 0), "textformat.abc": ("case-sensitive", 0),
    "character": ("type", 0), "strikethrough": ("strikethrough", 0), "text.cursor": ("text-cursor", 0), "increase.indent": ("indent-increase", 0),
    "decrease.indent": ("indent-decrease", 0), "text.word.spacing": ("space", 0), "textformat.superscript": ("superscript", 0), "textformat.subscript": ("subscript", 0),
    "paragraphsign": ("pilcrow", 0), "list.bullet.rectangle": ("list", 0), "tablecells.fill": ("table", 1), "function": ("sigma", 0), "sum": ("sigma", 0),
    "x.squareroot": ("radical", 0), "divide": ("divide", 0), "multiply": ("x", 0), "equal": ("equal", 0), "lessthan": ("chevron-left", 0), "greaterthan": ("chevron-right", 0),
    "plusminus": ("diff", 0), "plus.forwardslash.minus": ("diff", 0), "infinity": ("infinity", 0), "asterisk": ("asterisk", 0),
    "curlybraces": ("braces", 0), "chevron.left.slash.chevron.right": ("code", 0), "terminal.fill": ("terminal", 1), "apple.terminal": ("terminal", 0),
    "command": ("command", 0), "option": ("option", 0), "control": ("chevron-up", 0), "shift": ("arrow-big-up", 0), "capslock": ("arrow-big-up", 0),
    "escape": ("arrow-up-left", 0), "delete.left": ("delete", 0), "delete.right": ("delete", 0), "return": ("corner-down-left", 0), "tab": ("arrow-right-to-line", 0),
    "space": ("space", 0), "power.circle": ("power", 0), "togglepower": ("power", 0), "poweroff": ("power-off", 0), "powersleep": ("moon", 0),
    "sleep": ("moon", 0), "wake": ("sun", 0), "restart": ("rotate-ccw", 0), "eject": ("triangle", 0), "eject.fill": ("triangle", 1),
    "cursorarrow.click": ("mouse-pointer-click", 0), "cursorarrow.rays": ("mouse-pointer-click", 0), "hand.point.up": ("pointer", 0),
    "arrow.up.left.and.down.right.magnifyingglass": ("zoom-in", 0), "magnifyingglass.circle": ("search", 0), "doc.text.magnifyingglass": ("file-search", 0),
    "sparkle.magnifyingglass": ("search", 0), "text.magnifyingglass": ("search", 0), "loupe": ("search", 0), "slider.vertical.3": ("sliders-vertical", 0),
    "slider.horizontal.below.rectangle": ("sliders-horizontal", 0), "dial.min": ("gauge", 0), "switch.2": ("toggle-left", 0), "checkmark.rectangle": ("square-check", 0),
    "circle.circle": ("circle-dot", 0), "circle.inset.filled": ("circle-dot", 0), "checkmark.square.fill": ("square-check", 2), "xmark.square.fill": ("square-x", 2),
    "plus.square.fill": ("square-plus", 2), "minus.square.fill": ("square-minus", 2), "square.slash": ("square-slash", 0), "xmark.bin": ("trash", 0),
    "trash.slash.fill": ("trash", 1), "xmark.rectangle": ("square-x", 0), "questionmark.square": ("square-question-mark", 0),
    "exclamationmark.square": ("square-alert", 0), "info.square": ("square-info", 0), "star.square.fill": ("square-star", 2), "heart.square": ("square-heart", 0),
    "square.and.line.vertical.and.square": ("columns-2", 0), "square.split.diagonal": ("square-split-horizontal", 0), "rectangle.compress.vertical": ("fold-vertical", 0),
    "rectangle.expand.vertical": ("unfold-vertical", 0), "arrow.up.and.down.square": ("square-arrow-up", 0), "square.resize": ("scaling", 0), "aspectratio": ("ratio", 0),
    "perspective": ("box", 0), "cube": ("box", 0), "cube.fill": ("box", 1), "shippingbox.fill": ("package", 1), "cylinder.fill": ("database", 1),
    "cylinder.split.1x2": ("database", 0), "rotate.right": ("rotate-cw", 0), "rotate.left": ("rotate-ccw", 0), "rotate.3d": ("rotate-3d", 0), "move.3d": ("move-3d", 0),
    "scale.3d": ("scale-3d", 0), "view.3d": ("view", 0), "arkit": ("box", 0), "camera.viewfinder": ("scan", 0), "qrcode.viewfinder": ("scan-qr-code", 0),
    "barcode": ("barcode", 0), "barcode.viewfinder": ("scan-barcode", 0), "viewfinder": ("scan", 0), "doc.viewfinder": ("scan-text", 0),
    "camera.rotate": ("switch-camera", 0), "camera.on.rectangle": ("camera", 0), "photo.fill": ("image", 1), "photo.badge.plus": ("image-plus", 0),
    "photo.stack": ("images", 0), "rectangle.stack.badge.plus": ("layers", 0), "film.stack": ("film", 0), "livephoto": ("aperture", 0), "camera.aperture": ("aperture", 0),
    "camera.filters": ("blend", 0), "wand.and.stars.inverse": ("wand-sparkles", 0), "paintpalette.fill": ("palette", 1), "paintbrush.fill": ("brush", 1),
    "pencil.tip": ("pen-tool", 0), "pencil.line": ("pencil-line", 0), "pencil.circle": ("pencil", 0), "pencil.and.outline": ("pencil-ruler", 0),
    "pencil.and.ruler": ("pencil-ruler", 0), "highlighter.fill": ("highlighter", 1), "lasso": ("lasso", 0), "scribble": ("pen-line", 0), "signature": ("signature", 0),
    "hand.draw": ("pen", 0), "paintbrush.pointed.fill": ("brush", 1), "swatchpalette": ("swatch-book", 0), "circle.hexagongrid.fill": ("grip", 1),
    "trapezoid.and.line.horizontal": ("shapes", 0), "squareshape": ("square", 0), "triangle.righthalf.filled": ("triangle-right", 0), "star.lefthalf.fill": ("star-half", 0),
    "sun.horizon": ("sunset", 0), "sunrise": ("sunrise", 0), "sunset": ("sunset", 0), "moon.zzz": ("moon", 0), "cloud.moon": ("cloud-moon", 0), "cloud.snow": ("cloud-snow", 0),
    "cloud.fog": ("cloud-fog", 0), "cloud.drizzle": ("cloud-drizzle", 0), "cloud.hail": ("cloud-hail", 0), "tornado": ("tornado", 0), "hurricane": ("tornado", 0),
    "thermometer.sun": ("thermometer-sun", 0), "thermometer.snowflake": ("thermometer-snowflake", 0), "humidity": ("droplets", 0), "aqi.medium": ("haze", 0), "rainbow": ("rainbow", 0),
    "water.waves": ("waves", 0), "drop.triangle": ("droplet", 0), "flame.circle": ("flame", 0), "smoke": ("cloud-fog", 0), "sun.dust": ("sun-dim", 0),
    "wind.snow": ("wind", 0), "snow": ("snowflake", 0), "sparkles.rectangle.stack": ("sparkles", 0), "moonphase.new.moon": ("circle", 1),
    "globe.asia.australia": ("earth", 0), "globe.central.south.asia": ("earth", 0), "globe.badge.chevron.backward": ("globe", 0), "network.slash": ("network", 0),
    "wifi.slash": ("wifi-off", 0), "wifi.exclamationmark": ("wifi-off", 0), "personalhotspot": ("wifi", 0), "dot.radiowaves.left.and.right": ("radio", 0),
    "antenna.radiowaves.left.and.right.slash": ("radio-tower", 0), "bluetooth": ("bluetooth", 0), "cellularbars": ("signal", 0), "chart.bar.xaxis": ("chart-bar", 0),
    "waveform.circle": ("audio-waveform", 0), "waveform.path": ("audio-waveform", 0), "waveform.badge.plus": ("audio-lines", 0), "mic.circle": ("mic", 0),
    "mic.badge.plus": ("mic", 0), "recordingtape": ("disc", 0), "music.mic": ("mic-vocal", 0), "music.quarternote.3": ("music-3", 0), "music.note.house": ("music", 0),
    "opticaldisc": ("disc", 0), "guitars": ("guitar", 0), "pianokeys": ("piano", 0), "metronome": ("metronome", 0), "tuningfork": ("drum", 0), "drum": ("drum", 0),
    "headphones.fill": ("headphones", 1), "hifispeaker.fill": ("speaker", 1), "speaker.zzz": ("volume-off", 0), "ear.badge.checkmark": ("ear", 0), "ear.trianglebadge.exclamationmark": ("ear-off", 0),
    "hearingdevice.ear": ("ear", 0), "phone.arrow.up.right": ("phone-outgoing", 0), "phone.arrow.down.left": ("phone-incoming", 0), "phone.badge.plus": ("phone-call", 0),
    "phone.connection": ("phone-call", 0), "phone.bubble": ("phone-call", 0), "video.badge.plus": ("video", 0), "video.bubble": ("video", 0), "deskview": ("monitor", 0),
    "message.badge": ("message-circle-more", 0), "bubble.right": ("message-square", 0), "bubble.left.and.bubble.right": ("messages-square", 0), "quote.bubble": ("message-square-quote", 0),
    "text.bubble": ("message-square-text", 0), "captions.bubble": ("captions", 0), "plus.bubble": ("message-square-plus", 0), "checkmark.bubble": ("message-square-check", 0),
    "exclamationmark.bubble": ("message-square-warning", 0), "ellipsis.bubble": ("message-square-more", 0), "bubble": ("message-square", 0), "envelope.badge": ("mail-warning", 0),
    "envelope.open.fill": ("mail-open", 1), "envelope.arrow.triangle.branch": ("mail", 0), "mail": ("mail", 0), "mail.stack": ("mails", 0), "tray.2": ("inbox", 0),
    "tray.full": ("inbox", 0), "paperplane.circle": ("send", 0), "arrowshape.forward": ("forward", 0), "arrowshape.backward": ("reply", 0),
    "person.wave.2": ("hand", 0), "person.bubble": ("message-circle", 0), "person.and.background.dotted": ("user", 0), "shared.with.you": ("users", 0),
    "figure.2.arms.open": ("users", 0), "figure.and.child.holdinghands": ("users", 0), "person.crop.rectangle": ("contact", 0), "person.crop.artframe": ("contact", 0),
    "figure.arms.open": ("person-standing", 0), "hand.raised.fill": ("hand", 1), "hand.thumbsup.fill": ("thumbs-up", 1), "hand.thumbsdown.fill": ("thumbs-down", 1),
    "hands.sparkles": ("sparkles", 0), "heart.text.square": ("heart-handshake", 0), "brain.head.profile": ("brain", 0), "lungs": ("activity", 0), "allergens": ("flower", 0),
    "pills.fill": ("pill", 1), "cross": ("cross", 0), "cross.fill": ("cross", 1), "cross.circle": ("cross", 0), "cross.case.fill": ("briefcase-medical", 1),
    "medical.thermometer": ("thermometer", 0), "syringe": ("syringe", 0), "facemask": ("shield", 0), "bed.double.fill": ("bed-double", 1), "staroflife": ("cross", 0),
    "dumbbell.fill": ("dumbbell", 1), "sportscourt.fill": ("land-plot", 1), "tennis.racket": ("dumbbell", 0), "figure.walk.circle": ("footprints", 0),
    "leaf.arrow.circlepath": ("recycle", 0), "carrot.fill": ("carrot", 1), "fork.knife.circle": ("utensils", 0), "takeoutbag.and.cup.and.straw": ("shopping-bag", 0),
    "cup.and.saucer.fill": ("coffee", 1), "mug": ("coffee", 0), "wineglass.fill": ("wine", 1), "waterbottle": ("glass-water", 0), "popcorn": ("popcorn", 0),
    "frying.pan": ("cooking-pot", 0), "refrigerator": ("refrigerator", 0), "oven": ("microwave", 0), "microwave": ("microwave", 0), "washer": ("washing-machine", 0),
    "bathtub": ("bath", 0), "shower": ("shower-head", 0), "toilet": ("toilet", 0), "sofa": ("sofa", 0), "chair": ("armchair", 0), "lamp.desk": ("lamp-desk", 0),
    "lamp.floor": ("lamp", 0), "lightbulb.2": ("lightbulb", 0), "fan": ("fan", 0), "air.conditioner.horizontal": ("air-vent", 0), "thermometer.medium": ("thermometer", 0),
    "door.left.hand.open": ("door-open", 0), "door.left.hand.closed": ("door-closed", 0), "window.vertical.open": ("app-window", 0), "house.lodge": ("house", 0),
    "building.2.fill": ("building-2", 1), "building.fill": ("building", 1), "building.columns.fill": ("landmark", 1), "storefront.fill": ("store", 1), "hospital": ("hospital", 0),
    "school": ("school", 0), "church": ("church", 0), "theatermask": ("drama", 0), "warehouse": ("warehouse", 0), "factory": ("factory", 0), "tent.fill": ("tent", 1),
    "mountain.2.fill": ("mountain", 1), "road.lanes": ("route", 0), "point.topleft.down.to.point.bottomright.curvepath": ("route", 0), "map.circle": ("map", 0),
    "signpost.left": ("signpost", 0), "mappin.circle": ("map-pin", 0), "mappin.slash": ("map-pin-off", 0), "location.slash": ("navigation-off", 0),
    "location.north.line": ("navigation", 0), "location.viewfinder": ("locate", 0), "scope.fill": ("crosshair", 0), "sailboat.fill": ("sailboat", 1),
    "ferry.fill": ("ship", 1), "car.2": ("car", 0), "car.circle": ("car", 0), "bolt.car": ("car", 0), "truck.box.fill": ("truck", 1), "box.truck": ("truck", 0),
    "bicycle.circle": ("bike", 0), "scooter": ("bike", 0), "airplane.circle": ("plane", 0), "train.side.front.car": ("train-track", 0), "cablecar": ("cable-car", 0),
    "fuelpump.fill": ("fuel", 1), "ev.charger": ("plug-zap", 0), "parkingsign.circle": ("circle-parking", 0), "steeringwheel": ("circle-dot", 0), "engine.combustion": ("cog", 0),
    "wrench.and.screwdriver": ("wrench", 0), "wrench.fill": ("wrench", 1), "wrench.adjustable": ("wrench", 0), "gearshape.arrow.triangle.2.circlepath": ("settings", 0),
    "screwdriver.fill": ("wrench", 1), "hammer.circle": ("hammer", 0), "ruler.fill": ("ruler", 1), "level.fill": ("ruler", 1), "lightbulb.slash": ("lightbulb-off", 0),
    "flashlight.off.fill": ("flashlight-off", 1), "bolt.circle": ("zap", 0), "bolt.horizontal": ("zap", 0), "bolt.badge.a": ("zap", 0), "battery.0": ("battery", 0),
    "battery.75": ("battery-medium", 0), "battery.100.bolt": ("battery-charging", 0), "battery.slash": ("battery-warning", 0), "powerplug.fill": ("plug", 1),
    "cable.connector.horizontal": ("cable", 0), "dial.max": ("gauge", 0), "gauge.with.dots.needle.bottom.50percent": ("gauge", 0), "gauge.with.needle": ("gauge", 0),
    "speedometer.fill": ("gauge", 1), "barometer": ("gauge", 0), "stopwatch.fill": ("timer", 1), "timer.circle": ("timer", 0), "hourglass.bottomhalf.filled": ("hourglass", 0),
    "clock.arrow.circlepath": ("clock-fading", 0), "clock.badge": ("clock-alert", 0), "clock.badge.checkmark": ("clock-check", 0), "alarm.fill": ("alarm-clock", 1),
    "calendar.badge.clock": ("calendar-clock", 0), "calendar.badge.minus": ("calendar-minus", 0), "calendar.badge.exclamationmark": ("calendar-x", 0),
    "calendar.circle": ("calendar", 0), "calendar.day.timeline.left": ("calendar-days", 0), "deskclock": ("clock", 0), "watch": ("watch", 0),
    "apple.watch": ("watch", 0), "applewatch.watchface": ("watch", 0), "iphone.gen3": ("smartphone", 0), "iphone.landscape": ("smartphone", 0),
    "ipad.landscape": ("tablet", 0), "ipod": ("smartphone", 0), "macbook": ("laptop", 0), "macmini": ("hard-drive", 0), "macpro.gen3": ("server", 0), "macstudio": ("hard-drive", 0),
    "airpodspro": ("headphones", 0), "airpodsmax": ("headphones", 0), "homepod": ("speaker", 0), "appletv": ("tv", 0), "tv.and.hifispeaker.fill": ("tv", 1),
    "keyboard.fill": ("keyboard", 1), "computermouse.fill": ("mouse", 1), "magicmouse": ("mouse", 0), "gamecontroller.circle": ("gamepad-2", 0), "printer.dotmatrix": ("printer", 0),
    "scanner": ("scan", 0), "faxmachine": ("printer", 0), "candybarphone": ("smartphone", 0), "flipphone": ("smartphone", 0), "display.2": ("monitor", 0),
    "pc": ("monitor", 0), "server.rack.fill": ("server", 1), "xserve": ("server", 0), "externaldrive.badge.plus": ("hard-drive", 0), "externaldrive.connected.to.line.below": ("hard-drive", 0),
    "sdcard": ("memory-stick", 0), "simcard": ("memory-stick", 0), "memorychip.fill": ("memory-stick", 1), "cpu.fill": ("cpu", 1), "opticaldiscdrive.fill": ("disc", 1),
    "tv.circle": ("tv", 0), "4k.tv": ("tv", 0), "play.tv": ("tv", 0), "photo.tv": ("tv", 0), "sparkles.tv": ("tv", 0), "music.note.tv": ("tv", 0), "airplay.video": ("airplay", 0),
    "airplay.audio": ("airplay", 0), "display.trianglebadge.exclamationmark": ("monitor-x", 0), "desktopcomputer.trianglebadge.exclamationmark": ("monitor-x", 0),
    "lock.laptopcomputer": ("laptop", 0), "lock.iphone": ("smartphone", 0), "lock.desktopcomputer": ("monitor", 0), "lock.display": ("monitor", 0), "lock.doc": ("file-lock", 0),
    "lock.circle": ("lock", 0), "lock.square": ("lock", 0), "lock.slash": ("lock-open", 0), "lock.open.rotation": ("lock-open", 0), "lock.trianglebadge.exclamationmark": ("lock", 0),
    "key.horizontal": ("key-round", 0), "key.viewfinder": ("key", 0), "touchid.slash": ("fingerprint", 0), "faceid.slash": ("scan-face", 0), "eye.slash.fill": ("eye-off", 1),
    "eye.circle": ("eye", 0), "hand.raised.circle": ("hand", 0), "shield.slash": ("shield-off", 0), "shield.checkered": ("shield-check", 0), "checkmark.shield.fill": ("shield-check", 2),
    "xmark.shield.fill": ("shield-x", 2), "exclamationmark.shield.fill": ("shield-alert", 2), "lock.shield.fill": ("shield-check", 2), "shield.lefthalf.filled.slash": ("shield-off", 0),
    "bell.and.waves.left.and.right": ("bell-ring", 0), "bell.badge.circle": ("bell-ring", 0), "bell.slash.fill": ("bell-off", 1), "bell.circle.fill": ("bell", 2),
    "tag.slash": ("tag", 0), "bookmark.slash.fill": ("bookmark-x", 1), "bookmark.circle.fill": ("bookmark", 2), "flag.2.crossed": ("flag", 0), "flag.badge.ellipsis": ("flag", 0),
    "pin.circle": ("pin", 0), "pin.square": ("pin", 0), "pin.slash.fill": ("pin-off", 1), "paperclip.circle": ("paperclip", 0), "paperclip.badge.ellipsis": ("paperclip", 0),
    "rectangle.and.paperclip": ("paperclip", 0), "link.circle": ("link", 0), "link.circle.fill": ("link", 2), "personalhotspot.circle": ("wifi", 0),
    "scissors.circle": ("scissors", 0), "scissors.badge.ellipsis": ("scissors", 0), "printer.fill.and.paper.fill": ("printer", 1), "printer.filled.and.paper": ("printer", 1),
    "doc.badge.gearshape": ("file-cog", 0), "doc.badge.ellipsis": ("file", 0), "doc.badge.arrow.up": ("file-up", 0), "doc.badge.clock": ("file-clock", 0), "doc.append": ("file-plus", 0),
    "doc.text.below.ecg": ("file-heart", 0), "doc.questionmark": ("file-question-mark", 0), "doc.circle": ("file", 0), "doc.on.doc.badge.plus": ("copy-plus", 0),
    "doc.text.image": ("file-image", 0), "doc.richtext.fill": ("file-text", 1), "doc.plaintext.fill": ("file-text", 1), "doc.zipper.fill": ("file-archive", 1),
    "doc.text.magnifyingglass.fill": ("file-search", 1), "text.document": ("file-text", 0), "text.document.fill": ("file-text", 1), "note": ("notebook", 0),
    "note.text": ("notebook-pen", 0), "note.text.badge.plus": ("notebook-pen", 0), "calendar.badge.checkmark": ("calendar-check", 0), "book.fill": ("book-open", 1),
    "book.closed.fill": ("book", 1), "books.vertical": ("library", 0), "book.pages": ("book-open", 0), "book.and.wrench": ("book", 0), "character.book.closed": ("book-a", 0),
    "text.book.closed": ("book-text", 0), "menucard": ("book-open", 0), "greetingcard": ("mail", 0), "magazine": ("book-open", 0), "newspaper.fill": ("newspaper", 1),
    "bookmark.square": ("bookmark", 0), "graduationcap.fill": ("graduation-cap", 1), "graduationcap.circle": ("graduation-cap", 0), "pencil.and.list.clipboard": ("clipboard-pen", 0),
    "list.clipboard": ("clipboard-list", 0), "clipboard": ("clipboard", 0), "clipboard.fill": ("clipboard", 1), "doc.on.clipboard.fill": ("clipboard", 1),
    "backpack.fill": ("backpack", 1), "suitcase.fill": ("luggage", 1), "briefcase.fill": ("briefcase", 1), "briefcase.circle": ("briefcase", 0), "case": ("briefcase", 0),
    "latch.2.case": ("briefcase", 0), "cross.vial": ("test-tube", 0), "atom.fill": ("atom", 1), "flask.fill": ("flask-conical", 1), "microbe": ("bug", 0), "dna": ("dna", 0),
    "globe.desk": ("earth", 0), "telescope": ("telescope", 0), "binoculars.fill": ("binoculars", 1), "eyeglasses.slash": ("glasses", 0), "sunglasses.fill": ("glasses", 1),
    "tshirt.fill": ("shirt", 1), "shoe.fill": ("footprints", 1), "hat.cap": ("graduation-cap", 0), "hat.widebrim": ("graduation-cap", 0), "hanger": ("shirt", 0),
    "scarf": ("shirt", 0), "coat": ("shirt", 0), "jacket": ("shirt", 0), "handbag": ("shopping-bag", 0), "gift.fill": ("gift", 1), "gift.circle": ("gift", 0),
    "giftcard.fill": ("gift", 1), "ticket.fill": ("ticket", 1), "creditcard.circle": ("credit-card", 0), "creditcard.and.123": ("credit-card", 0), "creditcard.trianglebadge.exclamationmark": ("credit-card", 0),
    "wallet.bifold": ("wallet", 0), "wallet.pass.fill": ("wallet", 1), "banknote.fill": ("banknote", 1), "coloncurrencysign.circle": ("coins", 0), "centsign.circle": ("coins", 0),
    "dollarsign.circle.fill": ("circle-dollar-sign", 2), "dollarsign.square": ("circle-dollar-sign", 0), "dollarsign.arrow.circlepath": ("refresh-cw", 0), "cart.badge.plus": ("shopping-cart", 0),
    "cart.badge.minus": ("shopping-cart", 0), "cart.circle": ("shopping-cart", 0), "basket.fill": ("shopping-basket", 1), "bag.badge.plus": ("shopping-bag", 0), "bag.badge.minus": ("shopping-bag", 0),
    "bag.circle": ("shopping-bag", 0), "storefront.circle": ("store", 0), "tag.circle.fill": ("tag", 2), "chart.bar.doc.horizontal": ("chart-bar", 0), "chart.dots.scatter": ("chart-scatter", 0),
    "chart.bar.xaxis.ascending": ("chart-bar-increasing", 0), "chart.line.flattrend.xyaxis": ("chart-line", 0), "chart.line.text.clipboard": ("clipboard", 0),
    "chart.pie.fill.rtl": ("chart-pie", 1), "percent.circle.fill": ("badge-percent", 2), "square.stack.3d.up": ("layers", 0), "square.stack.3d.up.fill": ("layers", 1),
    "square.stack.3d.down.right": ("layers", 0), "square.stack.fill": ("layers", 1), "rectangle.stack.fill": ("layers", 1), "rectangle.on.rectangle.fill": ("app-window", 1),
    "rectangle.3.group.fill": ("layout-dashboard", 1), "square.grid.3x3.fill": ("grid-3x3", 1), "circle.grid.2x2.fill": ("layout-grid", 1), "circle.grid.3x3.fill": ("grip", 1),
    "square.grid.3x2": ("layout-grid", 0), "rectangle.grid.3x2": ("layout-grid", 0), "square.grid.4x3.fill": ("layout-grid", 1), "rectangle.grid.1x2.fill": ("rows-2", 1),
    "rectangle.split.2x2": ("layout-grid", 0), "tablecells.badge.ellipsis": ("table", 0), "rectangle.portrait.on.rectangle.portrait": ("copy", 0), "square.on.square.dashed": ("copy", 0),
    "square.on.square.squareshape.controlhandles": ("copy", 0), "square.dashed.inset.fill": ("square-dashed", 0), "rectangle.dashed": ("rectangle-horizontal", 0), "rectangle.dashed.badge.record": ("rectangle-horizontal", 0),
    "rectangle.badge.plus": ("rectangle-horizontal", 0), "rectangle.badge.checkmark": ("rectangle-horizontal", 0), "rectangle.badge.xmark": ("rectangle-horizontal", 0),
    "rectangle.and.pencil.and.ellipsis": ("square-pen", 0), "rectangle.portrait.and.arrow.right": ("log-out", 0), "rectangle.portrait.and.arrow.forward": ("log-out", 0),
    "arrow.right.square.fill": ("square-arrow-right", 2), "arrow.left.square": ("square-arrow-left", 0), "arrow.up.square": ("square-arrow-up", 0), "arrow.down.square": ("square-arrow-down", 0),
    "arrow.up.right.square.fill": ("square-arrow-out-up-right", 2), "arrow.up.left.square": ("square-arrow-up-left", 0), "arrow.down.right.square": ("square-arrow-down-right", 0),
    "arrow.up.forward.app": ("square-arrow-out-up-right", 0), "arrow.down.app": ("square-arrow-down", 0), "arrow.up.forward.square": ("square-arrow-out-up-right", 0),
    "arrow.down.circle.fill": ("circle-arrow-down", 2), "arrow.up.circle.fill": ("circle-arrow-up", 2), "arrow.right.circle.fill": ("circle-arrow-right", 2), "arrow.left.circle.fill": ("circle-arrow-left", 2),
    "arrow.up.right.circle": ("circle-arrow-out-up-right", 0), "arrow.down.left.circle": ("circle-arrow-out-down-left", 0), "arrow.clockwise.circle": ("rotate-cw", 0),
    "arrow.counterclockwise.circle": ("rotate-ccw", 0), "arrow.triangle.2.circlepath.circle": ("refresh-cw", 0), "arrow.triangle.branch": ("git-branch", 0), "arrow.triangle.merge": ("git-merge", 0),
    "arrow.triangle.pull": ("git-pull-request", 0), "arrow.triangle.swap": ("arrow-left-right", 0), "arrow.triangle.turn.up.right.diamond": ("navigation", 0),
    "arrow.triangle.turn.up.right.circle": ("navigation", 0), "arrow.left.arrow.right.square": ("square-arrow-left", 0), "arrow.up.arrow.down.square": ("square-arrow-up", 0),
    "arrow.up.arrow.down.circle": ("arrow-up-down", 0), "arrow.up.and.down.circle": ("move-vertical", 0), "arrow.left.and.right.circle": ("move-horizontal", 0),
    "arrow.up.left.and.arrow.down.right.circle": ("expand", 0), "arrow.down.right.and.arrow.up.left": ("shrink", 0), "arrow.down.right.and.arrow.up.left.circle": ("shrink", 0),
    "arrow.up.and.line.horizontal.and.arrow.down": ("unfold-vertical", 0), "arrow.down.and.line.horizontal.and.arrow.up": ("fold-vertical", 0),
    "arrow.left.and.line.vertical.and.arrow.right": ("unfold-horizontal", 0), "arrow.right.and.line.vertical.and.arrow.left": ("fold-horizontal", 0),
    "arrow.up.to.line.compact": ("arrow-up-to-line", 0), "arrow.down.to.line.compact": ("arrow-down-to-line", 0), "arrow.right.to.line.compact": ("arrow-right-to-line", 0),
    "arrow.left.to.line.compact": ("arrow-left-to-line", 0), "arrow.up.and.down.text.horizontal": ("move-vertical", 0), "arrow.left.and.right.text.vertical": ("move-horizontal", 0),
    "arrow.up.and.down.righttriangle.up.righttriangle.down": ("move-vertical", 0), "arrow.up.and.down.righttriangle.up.fill.righttriangle.down.fill": ("move-vertical", 0),
    "arrow.uturn.up": ("undo-2", 0), "arrow.uturn.down": ("redo-2", 0), "arrow.uturn.left.circle": ("undo-2", 0), "arrow.uturn.right.circle": ("redo-2", 0),
    "arrow.uturn.backward.circle": ("undo-2", 0), "arrow.uturn.forward.circle": ("redo-2", 0), "arrow.uturn.left.square": ("undo-2", 0), "arrow.uturn.right.square": ("redo-2", 0),
    "arrow.turn.right.up": ("corner-right-up", 0), "arrow.turn.right.down": ("corner-right-down", 0), "arrow.turn.left.up": ("corner-left-up", 0), "arrow.turn.left.down": ("corner-left-down", 0),
    "arrow.turn.up.forward.iphone": ("corner-up-right", 0), "arrow.turn.down.forward.iphone": ("corner-down-right", 0), "arrow.forward.circle": ("circle-arrow-right", 0),
    "arrow.backward.circle": ("circle-arrow-left", 0), "arrow.forward.square": ("square-arrow-right", 0), "arrow.backward.square": ("square-arrow-left", 0),
    "arrow.forward.to.line": ("arrow-right-to-line", 0), "arrow.backward.to.line": ("arrow-left-to-line", 0), "arrow.up.forward.circle": ("circle-arrow-out-up-right", 0),
    "arrow.down.backward.circle": ("circle-arrow-out-down-left", 0), "arrow.up.backward.circle": ("circle-arrow-out-up-left", 0), "arrow.down.forward.circle": ("circle-arrow-out-down-right", 0),
    "arrow.up.backward.square": ("square-arrow-up-left", 0), "arrow.down.forward.square": ("square-arrow-down-right", 0), "arrow.up.forward.and.arrow.down.backward": ("expand", 0),
    "arrow.down.forward.and.arrow.up.backward": ("shrink", 0), "arrow.up.backward.and.arrow.down.forward": ("expand", 0), "arrow.down.backward.and.arrow.up.forward": ("shrink", 0),
    "arrow.down.forward.and.arrow.up.backward.circle": ("shrink", 0), "arrow.up.forward.and.arrow.down.backward.circle": ("expand", 0),
    "arrow.rectanglepath": ("repeat", 0), "arrow.triangle.capsulepath": ("repeat", 0), "arrow.trianglehead.clockwise": ("rotate-cw", 0), "arrow.trianglehead.counterclockwise": ("rotate-ccw", 0),
    "arrow.trianglehead.2.clockwise": ("refresh-cw", 0), "arrow.trianglehead.2.counterclockwise": ("refresh-ccw", 0), "arrow.trianglehead.2.clockwise.rotate.90": ("refresh-cw", 0),
    "arrow.trianglehead.2.counterclockwise.rotate.90": ("refresh-ccw", 0), "arrow.trianglehead.clockwise.rotate.90": ("rotate-cw", 0), "arrow.trianglehead.counterclockwise.rotate.90": ("rotate-ccw", 0),
    "arrow.trianglehead.turn.up.right.diamond": ("navigation", 0), "arrow.trianglehead.turn.up.right.circle": ("navigation", 0), "arrow.trianglehead.branch": ("git-branch", 0),
    "arrow.trianglehead.merge": ("git-merge", 0), "arrow.trianglehead.pull": ("git-pull-request", 0), "arrow.trianglehead.swap": ("arrow-left-right", 0),
    "arrowshape.left": ("arrow-big-left", 0), "arrowshape.right": ("arrow-big-right", 0), "arrowshape.up": ("arrow-big-up", 0), "arrowshape.down": ("arrow-big-down", 0),
    "arrowshape.left.fill": ("arrow-big-left", 1), "arrowshape.right.fill": ("arrow-big-right", 1), "arrowshape.up.fill": ("arrow-big-up", 1), "arrowshape.down.fill": ("arrow-big-down", 1),
    "arrowshape.forward.fill": ("forward", 1), "arrowshape.backward.fill": ("reply", 1), "arrowshape.turn.up.left.fill": ("reply", 1), "arrowshape.turn.up.right.fill": ("forward", 1),
    "arrowshape.turn.up.left.2.fill": ("reply-all", 1), "arrowshape.turn.up.backward": ("reply", 0), "arrowshape.turn.up.forward": ("forward", 0),
    "arrowshape.turn.up.backward.2": ("reply-all", 0), "arrowshape.turn.up.left.circle": ("reply", 0), "arrowshape.turn.up.right.circle": ("forward", 0),
    "arrowshape.zigzag.right": ("zap", 0), "arrowshape.zigzag.forward": ("zap", 0), "arrowshape.bounce.right": ("redo", 0), "arrowshape.bounce.forward": ("redo", 0),
    "arrowtriangle.right": ("play", 0), "arrowtriangle.left": ("play", 0), "arrowtriangle.up": ("triangle", 0), "arrowtriangle.down": ("triangle", 0),
    "arrowtriangle.right.circle": ("circle-play", 0), "arrowtriangle.left.circle": ("circle-play", 0), "arrowtriangle.up.circle": ("circle-chevron-up", 0), "arrowtriangle.down.circle": ("circle-chevron-down", 0),
    "arrowtriangle.right.square": ("square-play", 0), "arrowtriangle.left.square": ("square-play", 0), "arrowtriangle.up.square": ("square-chevron-up", 0), "arrowtriangle.down.square": ("square-chevron-down", 0),
    "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left": ("fold-horizontal", 0), "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right": ("unfold-horizontal", 0),
    "arrowtriangle.up.arrowtriangle.down.window.left": ("app-window", 0), "arrowtriangle.up.arrowtriangle.down.window.right": ("app-window", 0),
    "chevron.left.circle": ("circle-chevron-left", 0), "chevron.up.circle": ("circle-chevron-up", 0), "chevron.down.circle": ("circle-chevron-down", 0),
    "chevron.left.circle.fill": ("circle-chevron-left", 2), "chevron.right.circle.fill": ("circle-chevron-right", 2), "chevron.up.circle.fill": ("circle-chevron-up", 2), "chevron.down.circle.fill": ("circle-chevron-down", 2),
    "chevron.left.square": ("square-chevron-left", 0), "chevron.right.square": ("square-chevron-right", 0), "chevron.up.square": ("square-chevron-up", 0), "chevron.down.square": ("square-chevron-down", 0),
    "chevron.left.square.fill": ("square-chevron-left", 2), "chevron.right.square.fill": ("square-chevron-right", 2), "chevron.up.square.fill": ("square-chevron-up", 2), "chevron.down.square.fill": ("square-chevron-down", 2),
    "chevron.up.2": ("chevrons-up", 0), "chevron.down.2": ("chevrons-down", 0), "chevron.compact.left": ("chevron-left", 0), "chevron.compact.right": ("chevron-right", 0),
    "chevron.compact.forward": ("chevron-right", 0), "chevron.compact.backward": ("chevron-left", 0), "chevron.forward.circle": ("circle-chevron-right", 0), "chevron.backward.circle": ("circle-chevron-left", 0),
    "chevron.forward.circle.fill": ("circle-chevron-right", 2), "chevron.backward.circle.fill": ("circle-chevron-left", 2), "chevron.forward.square": ("square-chevron-right", 0), "chevron.backward.square": ("square-chevron-left", 0),
    "chevron.forward.2": ("chevrons-right", 0), "chevron.backward.2": ("chevrons-left", 0), "chevron.left.chevron.right": ("chevrons-left-right", 0), "chevron.up.chevron.down.square": ("square-chevrons-up-down", 0),
    "chevron.up.chevron.down.circle": ("chevrons-up-down", 0), "chevron.forward.chevron.backward": ("chevrons-right-left", 0), "chevron.right.chevron.left": ("chevrons-right-left", 0),
    "chevron.down.right": ("chevron-right", 0), "chevron.down.left": ("chevron-left", 0), "chevron.up.right": ("chevron-right", 0), "chevron.up.left": ("chevron-left", 0),
    "ellipsis.circle.fill": ("circle-ellipsis", 2), "ellipsis.rectangle": ("rectangle-ellipsis", 0), "ellipsis.rectangle.fill": ("rectangle-ellipsis", 2), "ellipsis.vertical": ("ellipsis-vertical", 0),
    "ellipsis.vertical.circle": ("circle-ellipsis", 0), "ellipsis.message": ("message-square-more", 0), "ellipsis.curlybraces": ("braces", 0), "ellipsis.viewfinder": ("scan", 0),
    "line.3.horizontal.circle": ("menu", 0), "line.3.horizontal.circle.fill": ("menu", 0), "line.2.horizontal": ("equal", 0), "line.horizontal.2.decrease.circle": ("list-filter", 0),
    "line.3.horizontal.decrease.circle.fill": ("list-filter", 0), "line.horizontal.star.fill.line.horizontal": ("star", 1), "line.3.horizontal.button.angledtop.vertical.right": ("menu", 0),
    "line.diagonal": ("slash", 0), "line.diagonal.arrow": ("slash", 0), "line.horizontal.3.decrease": ("list-filter", 0), "slash.circle": ("ban", 0), "slash.circle.fill": ("ban", 2),
    "circle.slash": ("ban", 0), "circle.slash.fill": ("ban", 2), "circle.lefthalf.striped.horizontal": ("contrast", 0), "circle.righthalf.striped.horizontal": ("contrast", 0),
    "circle.bottomhalf.filled": ("contrast", 0), "circle.tophalf.filled": ("contrast", 0), "circle.and.line.horizontal": ("circle-dot", 0), "circle.hexagonpath": ("hexagon", 0),
    "circle.hexagonpath.fill": ("hexagon", 1), "circle.square": ("circle", 0), "circle.square.fill": ("circle", 1), "circle.badge.checkmark": ("circle-check", 0), "circle.badge.plus": ("circle-plus", 0),
    "circle.badge.minus": ("circle-minus", 0), "circle.badge.xmark": ("circle-x", 0), "circle.badge.questionmark": ("circle-question-mark", 0), "circle.badge.exclamationmark": ("circle-alert", 0),
    "circle.circle.fill": ("circle-dot", 2), "circle.inset.filled.circle": ("circle-dot", 0), "circle.grid.cross": ("grip", 0), "circle.grid.cross.fill": ("grip", 1),
    "circle.grid.2x1": ("circle", 0), "circle.grid.2x1.fill": ("circle", 1), "circle.grid.2x2.fill.rtl": ("layout-grid", 1), "circles.hexagongrid": ("grip", 0), "circles.hexagongrid.fill": ("grip", 1),
    "circles.hexagonpath": ("hexagon", 0), "circles.hexagonpath.fill": ("hexagon", 1), "circle.dashed.inset.filled": ("circle-dashed", 0), "circle.dotted.circle": ("circle-dashed", 0),
    "circle.dotted.circle.fill": ("circle-dashed", 2), "circle.dotted.and.circle": ("circle-dashed", 0), "circle.filled.pattern.diagonalline.rectangle": ("circle", 0),
    "square.circle": ("square", 0), "square.circle.fill": ("square", 1), "square.dotted": ("square-dashed", 0), "square.dashed.fill": ("square-dashed", 1),
    "square.lefthalf.filled": ("square", 0), "square.righthalf.filled": ("square", 0), "square.tophalf.filled": ("square", 0), "square.bottomhalf.filled": ("square", 0),
    "square.inset.filled": ("square", 0), "square.split.1x2": ("rows-2", 0), "square.split.bottomrightquarter": ("square", 0), "square.split.diagonal.2x2": ("square", 0),
    "square.grid.2x2.fill.rtl": ("layout-grid", 1), "square.grid.3x1.folder.badge.plus": ("folder-plus", 0), "square.grid.3x3.square": ("grid-3x3", 0), "square.grid.3x3.topleft.filled": ("grid-3x3", 0),
    "square.badge.plus": ("square-plus", 0), "square.badge.minus": ("square-minus", 0), "square.badge.xmark": ("square-x", 0), "square.badge.checkmark": ("square-check", 0),
    "square.and.arrow.up.circle": ("share", 0), "square.and.arrow.up.trianglebadge.exclamationmark": ("share", 0), "square.and.arrow.up.badge.clock": ("share", 0), "square.and.arrow.down.fill": ("download", 1),
    "square.and.arrow.down.on.square": ("download", 0), "square.and.arrow.up.on.square": ("share", 0), "square.and.arrow.down.on.square.fill": ("download", 1), "square.and.arrow.up.on.square.fill": ("share", 1),
    "square.and.pencil.circle": ("square-pen", 0), "square.and.pencil.circle.fill": ("square-pen", 2), "square.and.at.rectangle": ("at-sign", 0), "square.and.at.rectangle.fill": ("at-sign", 1),
    "square.and.line.vertical.and.square.filled": ("columns-2", 0), "square.filled.and.line.vertical.and.square": ("columns-2", 0), "square.on.circle": ("circle", 0), "square.on.circle.fill": ("circle", 1),
    "square.on.square.intersection.dashed": ("square-dashed", 0), "square.fill.on.circle.fill": ("circle", 1), "square.stack.3d.down.forward": ("layers", 0), "square.stack.3d.forward.dottedline": ("layers", 0),
    "square.stack.3d.up.badge.automatic": ("layers", 0), "square.stack.3d.up.slash": ("layers", 0), "square.stack.3d.up.trianglebadge.exclamationmark": ("layers", 0),
    "square.3.layers.3d.down.right": ("layers", 0), "square.3.layers.3d.down.left": ("layers", 0), "square.3.layers.3d.top.filled": ("layers", 0), "square.3.layers.3d.middle.filled": ("layers", 0),
    "square.3.layers.3d.bottom.filled": ("layers", 0), "square.2.layers.3d": ("layers", 0), "square.2.layers.3d.fill": ("layers", 1), "square.2.layers.3d.top.filled": ("layers", 0), "square.2.layers.3d.bottom.filled": ("layers", 0),
    "square.text.square": ("square", 0), "square.text.square.fill": ("square", 1), "square.leadingthird.inset.filled": ("panel-left", 0), "square.trailingthird.inset.filled": ("panel-right", 0),
    "square.topthird.inset.filled": ("panel-top", 0), "square.bottomthird.inset.filled": ("panel-bottom", 0), "square.leftthird.inset.filled": ("panel-left", 0), "square.rightthird.inset.filled": ("panel-right", 0),
    "square.split.2x2": ("layout-grid", 0), "square.split.2x2.fill": ("layout-grid", 1), "square.split.2x1.fill": ("columns-2", 1), "square.split.1x2.fill": ("rows-2", 1),
    "rectangle.split.3x1.fill": ("columns-3", 1), "rectangle.split.2x1.fill": ("columns-2", 1), "rectangle.split.1x2.fill": ("rows-2", 1), "rectangle.split.2x2.fill": ("layout-grid", 1),
    "rectangle.split.3x3.fill": ("grid-3x3", 1), "rectangle.leadinghalf.inset.filled": ("panel-left", 0), "rectangle.trailinghalf.inset.filled": ("panel-right", 0),
    "rectangle.tophalf.inset.filled": ("panel-top", 0), "rectangle.bottomhalf.inset.filled": ("panel-bottom", 0), "rectangle.lefthalf.filled": ("panel-left", 0), "rectangle.righthalf.filled": ("panel-right", 0),
    "rectangle.tophalf.filled": ("panel-top", 0), "rectangle.bottomhalf.filled": ("panel-bottom", 0), "rectangle.lefthalf.inset.filled": ("panel-left", 0), "rectangle.righthalf.inset.filled": ("panel-right", 0),
    "rectangle.lefthalf.inset.filled.arrow.left": ("panel-left-open", 0), "rectangle.righthalf.inset.filled.arrow.right": ("panel-right-open", 0), "rectangle.leadinghalf.inset.filled.arrow.leading": ("panel-left-open", 0),
    "rectangle.trailinghalf.inset.filled.arrow.trailing": ("panel-right-open", 0), "rectangle.topthird.inset.filled": ("panel-top", 0), "rectangle.bottomthird.inset.filled": ("panel-bottom", 0),
    "rectangle.leftthird.inset.filled": ("panel-left", 0), "rectangle.rightthird.inset.filled": ("panel-right", 0), "rectangle.leadingthird.inset.filled": ("panel-left", 0), "rectangle.trailingthird.inset.filled": ("panel-right", 0),
    "rectangle.center.inset.filled": ("rectangle-horizontal", 0), "rectangle.inset.topleft.filled": ("rectangle-horizontal", 0), "rectangle.inset.topright.filled": ("rectangle-horizontal", 0),
    "rectangle.inset.bottomleft.filled": ("rectangle-horizontal", 0), "rectangle.inset.bottomright.filled": ("rectangle-horizontal", 0), "rectangle.inset.filled.on.rectangle": ("app-window", 0),
    "rectangle.on.rectangle.circle": ("app-window", 0), "rectangle.on.rectangle.circle.fill": ("app-window", 2), "rectangle.on.rectangle.square": ("app-window", 0), "rectangle.on.rectangle.square.fill": ("app-window", 2),
    "rectangle.on.rectangle.slash": ("app-window", 0), "rectangle.on.rectangle.slash.fill": ("app-window", 1), "rectangle.on.rectangle.badge.gearshape": ("app-window", 0), "rectangle.on.rectangle.angled": ("app-window", 0),
    "rectangle.on.rectangle.angled.fill": ("app-window", 1), "rectangle.fill.on.rectangle.fill": ("app-window", 1), "rectangle.fill.on.rectangle.angled.fill": ("app-window", 1),
    "rectangle.2.swap": ("arrow-left-right", 0), "rectangle.portrait.split.2x1": ("rows-2", 0), "rectangle.portrait.split.2x1.fill": ("rows-2", 1), "rectangle.portrait.inset.filled": ("rectangle-vertical", 0),
    "rectangle.portrait.lefthalf.filled": ("rectangle-vertical", 0), "rectangle.portrait.righthalf.filled": ("rectangle-vertical", 0), "rectangle.portrait.tophalf.filled": ("rectangle-vertical", 0),
    "rectangle.portrait.bottomhalf.filled": ("rectangle-vertical", 0), "rectangle.portrait.on.rectangle.portrait.fill": ("copy", 1), "rectangle.portrait.on.rectangle.portrait.angled": ("copy", 0),
    "rectangle.portrait.on.rectangle.portrait.angled.fill": ("copy", 1), "rectangle.portrait.on.rectangle.portrait.slash": ("copy", 0), "rectangle.portrait.on.rectangle.portrait.slash.fill": ("copy", 1),
    "rectangle.portrait.badge.plus": ("rectangle-vertical", 0), "rectangle.portrait.badge.plus.fill": ("rectangle-vertical", 1), "rectangle.portrait.and.arrow.right.fill": ("log-out", 1),
    "rectangle.portrait.and.arrow.forward.fill": ("log-out", 1), "rectangle.portrait.arrowtriangle.2.outward": ("expand", 0), "rectangle.portrait.arrowtriangle.2.inward": ("shrink", 0),
    "rectangle.portrait.rotate": ("rotate-cw", 0), "rectangle.portrait.slash": ("rectangle-vertical", 0), "rectangle.portrait.slash.fill": ("rectangle-vertical", 1),
    "rectangle.portrait.topleft.inset.filled": ("rectangle-vertical", 0), "rectangle.portrait.topright.inset.filled": ("rectangle-vertical", 0), "rectangle.portrait.bottomleft.inset.filled": ("rectangle-vertical", 0),
    "rectangle.portrait.bottomright.inset.filled": ("rectangle-vertical", 0), "rectangle.portrait.center.inset.filled": ("rectangle-vertical", 0), "rectangle.portrait.lefthalf.inset.filled": ("rectangle-vertical", 0),
    "rectangle.portrait.righthalf.inset.filled": ("rectangle-vertical", 0), "rectangle.portrait.tophalf.inset.filled": ("rectangle-vertical", 0), "rectangle.portrait.bottomhalf.inset.filled": ("rectangle-vertical", 0),
    "rectangle.portrait.leadinghalf.inset.filled": ("rectangle-vertical", 0), "rectangle.portrait.trailinghalf.inset.filled": ("rectangle-vertical", 0), "rectangle.portrait.topthird.inset.filled": ("rectangle-vertical", 0),
    "rectangle.portrait.bottomthird.inset.filled": ("rectangle-vertical", 0), "rectangle.portrait.leftthird.inset.filled": ("rectangle-vertical", 0), "rectangle.portrait.rightthird.inset.filled": ("rectangle-vertical", 0),
    "rectangle.portrait.leadingthird.inset.filled": ("rectangle-vertical", 0), "rectangle.portrait.trailingthird.inset.filled": ("rectangle-vertical", 0),
    "rectangle.expand.diagonal": ("expand", 0), "rectangle.compress.diagonal": ("shrink", 0), "rectangle.arrowtriangle.2.outward": ("expand", 0), "rectangle.arrowtriangle.2.inward": ("shrink", 0),
    "rectangle.and.arrow.up.right.and.arrow.down.left": ("expand", 0), "rectangle.and.arrow.up.right.and.arrow.down.left.slash": ("expand", 0), "rectangle.and.hand.point.up.left": ("pointer", 0),
    "rectangle.and.hand.point.up.left.fill": ("pointer", 1), "rectangle.and.hand.point.up.left.filled": ("pointer", 0), "rectangle.and.hand.point.up.left.inset.filled": ("pointer", 0),
    "rectangle.and.text.magnifyingglass": ("scan-search", 0), "rectangle.and.text.magnifyingglass.rtl": ("scan-search", 0), "rectangle.connected.to.line.below": ("rectangle-horizontal", 0),
    "rectangle.fill.badge.plus": ("rectangle-horizontal", 1), "rectangle.fill.badge.minus": ("rectangle-horizontal", 1), "rectangle.fill.badge.xmark": ("rectangle-horizontal", 1),
    "rectangle.fill.badge.checkmark": ("rectangle-horizontal", 1), "rectangle.fill.badge.person.crop": ("rectangle-horizontal", 1), "rectangle.badge.person.crop": ("rectangle-horizontal", 0),
    "rectangle.slash": ("rectangle-horizontal", 0), "rectangle.slash.fill": ("rectangle-horizontal", 1), "rectangle.stack.badge.minus": ("layers", 0), "rectangle.stack.badge.person.crop": ("layers", 0),
    "rectangle.stack.badge.play": ("layers", 0), "rectangle.stack.fill.badge.plus": ("layers", 1), "rectangle.stack.fill.badge.minus": ("layers", 1), "rectangle.stack.fill.badge.person.crop": ("layers", 1),
    "rectangle.stack.fill.badge.play": ("layers", 1), "rectangle.3.group.bubble": ("layout-dashboard", 0), "rectangle.3.group.bubble.fill": ("layout-dashboard", 1),
    "rectangle.grid.3x2.fill": ("layout-grid", 1), "rectangle.grid.2x2.fill": ("layout-grid", 1), "rectangle.grid.1x2.fill.rtl": ("rows-2", 1), "rectangle.checkered": ("grid-3x3", 0),
    "rectangle.pattern.checkered": ("grid-3x3", 0), "rectangle.filled.and.hand.point.up.left": ("pointer", 0), "rectangle.stack.badge.person.crop.fill": ("layers", 1),
}

NUMBER = re.compile(r"[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?")


def arc_to_curves(x1, y1, rx, ry, phi, large, sweep, x2, y2):
    """Convert an SVG arc (endpoint parametrisation) to cubic Bézier segments."""
    if rx == 0 or ry == 0:
        return [("L", x2, y2)]
    phi = math.radians(phi)
    cos_phi, sin_phi = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cos_phi * dx + sin_phi * dy
    y1p = -sin_phi * dx + cos_phi * dy
    rx, ry = abs(rx), abs(ry)
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        rx *= math.sqrt(lam)
        ry *= math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = 0 if den == 0 else math.sqrt(max(0, num / den))
    if large == sweep:
        coef = -coef
    cxp = coef * rx * y1p / ry
    cyp = -coef * ry * x1p / rx
    cx = cos_phi * cxp - sin_phi * cyp + (x1 + x2) / 2
    cy = sin_phi * cxp + cos_phi * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        length = math.hypot(ux, uy) * math.hypot(vx, vy)
        a = math.acos(max(-1, min(1, dot / length)))
        return -a if ux * vy - uy * vx < 0 else a

    theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    elif sweep and delta < 0:
        delta += 2 * math.pi
    segments = max(1, int(math.ceil(abs(delta) / (math.pi / 2) - 1e-9)))
    step = delta / segments
    out = []
    t = theta1
    for _ in range(segments):
        alpha = math.sin(step) * (math.sqrt(4 + 3 * math.tan(step / 2) ** 2) - 1) / 3

        def point(a):
            px = rx * math.cos(a)
            py = ry * math.sin(a)
            return (cos_phi * px - sin_phi * py + cx, sin_phi * px + cos_phi * py + cy)

        def derivative(a):
            px = -rx * math.sin(a)
            py = ry * math.cos(a)
            return (cos_phi * px - sin_phi * py, sin_phi * px + cos_phi * py)

        p0 = point(t)
        p3 = point(t + step)
        d0 = derivative(t)
        d3 = derivative(t + step)
        c1 = (p0[0] + alpha * d0[0], p0[1] + alpha * d0[1])
        c2 = (p3[0] - alpha * d3[0], p3[1] - alpha * d3[1])
        out.append(("C", c1[0], c1[1], c2[0], c2[1], p3[0], p3[1]))
        t += step
    return out


def parse_path(d):
    """SVG path data -> list of absolute commands: ("M",x,y) ("L",x,y) ("C",x1,y1,x2,y2,x,y) ("Z",)."""
    tokens = re.findall(r"[MmLlHhVvCcSsQqTtAaZz]|" + NUMBER.pattern, d)
    out = []
    i = 0
    cmd = None
    x = y = 0.0
    sx = sy = 0.0
    last_c = None  # last cubic control point for S
    last_q = None  # last quadratic control point for T

    def nums(n):
        nonlocal i
        vals = [float(tokens[i + k]) for k in range(n)]
        i += n
        return vals

    while i < len(tokens):
        t = tokens[i]
        if re.match(r"[A-Za-z]", t):
            cmd = t
            i += 1
            if cmd in "Zz":
                out.append(("Z",))
                x, y = sx, sy
                last_c = last_q = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            nx, ny = nums(2)
            if rel:
                nx += x
                ny += y
            out.append(("M", nx, ny))
            x, y = nx, ny
            sx, sy = x, y
            cmd = "l" if rel else "L"
            last_c = last_q = None
        elif c == "L":
            nx, ny = nums(2)
            if rel:
                nx += x
                ny += y
            out.append(("L", nx, ny))
            x, y = nx, ny
            last_c = last_q = None
        elif c == "H":
            (nx,) = nums(1)
            if rel:
                nx += x
            out.append(("L", nx, y))
            x = nx
            last_c = last_q = None
        elif c == "V":
            (ny,) = nums(1)
            if rel:
                ny += y
            out.append(("L", x, ny))
            y = ny
            last_c = last_q = None
        elif c == "C":
            x1, y1, x2, y2, nx, ny = nums(6)
            if rel:
                x1 += x; y1 += y; x2 += x; y2 += y; nx += x; ny += y
            out.append(("C", x1, y1, x2, y2, nx, ny))
            last_c = (x2, y2)
            last_q = None
            x, y = nx, ny
        elif c == "S":
            x2, y2, nx, ny = nums(4)
            if rel:
                x2 += x; y2 += y; nx += x; ny += y
            x1, y1 = (2 * x - last_c[0], 2 * y - last_c[1]) if last_c else (x, y)
            out.append(("C", x1, y1, x2, y2, nx, ny))
            last_c = (x2, y2)
            last_q = None
            x, y = nx, ny
        elif c in ("Q", "T"):
            if c == "Q":
                qx, qy, nx, ny = nums(4)
                if rel:
                    qx += x; qy += y; nx += x; ny += y
            else:
                nx, ny = nums(2)
                if rel:
                    nx += x; ny += y
                qx, qy = (2 * x - last_q[0], 2 * y - last_q[1]) if last_q else (x, y)
            # Quadratic -> cubic.
            x1, y1 = x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y)
            x2, y2 = nx + 2 / 3 * (qx - nx), ny + 2 / 3 * (qy - ny)
            out.append(("C", x1, y1, x2, y2, nx, ny))
            last_q = (qx, qy)
            last_c = None
            x, y = nx, ny
        elif c == "A":
            rx, ry, rot = nums(3)
            # The two flags are single characters and may be glued to each other or to the next
            # number ("0 01-2.5", "1 1.95"); peel them off the token stream one character at a time.
            flags = []
            while len(flags) < 2:
                tok = tokens[i]
                flags.append(int(tok[0]))
                rest = tok[1:]
                if rest:
                    tokens[i] = rest
                else:
                    i += 1
            large, sweep = flags
            nx, ny = nums(2)
            if rel:
                nx += x; ny += y
            out += arc_to_curves(x, y, rx, ry, rot, int(large) != 0, int(sweep) != 0, nx, ny)
            x, y = nx, ny
            last_c = last_q = None
        else:
            raise ValueError(f"unsupported path command {cmd}")
    return out


K = 0.5522847498  # circle control-point factor


def ellipse(cx, cy, rx, ry):
    return [
        ("M", cx + rx, cy),
        ("C", cx + rx, cy + K * ry, cx + K * rx, cy + ry, cx, cy + ry),
        ("C", cx - K * rx, cy + ry, cx - rx, cy + K * ry, cx - rx, cy),
        ("C", cx - rx, cy - K * ry, cx - K * rx, cy - ry, cx, cy - ry),
        ("C", cx + K * rx, cy - ry, cx + rx, cy - K * ry, cx + rx, cy),
        ("Z",),
    ]


def element_commands(tag, attrs):
    f = lambda k, default=0.0: float(attrs.get(k, default))
    if tag == "path":
        return parse_path(attrs["d"])
    if tag == "circle":
        return ellipse(f("cx"), f("cy"), f("r"), f("r"))
    if tag == "ellipse":
        return ellipse(f("cx"), f("cy"), f("rx"), f("ry"))
    if tag == "rect":
        x, y, w, h = f("x"), f("y"), f("width"), f("height")
        rx = f("rx", attrs.get("ry", 0))
        ry = f("ry", rx)
        if rx == 0 and ry == 0:
            return [("M", x, y), ("L", x + w, y), ("L", x + w, y + h), ("L", x, y + h), ("Z",)]
        rx, ry = min(rx, w / 2), min(ry, h / 2)
        return [
            ("M", x + rx, y), ("L", x + w - rx, y),
            ("C", x + w - rx + K * rx, y, x + w, y + ry - K * ry, x + w, y + ry),
            ("L", x + w, y + h - ry),
            ("C", x + w, y + h - ry + K * ry, x + w - rx + K * rx, y + h, x + w - rx, y + h),
            ("L", x + rx, y + h),
            ("C", x + rx - K * rx, y + h, x, y + h - ry + K * ry, x, y + h - ry),
            ("L", x, y + ry),
            ("C", x, y + ry - K * ry, x + rx - K * rx, y, x + rx, y),
            ("Z",),
        ]
    if tag == "line":
        return [("M", f("x1"), f("y1")), ("L", f("x2"), f("y2"))]
    if tag in ("polyline", "polygon"):
        pts = [float(v) for v in NUMBER.findall(attrs["points"])]
        cmds = [("M", pts[0], pts[1])] + [("L", pts[i], pts[i + 1]) for i in range(2, len(pts), 2)]
        if tag == "polygon":
            cmds.append(("Z",))
        return cmds
    raise ValueError(f"unsupported element {tag}")


def bounds(commands, stroke=2.0):
    xs, ys = [], []
    for c in commands:
        for k in range(1, len(c), 2):
            xs.append(c[k])
            ys.append(c[k + 1])
    half = stroke / 2
    return (min(xs) - half, min(ys) - half, max(xs) + half, max(ys) + half)


def encode(commands):
    ops = []
    for c in commands:
        if c[0] == "M":
            ops += [0, c[1], c[2]]
        elif c[0] == "L":
            ops += [1, c[1], c[2]]
        elif c[0] == "C":
            ops += [2] + list(c[1:])
        else:
            ops.append(3)
    return ops


def fmt(v):
    if isinstance(v, int):
        return str(v)
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return s if s not in ("", "-0") else "0"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    nodes = json.loads(Path(sys.argv[1]).read_text())
    names = []
    icons = {}
    missing = []
    for sf_name in sorted(MAPPING):
        icon, mode = MAPPING[sf_name]
        if icon not in nodes:
            missing.append((sf_name, icon))
            continue
        if icon not in icons:
            try:
                elements = [element_commands(tag, attrs) for tag, attrs in nodes[icon]]
            except Exception as error:  # noqa: BLE001
                sys.exit(f"{icon}: {error}: {nodes[icon]}")
            all_commands = [c for e in elements for c in e]
            x0, y0, x1, y1 = bounds(all_commands)
            first = len(encode(elements[0]))
            ops = " ".join(fmt(v) for v in encode(all_commands))
            icons[icon] = f"{icon}|{first}|{fmt(x0)} {fmt(y0)} {fmt(x1)} {fmt(y1)}|{ops}"
        names.append((sf_name, icon, mode))
    if missing:
        print("not in the icon set:", ", ".join(f"{s} -> {i}" for s, i in missing), file=sys.stderr)
    header = f'''// Generated by scripts/symbol-glyphs.py from the Lucide icon set; do not edit.
//
// Lucide is licensed under the ISC License, Copyright (c) 2026 Lucide Icons and Contributors
// (https://lucide.dev, https://github.com/lucide-icons/lucide/blob/main/LICENSE). Permission to
// use, copy, modify, and/or distribute this software for any purpose with or without fee is
// hereby granted, provided that the above copyright notice and this permission notice appear in
// all copies. THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
// REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS.
//
// The glyphs `Image(systemName:)` draws, by SF Symbol name (Docs/elements/Image.md). SF Symbols
// are never shipped; these stand in for them. Each outline is on Lucide's 24 × 24 grid, stroked
// 2 wide with round caps and joins: `ops` is a flat command list (0 move x y, 1 line x y, 2 curve
// x1 y1 x2 y2 x y, 3 close), `bounds` the outline including the stroke, `firstElement` the
// length of the first element's ops. A name's `mode` is 0 stroke, 1 fill and stroke, 2 fill the
// first element and stroke the rest in the knockout colour. The tables are string blobs parsed
// on first use (array literals this large compile into code, not data).

/// A symbol name's glyph: the icon it draws and how (`mode`).
public struct SymbolGlyph: Sendable {{
    public let icon: String
    public let mode: Int
}}

/// An icon's outline on the 24 × 24 grid.
public struct SymbolGlyphOutline: Sendable {{
    public let firstElement: Int
    public let bounds: (Double, Double, Double, Double)
    public let ops: [Double]
}}

@MainActor
public enum SystemSymbolGlyphs {{
    public static let count = {len(names)}

    public static func glyph(named name: String) -> (SymbolGlyph, SymbolGlyphOutline)? {{
        guard let glyph = table[name], let outline = outline(for: glyph.icon) else {{ return nil }}
        return (glyph, outline)
    }}

    /// name|icon|mode per line; readable from any context, as `UIImage(systemName:)` is.
    nonisolated public static let table: [String: SymbolGlyph] = {{
        var table: [String: SymbolGlyph] = [:]
        for line in namesBlob.split(separator: "\\n") {{
            let parts = line.split(separator: "|")
            guard parts.count == 3, let mode = Int(parts[2]) else {{ continue }}
            table[String(parts[0])] = SymbolGlyph(icon: String(parts[1]), mode: mode)
        }}
        return table
    }}()

    /// icon|firstElement|x0 y0 x1 y1|ops per line, parsed on demand.
    private static let outlineLines: [String: Substring] = {{
        var lines: [String: Substring] = [:]
        for line in outlinesBlob.split(separator: "\\n") {{
            if let bar = line.firstIndex(of: "|") {{ lines[String(line[..<bar])] = line[line.index(after: bar)...] }}
        }}
        return lines
    }}()
    private static var outlines: [String: SymbolGlyphOutline] = [:]

    public static func outline(for icon: String) -> SymbolGlyphOutline? {{
        if let cached = outlines[icon] {{ return cached }}
        guard let line = outlineLines[icon] else {{ return nil }}
        let parts = line.split(separator: "|")
        guard parts.count == 3, let first = Int(parts[0]) else {{ return nil }}
        let b = parts[1].split(separator: " ").compactMap {{ Double($0) }}
        guard b.count == 4 else {{ return nil }}
        let outline = SymbolGlyphOutline(firstElement: first, bounds: (b[0], b[1], b[2], b[3]), ops: parts[2].split(separator: " ").compactMap {{ Double($0) }})
        outlines[icon] = outline
        return outline
    }}

    nonisolated private static let namesBlob = """
'''
    names_blob = "\n".join(f"{sf}|{icon}|{mode}" for sf, icon, mode in names)
    outlines_blob = "\n".join(icons[k] for k in sorted(icons))
    OUT.write_text(header + names_blob + "\n\"\"\"\n\n    private static let outlinesBlob = \"\"\"\n" + outlines_blob + "\n\"\"\"\n}\n")
    print(f"wrote {OUT.relative_to(ROOT)}: {len(names)} names, {len(icons)} icons")


if __name__ == "__main__":
    main()
