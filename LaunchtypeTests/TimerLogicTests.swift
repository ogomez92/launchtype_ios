import Foundation
import Testing
@testable import Launchtype

/// Port of the desktop `timers.rs` engine tests.
struct TimerLogicTests {
    private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

    private func oneShot(minutes: UInt64) -> TimerDef {
        TimerDef(id: "one", title: "tea", minutes: minutes)
    }

    private func repeating(minutes: UInt64) -> TimerDef {
        TimerDef(id: "rep", title: "stretch", minutes: minutes, repeating: true)
    }

    @Test func oneShotFiresOnceAfterDeadline() {
        let engine = TimerEngine(timers: [oneShot(minutes: 5)], now: t0)
        #expect(!engine.isActive("one"))
        #expect(engine.toggle("one", now: t0) == true)
        #expect(engine.due(now: t0.addingTimeInterval(299)).isEmpty)
        #expect(engine.due(now: t0.addingTimeInterval(300)).count == 1)
        #expect(engine.due(now: t0.addingTimeInterval(301)).isEmpty)
        #expect(!engine.isActive("one"))
    }

    @Test func oneShotRetoggleResetsCountdown() {
        let engine = TimerEngine(timers: [oneShot(minutes: 5)], now: t0)
        #expect(engine.toggle("one", now: t0) == true)
        // Re-toggling a running one-shot restarts it rather than stopping it.
        #expect(engine.toggle("one", now: t0.addingTimeInterval(200)) == true)
        #expect(engine.due(now: t0.addingTimeInterval(300)).isEmpty)
        #expect(engine.due(now: t0.addingTimeInterval(500)).count == 1)
    }

    @Test func repeatingDefaultsOnAndReschedules() {
        let engine = TimerEngine(timers: [repeating(minutes: 10)], now: t0)
        #expect(engine.isActive("rep"))
        let fired = engine.due(now: t0.addingTimeInterval(600))
        #expect(fired.count == 1)
        // Rescheduled from fire time.
        #expect(engine.due(now: t0.addingTimeInterval(700)).isEmpty)
        #expect(engine.due(now: t0.addingTimeInterval(1200)).count == 1)
    }

    @Test func repeatingTogglesOnOff() {
        let engine = TimerEngine(timers: [repeating(minutes: 10)], now: t0)
        #expect(engine.toggle("rep", now: t0) == false)
        #expect(!engine.isActive("rep"))
        #expect(engine.due(now: t0.addingTimeInterval(6000)).isEmpty)
        #expect(engine.toggle("rep", now: t0) == true)
    }

    @Test func unknownIdIsNil() {
        let engine = TimerEngine(timers: [], now: t0)
        #expect(engine.toggle("ghost", now: t0) == nil)
    }

    @Test func addActivatesRepeatingTimersOnly() {
        let engine = TimerEngine(timers: [], now: t0)
        engine.add(oneShot(minutes: 5), now: t0)
        engine.add(repeating(minutes: 10), now: t0)
        #expect(!engine.isActive("one"))
        #expect(engine.isActive("rep"))
        #expect(engine.due(now: t0.addingTimeInterval(600)).map(\.id) == ["rep"])
    }

    @Test func updateReplacesDefinitionAndRestartsCountdown() {
        let engine = TimerEngine(timers: [oneShot(minutes: 5)], now: t0)
        _ = engine.toggle("one", now: t0)
        var edited = oneShot(minutes: 2)
        edited.title = "coffee"
        engine.update(edited, now: t0)
        // A one-shot loses its old deadline on edit.
        #expect(!engine.isActive("one"))
        #expect(engine.timers.first?.title == "coffee")

        let repeatingEngine = TimerEngine(timers: [repeating(minutes: 10)], now: t0)
        repeatingEngine.update(repeating(minutes: 1), now: t0)
        #expect(repeatingEngine.isActive("rep"))
        #expect(repeatingEngine.due(now: t0.addingTimeInterval(60)).count == 1)
    }

    @Test func removeDropsDefinitionAndDeadline() {
        let engine = TimerEngine(timers: [repeating(minutes: 10)], now: t0)
        engine.remove("rep")
        #expect(engine.timers.isEmpty)
        #expect(!engine.anyActive)
        #expect(engine.due(now: t0.addingTimeInterval(6000)).isEmpty)
    }

    @Test func formatRemainingMatchesPython() {
        #expect(TimerEngine.formatRemaining(59) == "0:59")
        #expect(TimerEngine.formatRemaining(60) == "1:00")
        #expect(TimerEngine.formatRemaining(300) == "5:00")
        #expect(TimerEngine.formatRemaining(3600) == "1:00:00")
        #expect(TimerEngine.formatRemaining(3661) == "1:01:01")
        #expect(TimerEngine.formatRemaining(0) == "0:00")
    }

    @Test func labelsMatchTheDesktopShapes() {
        let engine = TimerEngine(timers: [oneShot(minutes: 5), repeating(minutes: 10)], now: t0)
        #expect(engine.itemLabel(for: oneShot(minutes: 5), now: t0) == "tea - 5 min (stopped)")
        _ = engine.toggle("one", now: t0)
        #expect(engine.itemLabel(for: oneShot(minutes: 5), now: t0) == "tea - 5 min (running, 5:00 left)")
        #expect(
            engine.itemLabel(for: repeating(minutes: 10), now: t0)
                == "stretch - every 10 min, repeating (running, 10:00 until repeat)"
        )
    }

    @Test func alarmLabelMatchesTheDesktopShape() {
        let alarm = AlarmDef(id: "a", title: "wake", hour: 7, minute: 5, enabled: true)
        #expect(alarm.label == "wake - 07:05 (on)")
        var off = alarm
        off.enabled = false
        #expect(off.label == "wake - 07:05 (off)")
    }
}
