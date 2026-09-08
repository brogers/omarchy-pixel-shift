import QtQuick
import QtTest
import "../core/Schedule.js" as Schedule

TestCase {
  name: "Schedule"

  function test_positions() {
    compare(Schedule.positions(2, 2), [-2, 0, 2])
    compare(Schedule.positions(1, 1), [-1, 0, 1])
    compare(Schedule.positions(4, 1), [-4, -3, -2, -1, 0, 1, 2, 3, 4])
    compare(Schedule.positions(3, 2), [-2, 0, 2])      // travel not a multiple of step stays inside travel
    compare(Schedule.positions(0, 2), [0])
    compare(Schedule.positions(-5, 0), [0])            // garbage in, resting position out
    compare(Schedule.positions("2", "2"), [-2, 0, 2])
  }

  function test_cycle_visits_every_position_equally_with_small_moves() {
    compare(Schedule.cycle(2, 2), [-2, 0, 2, 2, 0, -2])
    compare(Schedule.cycle(1, 1), [-1, 0, 1, 1, 0, -1])
    compare(Schedule.cycle(0, 1), [0])
    var c = Schedule.cycle(4, 1)
    compare(c.length, 18)
    var dwell = {}
    for (var i = 0; i < c.length; i++) {
      dwell[c[i]] = (dwell[c[i]] || 0) + 1
      compare(Math.abs(c[i] - c[(i + 1) % c.length]) <= 1, true)   // wrap-around included
    }
    for (var k = -4; k <= 4; k++) compare(dwell[k], 2)
  }

  function test_positionAt_wraps_in_both_directions() {
    compare(Schedule.positionAt(0, 2, 2), -2)
    compare(Schedule.positionAt(2, 2, 2), 2)
    compare(Schedule.positionAt(3, 2, 2), 2)
    compare(Schedule.positionAt(6, 2, 2), -2)
    compare(Schedule.positionAt(-1, 2, 2), -2)
    compare(Schedule.positionAt(7, 0, 2), 0)
    compare(Schedule.positionAt(1e9 + 1, 1, 1), -1)   // 1e9+1 = 5 mod 6
  }

  function test_phase_follows_the_wall_clock_from_epoch_zero() {
    var s = Schedule.newState()
    var ms = 180000
    compare(Schedule.phase(s, 0, ms), 0)
    compare(Schedule.phase(s, ms - 1, ms), 0)
    compare(Schedule.phase(s, ms, ms), 1)
    compare(Schedule.phase(s, 10 * ms + 5, ms), 10)
    compare(Schedule.nextBoundary(s, 10 * ms + 5, ms), 11 * ms)
    compare(Schedule.intervalMs(0), 1000)                // never a busy loop
    compare(Schedule.intervalMs("abc"), 1000)
  }

  function test_observe_records_the_moment_a_phase_first_appears() {
    var s = Schedule.newState()
    var ms = 60000
    compare(Schedule.observe(s, 5 * ms + 100, ms), 5)
    compare(s.lastShift, 5 * ms + 100)
    compare(Schedule.observe(s, 5 * ms + 30000, ms), 5)  // same phase: not a shift
    compare(s.lastShift, 5 * ms + 100)
    compare(Schedule.observe(s, 6 * ms + 7, ms), 6)
    compare(s.lastShift, 6 * ms + 7)
  }

  function test_advance_starts_a_new_phase_now_and_keeps_the_rhythm() {
    var s = Schedule.newState()
    var ms = 60000
    var now = 5 * ms + 20000
    compare(Schedule.observe(s, now, ms), 5)
    compare(Schedule.advance(s, now, ms), 6)
    compare(Schedule.phase(s, now, ms), 6)
    compare(Schedule.phase(s, now - 1, ms), 5)
    compare(Schedule.nextBoundary(s, now, ms), now + ms)
    compare(s.lastShift, now)
    compare(Schedule.observe(s, now + ms, ms), 7)
  }

  function test_masked_shifts_keep_their_distance() {
    var s = Schedule.newState()
    var ms = 60000
    Schedule.observe(s, 100000, ms)
    compare(Schedule.maskedShiftDue(s, 100000 + ms / 4 - 1, ms / 4), false)
    compare(Schedule.maskedShiftDue(s, 100000 + ms / 4, ms / 4), true)
    Schedule.advance(s, 100000 + ms / 4, ms)
    compare(Schedule.maskedShiftDue(s, 100000 + ms / 4 + 1000, ms / 4), false)
  }

  function test_shared_state_is_one_object() {
    compare(Schedule.shared === Schedule.shared, true)
    compare(typeof Schedule.shared.epoch, "number")
  }
}
