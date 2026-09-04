import Carbon.HIToolbox
import Testing
@testable import Nexus

@Suite struct ExpressionParserTests {
    @Test func basicArithmetic() throws {
        #expect(try ExpressionParser.evaluate("3*8+2") == 26)
        #expect(try ExpressionParser.evaluate("2+3*4") == 14)
        #expect(try ExpressionParser.evaluate("(2+3)*4") == 20)
        #expect(try ExpressionParser.evaluate("10/4") == 2.5)
        #expect(try ExpressionParser.evaluate("10%3") == 1)
    }

    @Test func unaryMinus() throws {
        #expect(try ExpressionParser.evaluate("-5+3") == -2)
        #expect(try ExpressionParser.evaluate("2*-3") == -6)
        #expect(try ExpressionParser.evaluate("-(2+3)") == -5)
    }

    @Test func power() throws {
        #expect(try ExpressionParser.evaluate("2^10") == 1024)
        // 右结合：2^3^2 = 2^9 = 512
        #expect(try ExpressionParser.evaluate("2^3^2") == 512)
    }

    @Test func functions() throws {
        #expect(try ExpressionParser.evaluate("sqrt(16)") == 4)
        #expect(try ExpressionParser.evaluate("abs(-7)") == 7)
        #expect(try ExpressionParser.evaluate("log(100)") == 2)
        #expect(abs(try ExpressionParser.evaluate("sin(0)")) < 1e-10)
    }

    @Test func constants() throws {
        #expect(abs(try ExpressionParser.evaluate("pi") - Double.pi) < 1e-10)
        #expect(try ExpressionParser.evaluate("pi*0") == 0)
    }

    @Test func unicodeOperators() throws {
        #expect(try ExpressionParser.evaluate("6×7") == 42)
        #expect(try ExpressionParser.evaluate("10÷4") == 2.5)
    }

    @Test func invalidInputThrows() {
        #expect(throws: (any Error).self) { try ExpressionParser.evaluate("3*") }
        #expect(throws: (any Error).self) { try ExpressionParser.evaluate("(2+3") }
        #expect(throws: (any Error).self) { try ExpressionParser.evaluate("hello world") }
        #expect(throws: (any Error).self) { try ExpressionParser.evaluate("1/0") }
        #expect(throws: (any Error).self) { try ExpressionParser.evaluate("foo(3)") }
    }

    @Test func looksLikeExpression() {
        #expect(ExpressionParser.looksLikeExpression("3*8+2"))
        #expect(ExpressionParser.looksLikeExpression("(1+2)"))
        #expect(ExpressionParser.looksLikeExpression("sqrt(2)"))
        #expect(!ExpressionParser.looksLikeExpression("safari"))
        #expect(!ExpressionParser.looksLikeExpression("42"))  // 纯数字不算
    }

    @Test func formatting() {
        #expect(ExpressionParser.format(26) == "26")
        #expect(ExpressionParser.format(2.5) == "2.5")
        #expect(ExpressionParser.format(1.0 / 3.0).hasPrefix("0.33333"))
    }
}

@Suite struct UnitConversionTests {
    @Test func lengthConversion() throws {
        let c = try #require(UnitConversion.convert("100m to ft"))
        #expect(abs(c.output.value - 328.084) < 0.01)
    }

    @Test func temperature() throws {
        let c = try #require(UnitConversion.convert("32f to c"))
        #expect(abs(c.output.value - 0) < 0.001)
    }

    @Test func storage() throws {
        let c = try #require(UnitConversion.convert("1gb to mb"))
        #expect(c.output.value == 1000)
    }

    @Test func chineseUnits() throws {
        let c = try #require(UnitConversion.convert("10斤 to kg"))
        #expect(abs(c.output.value - 5) < 0.001)
    }

    @Test func incompatibleUnits() {
        #expect(UnitConversion.convert("100m to kg") == nil)
        #expect(UnitConversion.convert("hello to world") == nil)
        #expect(UnitConversion.convert("safari") == nil)
    }
}

@Suite struct FuzzyMatcherTests {
    @Test func prefixBeatsScattered() throws {
        let prefix = try #require(FuzzyMatcher.score(query: "safa", target: "Safari"))
        let scattered = try #require(FuzzyMatcher.score(query: "safa", target: "System Analyzer Fast"))
        #expect(prefix > scattered)
    }

    @Test func noMatchReturnsNil() {
        #expect(FuzzyMatcher.score(query: "xyz", target: "Safari") == nil)
    }

    @Test func caseInsensitive() {
        #expect(FuzzyMatcher.score(query: "SAFARI", target: "safari") != nil)
    }
}

@Suite struct HotkeySpecTests {
    @Test func defaultHotkeyDisplay() {
        #expect(AppSettings.defaultLauncherHotkey.display == "⌥Space")
        #expect(AppSettings.defaultSnipHotkey.display == "⌃⌘A")
        #expect(AppSettings.defaultClipboardPinHotkey.display == "F3")
    }

    @Test func hidePinsHotkeyDisplay() {
        let hotkey = HotkeySpec(keyCode: UInt32(kVK_F3), carbonModifiers: UInt32(shiftKey))
        #expect(hotkey.display == "⇧F3")
    }

    @Test func keyNameNeverCrashes() {
        // 全键码扫一遍，任何键码都不允许 trap
        for code in UInt32(0)...UInt32(127) {
            _ = HotkeySpec.keyName(code)
        }
    }
}
