import Testing
@testable import KGDesign

@Suite("iOS version look")
struct CompatTests {
    @Test func legacyLookNeverUsesGlass() {
        #expect(KGCompat.usesGlass(legacyLook: true) == false)
    }

    @Test func newSystemsUseGlassUnlessForced() {
        if #available(iOS 26, macOS 26, *) {
            #expect(KGCompat.usesGlass(legacyLook: false))
        } else {
            #expect(KGCompat.usesGlass(legacyLook: false) == false)
        }
    }
}
