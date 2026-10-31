import FileKit
import XCTest
@testable import BrowserKit

/// R29: the sidebar's size and sections, with every mounted drive.
final class SidebarTests: XCTestCase {
    func volume(_ name: String, root: Bool = false, network: Bool = false, removable: Bool = false, internal isInside: Bool = false) -> VolumeInfo {
        VolumeInfo(
            url: URL(fileURLWithPath: root ? "/" : "/Volumes/\(name)", isDirectory: true), name: name,
            totalBytes: 2_000_000_000_000, availableBytes: 1_620_000_000_000, freeBytes: 1_500_000_000_000,
            isRemovable: removable, isEjectable: removable || network, isNetwork: network,
            isInternal: isInside || root, isRoot: root, format: "APFS"
        )
    }

    func testFinderSizeOrLarger() {
        XCTAssertGreaterThanOrEqual(SidebarMetrics.fontSize, 14)
        XCTAssertGreaterThanOrEqual(SidebarMetrics.rowHeight, 30)
        XCTAssertEqual(SidebarMetrics.clamp(10), SidebarMetrics.minimumWidth)
        XCTAssertEqual(SidebarMetrics.clamp(5_000), SidebarMetrics.maximumWidth)
        XCTAssertEqual(SidebarMetrics.clamp(250.4), 250)
    }

    func testSectionsInOrder() {
        let input = SidebarBuilder.Input(
            home: home, places: SidebarBuilder.defaultPlaces(home: home, drives: []),
            projects: [URL(fileURLWithPath: "/Users/me/Developer/glaucoma-model")], savedSearches: ["papers to read"],
            volumes: [volume("Macintosh HD", root: true)], trash: home.appendingPathComponent(".Trash")
        )
        let groups = SidebarBuilder.build(input)
        XCTAssertEqual(groups.map(\.section), [.places, .activeProjects, .savedSearches, .locations])
        XCTAssertEqual(groups[0].items.first?.title, "Recents")
        XCTAssertEqual(groups[0].items.map(\.title), ["Recents", "AirDrop", "Applications", "Desktop", "Documents", "Downloads", "me"])
        XCTAssertEqual(groups[0].items[1].target, .airDrop)
        XCTAssertNil(groups[0].items[1].folder, "AirDrop is not a folder to copy into")
        XCTAssertEqual(groups[2].items.first?.target, .savedSearch("papers to read"))
        XCTAssertTrue(groups.allSatisfy { group in group.items.allSatisfy { !$0.symbol.isEmpty } })
    }

    func testEmptySectionsAreLeftOutButLocationsAlwaysShow() {
        let groups = SidebarBuilder.build(SidebarBuilder.Input(home: home, places: [], trash: home.appendingPathComponent(".Trash")))
        XCTAssertEqual(groups.map(\.section), [.places, .locations])
        XCTAssertEqual(groups[1].items.map(\.title), ["Trash"])
    }

    func testEveryMountedVolumeShowsWithFreeSpaceAndEject() {
        let volumes = [
            volume("NAS", network: true), volume("Backup", removable: true),
            volume("Macintosh HD", root: true), volume("Data", internal: true),
        ]
        let input = SidebarBuilder.Input(home: home, places: [], volumes: volumes, trash: home.appendingPathComponent(".Trash"))
        let locations = SidebarBuilder.build(input).last!.items
        XCTAssertEqual(locations.map(\.title), ["Macintosh HD", "Data", "Backup", "NAS", "Trash"])
        XCTAssertEqual(locations[0].detail, ItemFormat.free(1_620_000_000_000))
        XCTAssertNil(locations[0].ejectable, "the startup disk cannot be ejected")
        XCTAssertEqual(locations[2].ejectable?.path, "/Volumes/Backup")
        XCTAssertEqual(locations[3].ejectable?.path, "/Volumes/NAS")
        XCTAssertEqual(locations[3].symbol, "server.rack")
        XCTAssertEqual(locations[2].symbol, "externaldrive")
    }

    func testGoogleDriveAppearsInPlacesAndLocations() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        try temp.folder("Library/CloudStorage/GoogleDrive-smith@example.com/My Drive")
        let drives = GoogleDrive.accounts(home: temp.root)
        XCTAssertEqual(drives.count, 1)
        let input = SidebarBuilder.Input(
            home: temp.root, places: SidebarBuilder.defaultPlaces(home: temp.root, drives: drives),
            drives: drives, trash: temp.url(".Trash")
        )
        let groups = SidebarBuilder.build(input)
        XCTAssertTrue(groups[0].items.contains { $0.title == "Drive" })
        XCTAssertTrue(groups.last!.items.contains { $0.title == "Google Drive" })
    }

    func testDownloadsBadge() {
        let input = SidebarBuilder.Input(
            home: home, places: [home.appendingPathComponent("Downloads")], trash: home.appendingPathComponent(".Trash"), newDownloads: 4
        )
        XCTAssertEqual(SidebarBuilder.build(input)[0].items[2].badge, "4 new")
    }

    func testAddToSidebarAppendsToPlacesOnce() {
        let defaults = SidebarBuilder.defaultPlaces(home: home, drives: [])
        let added = LogPoseSettings().addingPlace(home.appendingPathComponent("Developer"), current: defaults, home: home)
        XCTAssertEqual(added.places, ["/Applications", "~/Desktop", "~/Documents", "~/Downloads", "~", "~/Developer"])
        let again = added.addingPlace(home.appendingPathComponent("Developer"), current: added.placeURLs(home: home) ?? [], home: home)
        XCTAssertEqual(again, added, "a folder already there is not added twice")
    }

    func testRemoveFromSidebarRemovesPlacesAndHidesBuiltIns() {
        let input = SidebarBuilder.Input(
            home: home, places: SidebarBuilder.defaultPlaces(home: home, drives: []), savedSearches: ["papers to read"],
            volumes: [volume("Macintosh HD", root: true)], trash: home.appendingPathComponent(".Trash")
        )
        let groups = SidebarBuilder.build(input)
        let desktop = groups[0].items.first { $0.title == "Desktop" }!
        XCTAssertEqual(desktop.removal, .remove)
        XCTAssertEqual(groups[1].items[0].removal, .hide, "a saved search is hidden, so @name keeps working in Byakugan")
        XCTAssertEqual(groups[0].items[0].removal, .hide, "Recents is built in, so it is hidden")
        XCTAssertEqual(groups.last!.items[0].removal, .hide)

        let removed = LogPoseSettings().removingPlace(desktop.folder!, current: input.places, home: home)
        XCTAssertEqual(removed.places, ["/Applications", "~/Documents", "~/Downloads", "~"])

        var hidden = SidebarHidden()
        hidden.hide(groups[0].items[0])
        hidden.hide(.savedSearches)
        var hiding = input
        hiding.hidden = hidden
        let shown = SidebarBuilder.build(hiding)
        XCTAssertEqual(shown.map(\.section), [.places, .locations])
        XCTAssertFalse(shown[0].items.contains { $0.title == "Recents" })
        XCTAssertEqual(try JSONDecoder().decode(SidebarHidden.self, from: JSONEncoder().encode(hidden)), hidden)
    }

    func testActiveProjectsFromSettings() {
        let settings = LogPoseSettings(projectFolders: ["~/Drive/Projects/Active"], projects: ["~/Developer/cornea-app"])
        let children: (URL) -> [String] = { _ in ["Glaucoma review", ".hidden", "Cornea model"] }
        let projects = settings.projectURLs(home: home, children: children)
        XCTAssertEqual(projects.map(\.lastPathComponent), ["cornea-app", "Cornea model", "Glaucoma review"])
        XCTAssertNil(LogPoseSettings().placeURLs(home: home))
        XCTAssertEqual(LogPoseSettings(places: ["~/Downloads"]).placeURLs(home: home)?.first?.path, "/Users/me/Downloads")
    }
}
