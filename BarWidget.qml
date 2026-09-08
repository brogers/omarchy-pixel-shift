import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "core/Schedule.js" as Schedule

// Pixel Shift: an invisible bar widget that slowly walks the bar's edge
// padding and center offset a few pixels back and forth, so the static bar
// pixels of an OLED panel wear evenly instead of burning in.
//
// It draws nothing and takes no space. Wherever it sits in the layout, it
// finds the three things the built-in bar pins to the screen — the left
// section, the right section and the centered module — and nudges them:
//   left/right sections   margin 8 ± edgeTravel  (both move inward together)
//   centered module       center offset ± centerTravel
// On a vertical bar the same happens along the bar's long axis.
BarWidget {
  id: root
  moduleName: "io.github.evindor.pixel-shift"

  implicitWidth: 0
  implicitHeight: 0
  visible: false

  readonly property int intervalSec: clampInt(setting("intervalSec", 180), 10, 3600)
  readonly property int edgeTravel: clampInt(setting("edgeTravel", 2), 0, 8)
  readonly property int edgeStep: clampInt(setting("edgeStep", 2), 1, 4)
  readonly property int centerTravel: clampInt(setting("centerTravel", 1), 0, 4)
  readonly property bool shiftOnWorkspaceSwitch: setting("shiftOnWorkspaceSwitch", true) !== false

  // The distance the bar keeps from the screen edge in the built-in bar; the
  // shift is applied on top of it, so the resting position is unchanged.
  readonly property int edgeBase: Style.space(8)

  property int phase: 0
  readonly property int edgeOffset: Schedule.positionAt(phase, edgeTravel, edgeStep)
  readonly property int centerOffset: Schedule.positionAt(phase, centerTravel, 1)

  // Items this instance has moved, so they can be put back when the plugin
  // is disabled or removed: [{ item, prop, rest }].
  property var touched: []

  function clampInt(value, lo, hi) {
    var n = Math.round(Number(value))
    if (!isFinite(n)) n = lo
    return Math.min(hi, Math.max(lo, n))
  }

  // ------------------------------------------------------------- schedule

  Timer {
    id: clock
    repeat: false
    onTriggered: root.sync()
  }

  function sync() {
    var now = Date.now()
    var ms = root.intervalSec * 1000
    root.phase = Schedule.observe(Schedule.shared, now, ms)
    root.apply()
    clock.interval = Math.max(250, Schedule.nextBoundary(Schedule.shared, now, ms) - now + 20)
    clock.restart()
  }

  // A workspace switch redraws part of the bar anyway, which hides a shift
  // far better than a timer firing on a still screen. Take the opportunity
  // when at least a quarter of the interval has passed since the last move.
  function maskedShift() {
    if (!root.shiftOnWorkspaceSwitch) return
    var now = Date.now()
    var ms = root.intervalSec * 1000
    if (!Schedule.maskedShiftDue(Schedule.shared, now, ms / 4)) return
    Schedule.advance(Schedule.shared, now, ms)
    root.sync()
  }

  Connections {
    target: Hyprland
    enabled: root.shiftOnWorkspaceSwitch
    function onFocusedWorkspaceChanged() { root.maskedShift() }
  }

  onIntervalSecChanged: sync()
  onEdgeOffsetChanged: apply()
  onCenterOffsetChanged: apply()
  onBarChanged: Qt.callLater(apply)

  // Slots register as each monitor's bar builds; re-apply when the set
  // changes so a late bar, or a new monitor, is covered too.
  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onModuleSlotsChanged() { Qt.callLater(root.apply) }
  }

  Component.onCompleted: sync()
  Component.onDestruction: {
    clock.stop()
    restore()
  }

  // ---------------------------------------------------------------- apply

  // The section list a slot belongs to: the Loader whose loaded Row/Column
  // is the slot's parent. It carries the section name in `region`.
  function sectionList(slot) {
    var row = slot ? slot.parent : null
    var list = row ? row.parent : null
    if (!list || list.item !== row || typeof list.region !== "string") return null
    return list
  }

  function isCentered(item) {
    return !!item && !!item.anchors && item.anchors.centerIn !== null && item.anchors.centerIn !== undefined
  }

  function poke(item, prop, value, rest) {
    if (!item || !item.anchors) return
    if (item.anchors[prop] === value) return
    item.anchors[prop] = value
    for (var i = 0; i < touched.length; i++) {
      if (touched[i].item === item && touched[i].prop === prop) return
    }
    touched.push({ item: item, prop: prop, rest: rest })
  }

  // Duck-typed on purpose: the base class types `bar` as a bare QtObject,
  // and a bar that lacks these is one this plugin leaves alone.
  function hostProp(name) {
    var host = root.bar
    return host ? host[name] : undefined
  }

  function apply() {
    var slots = hostProp("moduleSlots")
    if (!Array.isArray(slots)) return
    var vertical = hostProp("vertical") === true
    var edge = root.edgeBase + root.edgeOffset
    var centerProp = vertical ? "verticalCenterOffset" : "horizontalCenterOffset"
    var seen = []
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot) continue
      var list = sectionList(slot)
      if (list && seen.indexOf(list) === -1) {
        seen.push(list)
        if (list.region === "left") poke(list, vertical ? "topMargin" : "leftMargin", edge, root.edgeBase)
        else if (list.region === "right") poke(list, vertical ? "bottomMargin" : "rightMargin", edge, root.edgeBase)
        else if (list.region === "center" && isCentered(list)) poke(list, centerProp, root.centerOffset, 0)
      }
      // With a center anchor set, the anchored module's slot is what the bar
      // pins to the middle of the screen; the lists beside it follow it.
      if (slot.region === "center" && isCentered(slot)) poke(slot, centerProp, root.centerOffset, 0)
    }
  }

  function restore() {
    var items = touched
    touched = []
    for (var i = 0; i < items.length; i++) {
      try {
        var t = items[i]
        if (t.item && t.item.anchors) t.item.anchors[t.prop] = t.rest
      } catch (e) {
        // The bar tore the item down before this widget; nothing to put back.
      }
    }
  }
}
