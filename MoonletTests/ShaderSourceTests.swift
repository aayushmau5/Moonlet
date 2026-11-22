import Foundation
import Testing
@testable import Moonlet

struct ShaderSourceTests {
    @Test func combinedSourceResetsLineNumbersForTheUserFile() {
        let combined = ShaderSource.combined("float4 x;", fileName: "aurora.metal")

        #expect(combined.hasPrefix(ShaderSource.header))
        #expect(combined.contains("#line 1 \"aurora.metal\"\nfloat4 x;"))
    }

    @Test func formatsCompilerErrorsWithTheirLines() {
        let log = """
        aurora.metal:3:12: error: use of undeclared identifier 'foo'
            float x = foo;
                      ^
        aurora.metal:5:1: warning: unused variable 'y'
        aurora.metal:9:4: error: expected ';' after expression
        """

        let message = ShaderSource.describeCompileLog(log)

        #expect(message == "line 3: use of undeclared identifier 'foo'; line 9: expected ';' after expression")
    }

    @Test func fallsBackToTheFirstLineWhenNoErrorMatches() {
        #expect(ShaderSource.describeCompileLog("Compiler crashed\nmore detail") == "Compiler crashed")
    }

    @Test func uniformsMatchTheMetalLayout() {
        #expect(MemoryLayout<ShaderUniforms>.offset(of: \.time) == 0)
        #expect(MemoryLayout<ShaderUniforms>.offset(of: \.resolution) == 8)
        #expect(MemoryLayout<ShaderUniforms>.stride == 16)
    }
}

struct ShaderClockTests {
    let start = ContinuousClock.now

    @Test func startsAtZero() {
        let clock = ShaderClock()
        #expect(clock.elapsed(at: start + .seconds(10)) == 0)
    }

    @Test func countsWhilePlaying() {
        var clock = ShaderClock()
        clock.resume(at: start)

        #expect(clock.elapsed(at: start + .seconds(3)) == 3)
    }

    @Test func excludesPausedTime() {
        var clock = ShaderClock()
        clock.resume(at: start)
        clock.pause(at: start + .seconds(2))
        clock.resume(at: start + .seconds(10))

        #expect(clock.elapsed(at: start + .seconds(10)) == 2)
        #expect(clock.elapsed(at: start + .seconds(11)) == 3)
    }

    @Test func repeatedPauseAndResumeAreHarmless() {
        var clock = ShaderClock()
        clock.resume(at: start)
        clock.resume(at: start + .seconds(5))
        clock.pause(at: start + .seconds(6))
        clock.pause(at: start + .seconds(9))

        #expect(clock.elapsed(at: start + .seconds(20)) == 6)
    }
}
