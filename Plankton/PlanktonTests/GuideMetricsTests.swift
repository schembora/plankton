//
//  GuideMetricsTests.swift
//  PlanktonTests
//
//  The guide's geometry, and the window the listings request has to cover.
//

import Foundation
import Testing

@testable import Plankton

@Suite("Guide metrics")
struct GuideMetricsTests {

    private func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 9
        components.hour = hour
        components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test("the left edge lands on a slot boundary", arguments: [0, 1, 14, 29, 30, 31, 45, 59])
    func startIsAlignedToASlot(minute: Int) {
        let start = GuideMetrics.gridStart(for: date(hour: 20, minute: minute))
        let offset = start.timeIntervalSinceReferenceDate

        #expect(offset.truncatingRemainder(dividingBy: GuideMetrics.slot) == 0)
    }

    @Test func theGridOpensAtTheHalfHourOnOrBeforeNow() {
        #expect(GuideMetrics.gridStart(for: date(hour: 20, minute: 4)) == date(hour: 20, minute: 0))
        #expect(GuideMetrics.gridStart(for: date(hour: 20, minute: 40)) == date(hour: 20, minute: 30))
    }

    /// A moment already on the boundary opens there rather than a slot back.
    @Test func aMomentOnTheSlotOpensAtIt() {
        #expect(GuideMetrics.gridStart(for: date(hour: 20, minute: 30)) == date(hour: 20, minute: 30))
    }

    /// The edge is never ahead of now and never further back than one slot, so
    /// the grid always opens on the half hour currently running.
    @Test("the edge sits within the running slot", arguments: [0, 1, 15, 29, 30, 31, 45, 59])
    func theEdgeIsWithinTheRunningSlot(minute: Int) {
        let now = date(hour: 20, minute: minute)
        let behind = now.timeIntervalSince(GuideMetrics.gridStart(for: now))

        #expect(behind >= 0)
        #expect(behind < GuideMetrics.slot)
    }

    /// The time axis lays out one label per slot at a fixed width, so the two
    /// have to multiply out to the width the layout gives the grid. They came
    /// apart when padding was applied outside the column frame, and the axis
    /// drifted 6pt per column away from the programmes under it.
    @Test func theAxisColumnsSpanTheContentWidth() {
        let slotWidth = CGFloat(GuideMetrics.slot / 60) * GuideMetrics.minuteWidth

        #expect(CGFloat(GuideMetrics.slotCount) * slotWidth == GuideMetrics.contentWidth)
    }
}
