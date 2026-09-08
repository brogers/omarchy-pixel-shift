.pragma library

// Pixel Shift schedule: pure functions plus one shared clock.
//
// A `.pragma library` file is instantiated once per QML engine, so `shared`
// below is the same object for every bar widget instance in the shell (one
// per monitor). All instances read the same phase and therefore move together.

// Positions visited around the resting point, `step` px apart and at most
// `travel` px away: travel 2 / step 2 -> [-2, 0, 2]; travel 1 / step 1 ->
// [-1, 0, 1]; travel 0 -> [0].
function positions(travel, step) {
  var t = Math.max(0, Math.floor(Number(travel) || 0))
  var s = Math.max(1, Math.floor(Number(step) || 1))
  var n = Math.floor(t / s)
  var out = []
  for (var k = -n; k <= n; k++) out.push(k * s)
  return out
}

// One full walk: out to one end, hold, back to the other end, hold:
// [-2, 0, 2, 2, 0, -2]. Two properties matter for burn-in and for the eye:
// every position appears exactly twice per cycle, so each spot on the panel
// gets the same share of wear; and neighbouring phases differ by at most one
// step, so no single move is bigger than `step`.
function cycle(travel, step) {
  var p = positions(travel, step)
  if (p.length <= 1) return p
  return p.concat(p.slice().reverse())
}

function positionAt(phase, travel, step) {
  var c = cycle(travel, step)
  if (c.length === 0) return 0
  var i = ((Math.floor(Number(phase) || 0) % c.length) + c.length) % c.length
  return c[i]
}

// ----------------------------------------------------------------- clock

// Phases are counted from `epoch` in whole intervals. With epoch 0 the phase
// derives from the wall clock, so a restarted shell does not resume at the
// same position every time. `advance` moves the epoch so a new phase begins
// now (a masked shift) and the interval rhythm continues from that moment.
function newState() {
  return { epoch: 0, seenPhase: null, lastShift: 0 }
}

var shared = newState()

function intervalMs(value) {
  var ms = Math.floor(Number(value) || 0)
  return Math.max(1000, ms)
}

function phase(state, now, interval) {
  return Math.floor((now - state.epoch) / intervalMs(interval))
}

function nextBoundary(state, now, interval) {
  var ms = intervalMs(interval)
  return state.epoch + (phase(state, now, ms) + 1) * ms
}

// Current phase, recording the moment it was first observed so masked
// shifts can keep their distance from the last move.
function observe(state, now, interval) {
  var p = phase(state, now, interval)
  if (state.seenPhase !== p) {
    state.seenPhase = p
    state.lastShift = now
  }
  return p
}

// Whether a masked shift may run now: at least `minGap` ms since the last
// move, so a burst of workspace switches does not turn into a jitter.
function maskedShiftDue(state, now, minGap) {
  return now - state.lastShift >= Math.max(0, Number(minGap) || 0)
}

function advance(state, now, interval) {
  var ms = intervalMs(interval)
  var next = phase(state, now, ms) + 1
  state.epoch = now - next * ms
  state.seenPhase = next
  state.lastShift = now
  return next
}
