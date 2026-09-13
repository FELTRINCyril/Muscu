import Testing
@testable import MuscuEngine

@Suite
struct UnitsTests {
    @Test
    func testKilogramsRoundTripIsLossless() {
        for value in [0.0, 2.5, 20.0, 72.5, 137.25, 999.9] {
            let pounds = MassUnit.pounds.fromKilograms(value)
            #expect(abs(MassUnit.pounds.toKilograms(pounds) - value) < 1e-9)
        }
    }

    @Test
    func testKilogramsIsIdentity() {
        #expect(MassUnit.kilograms.fromKilograms(80) == 80)
        #expect(MassUnit.kilograms.toKilograms(80) == 80)
    }

    @Test
    func testKnownPoundConversion() {
        #expect(abs(MassUnit.pounds.fromKilograms(100) - 220.462) < 0.001)
    }

    @Test
    func testDefaultIncrementInPoundsIsFivePounds() {
        let incrementKg = MassUnit.pounds.defaultIncrementKilograms
        #expect(abs(MassUnit.pounds.fromKilograms(incrementKg) - 5) < 1e-9)
        #expect(MassUnit.kilograms.defaultIncrementKilograms == 2.5)
    }

    @Test
    func testLengthRoundTrip() {
        let centimeters = LengthUnit.inches.toCentimeters(40)
        #expect(abs(LengthUnit.inches.fromCentimeters(centimeters) - 40) < 1e-9)
        #expect(abs(centimeters - 101.6) < 1e-9)
    }

    @Test
    func testRoundedToIncrementNeverExceedsValue() {
        #expect(abs(Units.roundedToIncrement(83.4, increment: 2.5) - 82.5) < 1e-9)
        #expect(Units.roundedToIncrement(0, increment: 2.5) == 0)
        #expect(Units.roundedToIncrement(10, increment: 0) == 0)
    }

    @Test
    func testRoundedForDisplayHandlesNonFinite() {
        #expect(Units.roundedForDisplay(.nan) == 0)
        #expect(abs(Units.roundedForDisplay(12.34) - 12.3) < 1e-9)
    }
}
