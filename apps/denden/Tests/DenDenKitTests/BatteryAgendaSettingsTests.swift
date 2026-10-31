import XCTest
@testable import DenDenKit

final class BatteryTests: XCTestCase {
    func testOnBattery() throws {
        let r = try XCTUnwrap(BatteryReading.parse([
            "Type": "InternalBattery", "Is Present": true, "Current Capacity": 41, "Max Capacity": 100,
            "Power Source State": "Battery Power", "Is Charging": false, "Time to Empty": 190,
        ]))
        XCTAssertEqual(r.percent, 41)
        XCTAssertEqual(r.symbol, "battery.50percent")
        XCTAssertEqual(r.summary, "41%, 3:10 left")
        XCTAssertFalse(r.isLow)
    }

    func testCharging() throws {
        let r = try XCTUnwrap(BatteryReading.parse([
            "Type": "InternalBattery", "Current Capacity": 80, "Max Capacity": 100,
            "Power Source State": "AC Power", "Is Charging": true, "Time to Full Charge": 45,
        ]))
        XCTAssertEqual(r.symbol, "battery.100percent.bolt")
        XCTAssertEqual(r.summary, "80%, charging, full in 0:45")
    }

    func testChargedAndLow() throws {
        let full = try XCTUnwrap(BatteryReading.parse(["Current Capacity": 100, "Max Capacity": 100,
                                                       "Power Source State": "AC Power", "Is Charged": true, "Time to Empty": 0]))
        XCTAssertEqual(full.summary, "100%, charged")
        XCTAssertNil(full.minutesRemaining)
        let low = try XCTUnwrap(BatteryReading.parse(["Current Capacity": 9, "Max Capacity": 100, "Time to Empty": -1]))
        XCTAssertTrue(low.isLow)
        XCTAssertEqual(low.symbol, "battery.0percent")
        XCTAssertNil(low.minutesRemaining)
    }

    func testOtherPowerSourcesAreIgnored() {
        XCTAssertNil(BatteryReading.parse(["Type": "UPS", "Current Capacity": 50, "Max Capacity": 100]))
        XCTAssertNil(BatteryReading.parse(["Current Capacity": 50]))
        XCTAssertNil(BatteryReading.parse(["Is Present": false, "Current Capacity": 50, "Max Capacity": 100]))
    }
}

final class AgendaTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func at(_ hour: Int, _ minute: Int = 0, day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute))!
    }

    func testUpcomingEvents() {
        let now = at(11)
        let events = [
            AgendaEvent(id: "1", title: "Team sync", start: at(9), end: at(10)),
            AgendaEvent(id: "2", title: "Clinic", start: at(10, 30), end: at(12)),
            AgendaEvent(id: "3", title: "Lunch", start: at(12), end: at(13)),
            AgendaEvent(id: "4", title: "Holiday", start: at(0), end: at(0, day: 16), isAllDay: true),
            AgendaEvent(id: "5", title: "Tomorrow", start: at(9, day: 16), end: at(10, day: 16)),
        ]
        let shown = Agenda.upcoming(events, now: now, calendar: calendar)
        XCTAssertEqual(shown.map(\.title), ["Holiday", "Clinic", "Lunch"])
        XCTAssertTrue(Agenda.isCurrent(shown[1], now: now))
        XCTAssertFalse(Agenda.isCurrent(shown[0], now: now))
        XCTAssertEqual(Agenda.upcoming(events, now: now, calendar: calendar, limit: 2).count, 2)
    }

    func testRemindersDueToday() {
        let now = at(11)
        let items = [
            AgendaReminder(id: "a", title: "Send report", due: at(17)),
            AgendaReminder(id: "b", title: "Overdue", due: at(9, day: 14)),
            AgendaReminder(id: "c", title: "Any time today", dueDay: at(0), priority: 1),
            AgendaReminder(id: "d", title: "Tomorrow", due: at(9, day: 16)),
            AgendaReminder(id: "e", title: "Done", due: at(8), isCompleted: true),
            AgendaReminder(id: "f", title: "No date"),
        ]
        let due = Agenda.dueToday(items, now: now, calendar: calendar)
        XCTAssertEqual(due.map(\.id), ["b", "c", "a"])
    }

    func testTimeLabels() {
        let e = AgendaEvent(id: "1", title: "x", start: at(9, 5), end: at(10))
        XCTAssertEqual(Agenda.timeLabel(e, calendar: calendar, locale: Locale(identifier: "en_GB")), "09:05")
        var allDay = e
        allDay.isAllDay = true
        XCTAssertEqual(Agenda.timeLabel(allDay, calendar: calendar), "All day")
    }
}

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let (s, issues) = DenDenSettings.parse("")
        XCTAssertEqual(s, DenDenSettings())
        XCTAssertEqual(issues, [])
        XCTAssertEqual(s.externalDisplays, .none)
        XCTAssertEqual(s.builtin, DenDenSettings.builtinWidgets)
        XCTAssertTrue(s.launchAtLogin)
    }

    func testEveryKey() {
        let (s, issues) = DenDenSettings.parse("""
        external_displays = "pill"
        open_on = "click"
        hover_delay = 0.3
        close_delay = 1
        live_activity = false
        launch_at_login = false
        builtin = ["today", "battery", "today"]
        """)
        XCTAssertEqual(issues, [])
        XCTAssertEqual(s.externalDisplays, .pill)
        XCTAssertEqual(s.openOn, .click)
        XCTAssertEqual(s.hoverDelay, 0.3)
        XCTAssertEqual(s.closeDelay, 1)
        XCTAssertFalse(s.liveActivity)
        XCTAssertFalse(s.launchAtLogin)
        XCTAssertEqual(s.builtin, ["today", "battery"])
    }

    func testProblemsAreWarningsWithDefaults() {
        let (s, issues) = DenDenSettings.parse("""
        external_displays = "everywhere"
        hover_delay = 10
        builtin = ["today", "clock"]
        mystery = 1
        """)
        XCTAssertEqual(s.externalDisplays, .none)
        XCTAssertEqual(s.hoverDelay, DenDenSettings().hoverDelay)
        XCTAssertEqual(s.builtin, ["today"])
        XCTAssertEqual(issues.count, 4)
        XCTAssertTrue(issues.allSatisfy { $0.severity == .warning })
    }

    func testBrokenFileGivesDefaults() {
        let (s, issues) = DenDenSettings.parse("open_on = \"click")
        XCTAssertEqual(s, DenDenSettings())
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.line, 1)
    }
}
