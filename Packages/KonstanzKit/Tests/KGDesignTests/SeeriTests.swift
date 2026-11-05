import Foundation
import Testing
@testable import KGDesign

@Suite("Seeri")
struct SeeriTests {
    @Test func blinksBrieflyOncePerCycle() {
        #expect(SeeriAlive.blink(at: 0) == 0)
        #expect(SeeriAlive.blink(at: SeeriAlive.blinkLength / 2) == 1)
        #expect(SeeriAlive.blink(at: SeeriAlive.blinkLength) == 0)
        #expect(SeeriAlive.blink(at: 2) == 0)
        #expect(abs(SeeriAlive.blink(at: SeeriAlive.blinkCycle + SeeriAlive.blinkLength / 2) - 1) < 1e-6)
        // Closed for only a small part of the cycle.
        let samples = stride(from: 0.0, to: SeeriAlive.blinkCycle, by: 0.01).map(SeeriAlive.blink)
        #expect(Double(samples.filter { $0 > 0 }.count) / Double(samples.count) < 0.05)
    }

    @Test func aHatMakesRoomAbove() {
        #expect(Seeri(.happy).viewBox.height == 170)
        #expect(Seeri(.spooky, hat: .witch).viewBox.minY == -40)
    }

    @Test func everyExpressionFromTheDesign() {
        #expect(Seeri.Expression.allCases.count == 8)
    }

    @Test func theSirenAlternatesRedAndBlue() {
        #expect(SeeriSiren.isRed(at: 0.1))
        #expect(!SeeriSiren.isRed(at: 0.5))
        #expect(SeeriSiren.isRed(at: 0.8))
    }

    @Test func onlyWakesForBlinks() {
        let start = Date(timeIntervalSinceReferenceDate: 4.2 * 100)
        // During a blink: frames.
        #expect(BlinkSchedule.next(after: start).timeIntervalSince(start) < 0.1)
        // Between blinks: straight to the next one.
        let later = start.addingTimeInterval(1)
        #expect(abs(BlinkSchedule.next(after: later).timeIntervalSince(later) - 3.2) < 0.001)
        let frames = Array(BlinkSchedule(isPaused: false).entries(from: start, mode: .normal).prefix(40))
        #expect(frames.count == 40)
        let cycles = (frames.last?.timeIntervalSince(start) ?? 0) / SeeriAlive.blinkCycle
        #expect(cycles > 3, "too many frames per blink")
    }
}
