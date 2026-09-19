import Foundation
import Testing
@testable import Drift

struct LaunchSessionPolicyTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func shortBackgroundKeepsTheExistingSession() {
        var policy = LaunchSessionPolicy()
        #expect(policy.interval == 300)
        policy.enteredBackground(at: start)
        let startsNewSession = policy.becameActive(at: start.addingTimeInterval(299.999))
        #expect(!startsNewSession)
    }

    @Test func fiveMinuteBoundaryStartsExactlyOneNewSession() {
        var policy = LaunchSessionPolicy()
        policy.enteredBackground(at: start)
        let firstActivation = policy.becameActive(at: start.addingTimeInterval(300))
        let duplicateActivation = policy.becameActive(at: start.addingTimeInterval(301))
        #expect(firstActivation)
        #expect(!duplicateActivation)
    }

    @Test func longerBackgroundStartsANewSession() {
        var policy = LaunchSessionPolicy()
        policy.enteredBackground(at: start)
        let startsNewSession = policy.becameActive(at: start.addingTimeInterval(3_600))
        #expect(startsNewSession)
    }

    @Test func inactiveOnlyInterruptionsNeverStartTheBackgroundTimer() {
        var policy = LaunchSessionPolicy()
        let firstActivation = policy.becameActive(at: start)
        let laterActivation = policy.becameActive(at: start.addingTimeInterval(3_600))
        #expect(!firstActivation)
        #expect(!laterActivation)
    }

    @Test func repeatedBackgroundEventsDoNotPostponeTheBoundary() {
        var policy = LaunchSessionPolicy()
        policy.enteredBackground(at: start)
        policy.enteredBackground(at: start.addingTimeInterval(240))
        let startsNewSession = policy.becameActive(at: start.addingTimeInterval(300))
        #expect(startsNewSession)
    }

    @Test func eachBackgroundIntervalIsIndependent() {
        var policy = LaunchSessionPolicy()
        policy.enteredBackground(at: start)
        let firstShortReturn = policy.becameActive(at: start.addingTimeInterval(200))
        #expect(!firstShortReturn)
        policy.enteredBackground(at: start.addingTimeInterval(210))
        let secondShortReturn = policy.becameActive(at: start.addingTimeInterval(410))
        #expect(!secondShortReturn)
        policy.enteredBackground(at: start.addingTimeInterval(420))
        let longReturn = policy.becameActive(at: start.addingTimeInterval(720))
        #expect(longReturn)
        policy.enteredBackground(at: start.addingTimeInterval(730))
        let nextShortReturn = policy.becameActive(at: start.addingTimeInterval(731))
        #expect(!nextShortReturn)
    }
}
