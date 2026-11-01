import XCTest
@testable import IcebergKit

/// The shake gesture, the drag tracker, and what each HUD shows and when.
final class DragGestureTests: XCTestCase {
    /// Points every `step` seconds, swinging `amplitude` points left and right.
    func zigzag(_ d: inout ShakeDetector, swings: Int, amplitude: Double, step: TimeInterval, start: TimeInterval = 0) -> [Bool] {
        var out: [Bool] = []
        var t = start
        for i in 0...swings {
            out.append(d.add(x: i % 2 == 0 ? 500 : 500 + amplitude, at: t))
            t += step
        }
        return out
    }

    func testAQuickShakeIsHeard() {
        var d = ShakeDetector()
        let fired = zigzag(&d, swings: 6, amplitude: 60, step: 0.06)
        XCTAssertEqual(fired.filter { $0 }.count, 1, "once per shake")
        XCTAssertEqual(fired.firstIndex(of: true), 5, "the fourth reversal completes it")
    }

    func testSlowSwingsSmallJitterAndStraightLinesAreNot() {
        var slow = ShakeDetector()
        XCTAssertFalse(zigzag(&slow, swings: 10, amplitude: 80, step: 0.4).contains(true))
        var jitter = ShakeDetector()
        XCTAssertFalse(zigzag(&jitter, swings: 20, amplitude: 10, step: 0.03).contains(true))
        var line = ShakeDetector()
        var fired = false
        for i in 0..<50 { fired = line.add(x: Double(i) * 30, at: Double(i) * 0.02) || fired }
        XCTAssertFalse(fired)
    }

    func testCooldownAndReset() {
        var d = ShakeDetector()
        XCTAssertTrue(zigzag(&d, swings: 5, amplitude: 60, step: 0.05).contains(true))
        // Straight after: held back by the cooldown.
        XCTAssertFalse(zigzag(&d, swings: 5, amplitude: 60, step: 0.05, start: 0.3).contains(true))
        // Later on, another shake is heard.
        d.reset()
        XCTAssertTrue(zigzag(&d, swings: 5, amplitude: 60, step: 0.05, start: 3).contains(true))
    }

    func testAPauseStartsOver() {
        var d = ShakeDetector()
        _ = zigzag(&d, swings: 3, amplitude: 60, step: 0.05)
        // Two reversals, then a long pause: two more do not complete a shake.
        XCTAssertFalse(zigzag(&d, swings: 2, amplitude: 60, step: 0.05, start: 5).contains(true))
    }

    // MARK: Drag tracker

    func testAFileDragIsSeenOnceThePasteboardChanges() {
        var t = DragSessionTracker()
        var reads = 0
        XCTAssertEqual(t.mouseDown(changeCount: 7), .none)
        XCTAssertEqual(t.dragged(changeCount: { 7 }, hasFiles: { reads += 1; return true }), .none)
        XCTAssertEqual(reads, 0, "the types are read only once the pasteboard changed")
        XCTAssertEqual(t.dragged(changeCount: { 8 }, hasFiles: { reads += 1; return true }), .began)
        XCTAssertTrue(t.isFileDrag)
        XCTAssertEqual(t.dragged(changeCount: { XCTFail("not read again"); return 0 }, hasFiles: { true }), .moved)
        XCTAssertEqual(t.mouseUp(), .ended)
        XCTAssertFalse(t.isFileDrag)
        XCTAssertEqual(reads, 1)
    }

    func testOtherDragsSettleOnce() {
        var t = DragSessionTracker()
        _ = t.mouseDown(changeCount: 1)
        XCTAssertEqual(t.dragged(changeCount: { 2 }, hasFiles: { false }), .none)
        XCTAssertEqual(t.phase, .other)
        XCTAssertEqual(t.dragged(changeCount: { XCTFail("settled"); return 0 }, hasFiles: { true }), .none)
        XCTAssertEqual(t.mouseUp(), .none)

        // A window being moved: the pasteboard never changes, and checking stops.
        _ = t.mouseDown(changeCount: 5)
        var count = 0
        for _ in 0..<(DragSessionTracker.maxChecks + 10) { _ = t.dragged(changeCount: { count += 1; return 5 }, hasFiles: { true }) }
        XCTAssertEqual(count, DragSessionTracker.maxChecks)
        XCTAssertEqual(t.phase, .other)
    }

    func testDraggedWithoutAPressIsIgnored() {
        var t = DragSessionTracker()
        XCTAssertEqual(t.dragged(changeCount: { 3 }, hasFiles: { true }), .none)
        XCTAssertFalse(t.isFileDrag)
    }
}

final class HUDTests: XCTestCase {
    func testVolume() {
        let v = HUDEvent.volume(level: 0.625, muted: false)
        XCTAssertEqual(v.symbol, "speaker.wave.2.fill")
        XCTAssertEqual(v.text, "63%")
        XCTAssertEqual(v.level, 0.625)
        XCTAssertEqual(HUDEvent.volume(level: 0.5, muted: true).text, "Muted")
        XCTAssertEqual(HUDEvent.volume(level: 0.5, muted: true).level, 0)
        XCTAssertEqual(HUDEvent.volume(level: 0, muted: false).symbol, "speaker.slash.fill")
        XCTAssertEqual(HUDEvent.volume(level: 0.9, muted: false).symbol, "speaker.wave.3.fill")
        XCTAssertEqual(HUDEvent.volume(level: 1.4, muted: false).level, 1, "kept in range")
    }

    func testVolumeShowsOnlyRealChanges() {
        let a = VolumeHUDPolicy.Reading(level: 0.5, muted: false)
        XCTAssertFalse(VolumeHUDPolicy.shows(previous: nil, current: a), "the first reading is not news")
        XCTAssertFalse(VolumeHUDPolicy.shows(previous: a, current: a))
        XCTAssertFalse(VolumeHUDPolicy.shows(previous: a, current: .init(level: 0.501, muted: false)))
        XCTAssertTrue(VolumeHUDPolicy.shows(previous: a, current: .init(level: 0.5625, muted: false)))
        XCTAssertTrue(VolumeHUDPolicy.shows(previous: a, current: .init(level: 0.5, muted: true)))
    }

    func testBrightness() {
        XCTAssertEqual(HUDEvent.brightness(level: 0.25).symbol, "sun.min.fill")
        XCTAssertEqual(HUDEvent.brightness(level: 0.75).text, "75%")
    }

    func testBatteryPolicy() {
        let battery = BatteryReading(percent: 50)
        let plugged = BatteryReading(percent: 50, isCharging: true, isPluggedIn: true)
        XCTAssertNil(BatteryHUDPolicy.reason(previous: nil, current: battery))
        XCTAssertNil(BatteryHUDPolicy.reason(previous: battery, current: battery))
        XCTAssertEqual(BatteryHUDPolicy.reason(previous: battery, current: plugged), .pluggedIn)
        XCTAssertEqual(BatteryHUDPolicy.reason(previous: plugged, current: battery), .unplugged)
        XCTAssertEqual(BatteryHUDPolicy.reason(previous: BatteryReading(percent: 21), current: BatteryReading(percent: 20)), .low)
        XCTAssertNil(BatteryHUDPolicy.reason(previous: BatteryReading(percent: 20), current: BatteryReading(percent: 19)), "once per crossing")
        XCTAssertEqual(BatteryHUDPolicy.reason(previous: BatteryReading(percent: 11), current: BatteryReading(percent: 10)), .critical)
        XCTAssertNil(BatteryHUDPolicy.reason(previous: BatteryReading(percent: 25, isPluggedIn: true),
                                             current: BatteryReading(percent: 15, isPluggedIn: true)))
        let e = HUDEvent.battery(plugged, reason: .pluggedIn)
        XCTAssertEqual(e.tone, .good)
        XCTAssertEqual(e.text, "50%")
        XCTAssertEqual(e.label, "Charging, 50%")
        XCTAssertEqual(HUDEvent.battery(BatteryReading(percent: 9), reason: .critical).tone, .critical)
    }

    func testHeadphones() {
        let pods = DeviceBattery(left: 80, right: 75, caseLevel: 40)
        XCTAssertEqual(pods.lowest, 75)
        XCTAssertEqual(pods.summary, "L 80%, R 75%, case 40%")
        XCTAssertEqual(DeviceBattery(single: 60).summary, "60%")
        XCTAssertFalse(DeviceBattery(left: 0, right: -1, single: 200).isKnown, "0 and out of range mean unknown")
        let e = HUDEvent.device(name: "AirPods Pro", battery: pods)
        XCTAssertEqual(e.symbol, "airpodspro")
        XCTAssertEqual(e.text, "75%")
        XCTAssertEqual(e.label, "AirPods Pro connected, L 80%, R 75%, case 40%")
        XCTAssertEqual(HUDEvent.device(name: "Studio Headphones", battery: nil).text, "On")
        XCTAssertEqual(DeviceSymbol.symbol(forName: "My AirPods Max"), "airpodsmax")
        XCTAssertEqual(DeviceSymbol.symbol(forName: "Beats Flex"), "beats.headphones")
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(DeviceSymbol.announces(connectedAt: start.addingTimeInterval(1), listeningSince: start))
        XCTAssertTrue(DeviceSymbol.announces(connectedAt: start.addingTimeInterval(10), listeningSince: start))
    }

    func testMediaKeys() {
        for key in [MediaKey.soundUp, .soundDown, .mute, .brightnessUp, .brightnessDown] {
            let down = MediaKey.decode(data1: MediaKey.data1(key, down: true))
            XCTAssertEqual(down?.key, key)
            XCTAssertEqual(down?.down, true)
            XCTAssertEqual(MediaKey.decode(data1: MediaKey.data1(key, down: false))?.down, false)
        }
        XCTAssertEqual(MediaKey.decode(data1: MediaKey.data1(.soundUp, down: true, isRepeat: true))?.isRepeat, true)
        // Play/pause (16) and a malformed state are not ours.
        XCTAssertNil(MediaKey.decode(data1: (16 << 16) | (0xA << 8)))
        XCTAssertNil(MediaKey.decode(data1: (0 << 16) | (0x3 << 8)))
        XCTAssertTrue(MediaKey.mute.isVolume)
        XCTAssertTrue(MediaKey.brightnessDown.isBrightness)
    }

    func testSteps() {
        XCTAssertEqual(LevelStep.next(0.5, up: true, fine: false), 9.0 / 16)
        XCTAssertEqual(LevelStep.next(0.5, up: false, fine: false), 7.0 / 16)
        XCTAssertEqual(LevelStep.next(0.52, up: true, fine: false), 9.0 / 16, "between steps lands on the next one")
        XCTAssertEqual(LevelStep.next(0.52, up: false, fine: false), 8.0 / 16)
        XCTAssertEqual(LevelStep.next(1, up: true, fine: false), 1)
        XCTAssertEqual(LevelStep.next(0, up: false, fine: false), 0)
        XCTAssertEqual(LevelStep.next(0.5, up: true, fine: true), 33.0 / 64)
    }

    func testHUDSettingsStartOff() {
        let d = IcebergSettings()
        XCTAssertFalse(d.anyHUD)
        XCTAssertFalse(d.hudReplaceSystem)
        let (s, issues) = IcebergSettings.parse("""
        hud_volume = true
        hud_brightness = true
        hud_battery = true
        hud_bluetooth = true
        hud_replace_system = true
        """)
        XCTAssertEqual(issues, [])
        XCTAssertTrue(s.hudVolume && s.hudBrightness && s.hudBattery && s.hudBluetooth && s.hudReplaceSystem)
        XCTAssertTrue(s.anyHUD)
    }
}
