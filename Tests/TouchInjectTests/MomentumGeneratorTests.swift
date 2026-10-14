import Testing
import CoreGraphics
@testable import TouchInject

@Suite struct MomentumGeneratorTests {
    @Test func zeroVelocityHasNoFrames() {
        #expect(MomentumGenerator().frames(initialVelocity: .zero).isEmpty)
    }

    @Test func framesDecayAndStop() {
        let g = MomentumGenerator(decayPerFrame: 0.96, stopVelocity: 20, frameRate: 60)
        let frames = g.frames(initialVelocity: CGVector(dx: 0, dy: 600))
        #expect(!frames.isEmpty)
        #expect(abs(frames[0].dy - 10) < 1e-9)                 // 600 pt/s ÷ 60 Hz
        #expect(frames[1].dy < frames[0].dy)
        #expect(frames.last!.dy * 60 > 20)                      // last emitted frame is still above stop velocity
        #expect(frames.last!.dy * 60 * 0.96 <= 20)              // the next one would not be
        #expect(frames.allSatisfy { $0.dx == 0 })
    }

    @Test func negativeDirectionIsPreserved() {
        let frames = MomentumGenerator().frames(initialVelocity: CGVector(dx: -300, dy: 0))
        #expect(frames.allSatisfy { $0.dx < 0 && $0.dy == 0 })
    }

    @Test func frameCapPreventsInfiniteSequences() {
        let g = MomentumGenerator(decayPerFrame: 1.0, stopVelocity: 20, frameRate: 60, maxFrames: 50)
        #expect(g.frames(initialVelocity: CGVector(dx: 0, dy: 600)).count == 50)
    }

    @Test func hostileParametersAreClamped() {
        let g = MomentumGenerator(decayPerFrame: 2, stopVelocity: 20, frameRate: 0)
        #expect(g.decayPerFrame == 0.999)
        #expect(g.frameRate == 60)
        let frames = g.frames(initialVelocity: CGVector(dx: 0, dy: 600))
        #expect(!frames.isEmpty)
        #expect(frames.count <= g.maxFrames)
        #expect(frames.allSatisfy { $0.dx.isFinite && $0.dy.isFinite })
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $1.dy < $0.dy })   // strictly decaying
    }
}
