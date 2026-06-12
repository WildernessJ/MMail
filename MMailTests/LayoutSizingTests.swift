import Testing
import Foundation
@testable import MMail

/// Unit tests for the PURE, SwiftUI-free layout-sizing seams (`SidebarSize`,
/// `clampListWidth`) plus the keyless persistence LOAD accessors
/// (`loadSidebarSize`/`loadListWidth`) over an injected `UserDefaults` suite. These
/// exercise the seam-level decisions without constructing any view or `AppModel`
/// (whose init has bootstrap side-effects). The WRITE wiring (`persistTweaks`/
/// `setListWidth` actually calling `d.set`) + the full set→relaunch→read round-trip
/// are live-verified at T018, per SC-007 — not asserted here.
///
/// Mirrors specs/resizable-columns.md scenarios:
/// - SidebarSize: medium==today, small icon-only, strict width ordering, cycle wrap,
///   rawValue round-trip + unknown→nil (SC-007).
/// - clampListWidth: in-range / below-min / above-max / exact bounds (SC-006/007).
/// - Load path via canonical `LayoutDefaultsKey` constants: defaults when unset,
///   unknown-size → .medium, clamp-on-load of out-of-range width (SC-007).
@Suite struct LayoutSizingTests {

    // MARK: - SidebarSize

    @Test func mediumIsTodaysLayout() {
        #expect(SidebarSize.medium.width == 232)
        #expect(SidebarSize.medium.showsLabels)
    }

    @Test func smallIsIconOnly() {
        #expect(SidebarSize.small.showsLabels == false)
        #expect(SidebarSize.small.width < SidebarSize.medium.width)
    }

    @Test func widthOrderingAndLabelFlags() {
        #expect(SidebarSize.small.width < SidebarSize.medium.width)
        #expect(SidebarSize.medium.width < SidebarSize.large.width)
        #expect(SidebarSize.large.showsLabels)
    }

    @Test func cycleOrderWraps() {
        #expect(SidebarSize.small.next == .medium)
        #expect(SidebarSize.medium.next == .large)
        #expect(SidebarSize.large.next == .small)
    }

    @Test func rawValueRoundTripAndUnknown() {
        for size in SidebarSize.allCases {
            #expect(SidebarSize(rawValue: size.rawValue) == size)
        }
        #expect(SidebarSize(rawValue: "huge") == nil)
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

        #expect(loadSidebarSize(d) == .medium)
        #expect(loadListWidth(d) == 380)
    }

    @Test func loadKnownSidebarSize() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        d.set("small", forKey: LayoutDefaultsKey.sidebarSize)
        #expect(loadSidebarSize(d) == .small)
    }

    @Test func loadUnknownSidebarSizeFallsBackToMedium() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        d.set("huge", forKey: LayoutDefaultsKey.sidebarSize)
        #expect(loadSidebarSize(d) == .medium)
    }

    @Test func loadClampsOutOfRangeWidth() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        d.set(9999.0, forKey: LayoutDefaultsKey.listWidth)
        #expect(loadListWidth(d) == 600)
    }

    @Test func loadInRangeWidth() {
        let suiteName = "test.resizable.\(UUID())"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }

        d.set(420.0, forKey: LayoutDefaultsKey.listWidth)
        #expect(loadListWidth(d) == 420)
    }
}
