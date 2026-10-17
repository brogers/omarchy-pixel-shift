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
  // is disabled or reloaded: [{ item, prop, edge }].
  property var touched: []

  function clampInt(value, lo, hi) {
    var n = Math.round(Number(value))
    return isFinite(n) ? Math.min(hi, Math.max(lo, n)) : lo
  }

  // ------------------------------------------------------------- schedule

  // One wakeup per step: the timer is re-armed to the next phase boundary.
  // A second of slack keeps Qt's coarse timer from firing just before it.
  Timer {
    id: clock
    onTriggered: root.sync()
  }

  function sync() {
    var now = Date.now()
    var ms = root.intervalSec * 1000
    root.phase = Schedule.phase(Schedule.shared, now, ms)
    clock.interval = Schedule.nextBoundary(Schedule.shared, now, ms) - now + 1000
    clock.restart()
  }

  // A workspace switch redraws part of the bar anyway, which hides a shift
  // far better than a timer firing on a still screen. Take the opportunity
  // when at least a quarter of the interval has passed since the last move.
  // Every instance resyncs, so all monitors step together whichever one
  // advanced the shared clock.
  function maskedShift() {
    var now = Date.now()
    var ms = root.intervalSec * 1000
    if (Schedule.maskedShiftDue(Schedule.shared, now, ms, ms / 4)) Schedule.advance(Schedule.shared, now, ms)
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
  onEdgeBaseChanged: apply()
  onBarChanged: Qt.callLater(apply)

  // Slots register as each monitor's bar builds; re-apply when the set
  // changes so a late bar, or a new monitor, is covered too. Qt.callLater
  // folds a burst of registrations into one pass.
  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onModuleSlotsChanged() { Qt.callLater(root.apply) }
  }

  Component.onCompleted: sync()
  Component.onDestruction: restore()

  // ---------------------------------------------------------------- apply

  // The section list a slot belongs to: the Loader whose loaded Row/Column
  // is the slot's parent. It carries the section name in `region`.
  function sectionList(slot) {
    var row = slot.parent
    var list = row ? row.parent : null
    return list && list.item === row && typeof list.region === "string" ? list : null
  }

  function poke(item, prop, value, edge) {
    if (item.anchors[prop] === value) return
    item.anchors[prop] = value
    for (var i = 0; i < touched.length; i++) {
      if (touched[i].item === item && touched[i].prop === prop) return
    }
    touched.push({ item: item, prop: prop, edge: edge })
  }

  // The item that holds one bar surface's sections: the ancestor of this
  // widget with both a left and a right section list among its children.
  // Section lists are told apart from the slots inside them by their `keys`.
  function barContent() {
    for (var item = root.parent; item; item = item.parent) {
      var kids = item.children
      var left = false, right = false
      for (var i = 0; i < kids.length; i++) {
        if (kids[i].keys === undefined) continue
        if (kids[i].region === "left") left = true
        else if (kids[i].region === "right") right = true
      }
      if (left && right) return item
    }
    return null
  }

  // Omarchy 4.0 hands a third-party widget a scoped `bar` with no slots, but
  // the widget still sits in the bar's scene, so the parts to move are found
  // from there instead: the left and right section lists, and the item that
  // places the center box and the lists hanging off it (CenterSections). That
  // item fills the bar and binds its children's x/y, so it is moved as a
  // whole through its fill margins rather than by touching those bindings.
  // The copy drawn beside the right section under a display notch already
  // follows the right section and is left alone.
  function applyScene() {
    var content = barContent()
    if (!content) return
    var edge = root.edgeBase + root.edgeOffset
    var kids = content.children
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      if (kid.keys !== undefined && kid.region === "left") poke(kid, root.vertical ? "topMargin" : "leftMargin", edge, true)
      else if (kid.keys !== undefined && kid.region === "right") poke(kid, root.vertical ? "bottomMargin" : "rightMargin", edge, true)
      var inner = kid.children
      for (var j = 0; j < inner.length; j++) {
        var sections = inner[j]
        if (sections.besideRight !== false || !sections.anchors.fill) continue
        poke(sections, root.vertical ? "topMargin" : "leftMargin", root.centerOffset, false)
        poke(sections, root.vertical ? "bottomMargin" : "rightMargin", -root.centerOffset, false)
      }
    }
  }

  function apply() {
    // The base class types `bar` as a bare QtObject; a bar without slots is
    // the scoped one third-party widgets get.
    var slots = root.bar ? root.bar.moduleSlots : null // qmllint disable missing-property
    if (!Array.isArray(slots)) return applyScene()
    var edge = root.edgeBase + root.edgeOffset
    var centerProp = root.vertical ? "verticalCenterOffset" : "horizontalCenterOffset"
    var seen = []
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      var list = sectionList(slot)
      if (list && seen.indexOf(list) === -1) {
        seen.push(list)
        if (list.region === "left") poke(list, root.vertical ? "topMargin" : "leftMargin", edge, true)
        else if (list.region === "right") poke(list, root.vertical ? "bottomMargin" : "rightMargin", edge, true)
        else if (list.region === "center" && list.anchors.centerIn) poke(list, centerProp, root.centerOffset, false)
      }
      // With a center anchor set, the anchored module's slot is what the bar
      // pins to the middle of the screen; the lists beside it follow it.
      if (slot.region === "center" && slot.anchors.centerIn) poke(slot, centerProp, root.centerOffset, false)
    }
  }

  function restore() {
    var items = touched
    touched = []
    for (var i = 0; i < items.length; i++) {
      var t = items[i]
      if (t.item) t.item.anchors[t.prop] = t.edge ? root.edgeBase : 0
    }
  }
}
