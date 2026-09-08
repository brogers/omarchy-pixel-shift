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
  var n = Math.floor(travel / step)
  var out = []
  for (var k = -n; k <= n; k++) out.push(k * step)
  return out
}

// One full walk: out to one end, hold, back to the other end, hold:
// [-2, 0, 2, 2, 0, -2]. Two properties matter for burn-in and for the eye:
// every position appears exactly twice per cycle, so each spot on the panel
// gets the same share of wear; and neighbouring phases differ by at most one
// step, so no single move is bigger than `step`.
function cycle(travel, step) {
  var p = positions(travel, step)
  return p.length > 1 ? p.concat(p.slice().reverse()) : p
}

function positionAt(phase, travel, step) {
  var c = cycle(travel, step)
  return c[((phase % c.length) + c.length) % c.length]
}

// ----------------------------------------------------------------- clock

// Phases are whole intervals counted from `epoch`. With epoch 0 the phase
// derives from the wall clock, so a restarted shell does not resume at the
// same position every time.
var shared = { epoch: 0 }

function phase(state, now, ms) {
  return Math.floor((now - state.epoch) / ms)
}

function nextBoundary(state, now, ms) {
  return state.epoch + (phase(state, now, ms) + 1) * ms
}

// Whether a masked shift may run: at least `minGap` ms of the current phase
// have passed, so a burst of workspace switches does not turn into a jitter.
function maskedShiftDue(state, now, ms, minGap) {
  return (now - state.epoch) % ms >= minGap
}

// Start a new phase now; the interval rhythm continues from this moment.
function advance(state, now, ms) {
  state.epoch = now - (phase(state, now, ms) + 1) * ms
}
