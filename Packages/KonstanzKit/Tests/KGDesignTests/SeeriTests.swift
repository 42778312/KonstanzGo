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
}
