import SwiftUI
import Testing
@testable import KGDesign

@Suite("Motion and layout")
struct MotionTests {
    @Test func reduceMotionStopsLoopsAndShortensMoves() {
        #expect(KGMotion.animation(KGMotion.rise, reduceMotion: false) != nil)
        #expect(KGMotion.animation(KGMotion.rise, reduceMotion: true) != nil)  // a short fade
        #expect(KGMotion.animation(KGMotion.Loop.livePulse.animation, reduceMotion: true, isLoop: true) == nil)
    }

    @Test func loopDurationsFromTheDesign() {
        #expect(KGMotion.Loop.livePulse.rawValue == 1.3)
        #expect(KGMotion.Loop.locationPulse.rawValue == 2.4)
        #expect(KGMotion.Loop.seeriPeek.rawValue == 2.6)
    }

    @Test func layoutValuesFromTheDesign() {
        #expect(KGSpace.screen == 16)
        #expect(KGRadius.search == 18 && KGRadius.card == 20 && KGRadius.large == 14)
        #expect(KGSize.tabItem == CGSize(width: 96, height: 54))
        #expect(KGSize.touch >= 44)
    }

    @Test func everyShadowHasALayer() {
        for shadow in KGShadow.allCases { #expect(!shadow.layers.isEmpty) }
        #expect(KGShadow.search.layers.count == 2)
    }
}
