import Testing
import Foundation
@testable import MMail

/// Unit tests for the PURE, SwiftUI-free layout-sizing seams (`RailSize`,
/// `clampSidebarWidth`, `clampListWidth`) plus the keyless persistence LOAD accessors
/// (`loadRailSize`/`loadSidebarLabels`/`loadSidebarWidth`/`loadListWidth`) over an
/// injected `UserDefaults` suite. These exercise the seam-level decisions without
/// constructing any view or `AppModel` (whose init has bootstrap side-effects). The
/// WRITE wiring (`persistTweaks`/`setSidebarWidth`/`setListWidth` actually calling
/// `d.set`) + the full set→relaunch→read round-trip are live-verified at T-D2, per
/// SC-008 — not asserted here.
///
/// Mirrors specs/resizable-columns.md scenarios:
/// - RailSize: small==today's rail, medium bigger-but-icon-only, large shows names +
///   widest, strict width/tile ordering, cycle wrap, rawValue round-trip + unknown→nil.
/// - clampSidebarWidth: 232 unchanged / below-min / above-max (SC-006).
/// - clampListWidth: in-range / below-min / above-max / exact bounds (SC-007).
/// - Load path via canonical `LayoutDefaultsKey` constants: defaults when unset,
///   unknown-size → .small, clamp-on-load of out-of-range widths (SC-008).
@Suite struct LayoutSizingTests {

    // MARK: - RailSize

    @Test func smallIsTodaysRail() {
        #expect(RailSize.small.width == 56)
        #expect(RailSize.small.tileSize == 38)
        #expect(RailSize.small.showsNames == false)
    }

    @Test func mediumIsBiggerStillIconOnly() {
        #expect(RailSize.medium.showsNames == false)
        #expect(RailSize.medium.width > RailSize.small.width)
        #expect(RailSize.medium.tileSize > RailSize.small.tileSize)
    }

    @Test func largeShowsNamesAndIsWidest() {
        #expect(RailSize.small.width < RailSize.medium.width)
        #expect(RailSize.medium.width < RailSize.large.width)
        #expect(RailSize.large.showsNames)
        #expect(RailSize.large.tileSize > RailSize.small.tileSize)
    }

    @Test func cycleOrderWraps() {
        #expect(RailSize.small.next == .medium)
        #expect(RailSize.medium.next == .large)
        #expect(RailSize.large.next == .small)
    }

    @Test func rawValueRoundTripAndUnknown() {
        for size in RailSize.allCases {
            #expect(RailSize(rawValue: size.rawValue) == size)
        }
        #expect(RailSize(rawValue: "huge") == nil)
    }

    // MARK: - clampSidebarWidth

    @Test func clampSidebarInRangeUnchanged() {
        #expect(clampSidebarWidth(232) == 232)
    }

    @Test func clampSidebarBelowMinimum() {
        #expect(clampSidebarWidth(100) < 232)
        #expect(clampSidebarWidth(100) == clampSidebarWidth(0))
    }

    @Test func clampSidebarAboveMaximum() {
        #expect(clampSidebarWidth(1000) > 232)
        #expect(clampSidebarWidth(1000) == clampSidebarWidth(5000))
    }

    // MARK: - clampListWidth

    @Test func clampInRangeUnchanged() {
        #expect(clampListWidth(380) == 380)
    }

    @Test func clampBelowMinimum() {
        #expect(clampListWidth(120) == 300)
    }

    @Test func clampAboveMaximum() {
        #expect(clampListWidth(5000) == 600)
    }

    @Test func clampExactBounds() {
        #expect(clampListWidth(300) == 300)
        #expect(clampListWidth(600) == 600)
    }

    // MARK: - Load path (injected UserDefaults, canonical keys)

    @Test func loadDefaultsWhenUnset() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        #expect(loadRailSize(d) == .small)
        #expect(loadSidebarLabels(d) == true)
        #expect(loadSidebarWidth(d) == 232)
        #expect(loadListWidth(d) == 380)
    }

    @Test func loadKnownRailSize() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        d.set("large", forKey: LayoutDefaultsKey.railSize)
        #expect(loadRailSize(d) == .large)
    }

    @Test func loadUnknownRailSizeFallsBackToSmall() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        d.set("huge", forKey: LayoutDefaultsKey.railSize)
        #expect(loadRailSize(d) == .small)
    }

    @Test func loadSidebarLabelsRoundTrip() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        d.set(false, forKey: LayoutDefaultsKey.sidebarLabels)
        #expect(loadSidebarLabels(d) == false)
    }

    @Test func loadClampsOutOfRangeSidebarWidth() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        d.set(9999.0, forKey: LayoutDefaultsKey.sidebarWidth)
        #expect(loadSidebarWidth(d) == clampSidebarWidth(9999))
    }

    @Test func loadInRangeSidebarWidth() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        d.set(300.0, forKey: LayoutDefaultsKey.sidebarWidth)
        #expect(loadSidebarWidth(d) == 300)
    }

    @Test func loadClampsOutOfRangeListWidth() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        d.set(9999.0, forKey: LayoutDefaultsKey.listWidth)
        #expect(loadListWidth(d) == 600)
    }

    @Test func loadInRangeListWidth() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        d.set(420.0, forKey: LayoutDefaultsKey.listWidth)
        #expect(loadListWidth(d) == 420)
    }
}
