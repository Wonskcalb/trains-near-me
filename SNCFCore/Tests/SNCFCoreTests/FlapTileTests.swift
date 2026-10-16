import Testing
@testable import SNCFCore

/// The drum a split-flap tile turns through: forward only, ending on the target, like a real board.
@Suite struct FlapDrum {
    @Test func aMinuteTickIsOneStep() {
        #expect(FlapTile.path(from: "1", to: "2") == ["2"])
    }

    @Test func goingBackwardTurnsForwardThroughTheBlank() {
        #expect(FlapTile.path(from: "4", to: "2") == Array("56789-012"))
    }

    @Test func toTheBlankAndBack() {
        #expect(FlapTile.path(from: "9", to: "-") == ["-"])
        #expect(FlapTile.path(from: "-", to: "3") == Array("0123"))
    }

    @Test func sameCharacterIsNoTurn() {
        #expect(FlapTile.path(from: "7", to: "7").isEmpty)
    }

    @Test func aCharacterOffTheDrumSwapsInOneStep() {
        #expect(FlapTile.path(from: "7", to: "A") == ["A"])
    }
}
