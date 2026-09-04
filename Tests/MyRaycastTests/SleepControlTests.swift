import Foundation
import Testing
@testable import MyRaycast

@Suite("禁止休眠 SleepControl")
struct SleepControlTests {

    private let disabledOutput = """
    System-wide power settings:
     SleepDisabled\t\t1
    Currently in use:
     standby              1
     Sleep On Power Button 1
     sleep                0 (sleep prevented by coreaudiod, coreaudiod, bluetoothd, caffeinate)
     displaysleep         0
    """

    private let enabledOutput = """
    System-wide power settings:
     SleepDisabled\t\t0
    Currently in use:
     sleep                5
     displaysleep         10
    """

    @Test("SleepDisabled=1 解析为已禁止")
    func parsesDisabledOn() {
        #expect(SleepControl.parse(disabledOutput).sleepDisabled == true)
    }

    @Test("SleepDisabled=0 解析为未禁止")
    func parsesDisabledOff() {
        #expect(SleepControl.parse(enabledOutput).sleepDisabled == false)
    }

    @Test("容忍多空格/制表符/段头/字段缺失")
    func toleratesOddWhitespaceAndSectionHeaders() {
        let status = SleepControl.parse(" System-wide power settings:\n  SleepDisabled   1\nCurrently in use:\n")
        #expect(status.sleepDisabled == true)
        #expect(status.automaticSleepMinutes == nil)
        #expect(status.displaySleepMinutes == nil)
    }

    @Test("sleep 行带括号注释仍能取到数字")
    func parsesSleepTimerWithParenthetical() {
        let status = SleepControl.parse(disabledOutput)
        #expect(status.automaticSleepMinutes == 0)
        #expect(status.displaySleepMinutes == 0)
    }

    @Test("无 SleepDisabled 键时默认未禁止")
    func defaultsWhenKeyMissing() {
        let status = SleepControl.parse("Currently in use:\n sleep 3\n")
        #expect(status.sleepDisabled == false)
        #expect(status.automaticSleepMinutes == 3)
    }

    @Test("subtitle 反映开关")
    func subtitleReflectsState() {
        #expect(SleepControl.subtitle(for: .init(sleepDisabled: true, automaticSleepMinutes: 0, displaySleepMinutes: 0)).contains("已禁止"))
        #expect(SleepControl.subtitle(for: .init(sleepDisabled: false, automaticSleepMinutes: nil, displaySleepMinutes: nil)).contains("未禁止"))
    }
}
