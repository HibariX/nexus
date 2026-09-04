import Foundation

/// 算式解析器（Tokenizer + Pratt）。不用 NSExpression：非法输入抛 ObjC 异常会崩进程。
/// 纯逻辑，nonisolated 以便单测与后台调用。
nonisolated enum ExpressionParser {

    enum ParseError: Error {
        case invalidCharacter(Character)
        case unexpectedToken
        case unexpectedEnd
        case unknownFunction(String)
        case divisionByZero
    }

    // MARK: - Tokenizer

    private enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case plus, minus, star, slash, percent, caret
        case lparen, rparen, comma
    }

    private static func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            switch c {
            case " ", "\t": i += 1
            case "+": tokens.append(.plus); i += 1
            case "-", "−": tokens.append(.minus); i += 1
            case "*", "×": tokens.append(.star); i += 1
            case "/", "÷": tokens.append(.slash); i += 1
            case "%": tokens.append(.percent); i += 1
            case "^": tokens.append(.caret); i += 1
            case "(": tokens.append(.lparen); i += 1
            case ")": tokens.append(.rparen); i += 1
            case ",": tokens.append(.comma); i += 1
            case "0"..."9", ".":
                var num = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    num.append(chars[i]); i += 1
                }
                guard let value = Double(num) else { throw ParseError.unexpectedToken }
                tokens.append(.number(value))
            default:
                if c.isLetter {
                    var name = ""
                    while i < chars.count, chars[i].isLetter {
                        name.append(chars[i]); i += 1
                    }
                    tokens.append(.identifier(name.lowercased()))
                } else {
                    throw ParseError.invalidCharacter(c)
                }
            }
        }
        return tokens
    }

    // MARK: - Pratt 解析

    private struct Parser {
        var tokens: [Token]
        var pos = 0

        var current: Token? { pos < tokens.count ? tokens[pos] : nil }

        mutating func advance() -> Token? {
            defer { pos += 1 }
            return current
        }

        mutating func expect(_ token: Token) throws {
            guard current == token else { throw ParseError.unexpectedToken }
            pos += 1
        }

        mutating func parseExpression(minBP: Int = 0) throws -> Double {
            var lhs = try parsePrefix()

            while let op = current, let (leftBP, rightBP) = infixBindingPower(op), leftBP >= minBP {
                pos += 1
                let rhs = try parseExpression(minBP: rightBP)
                lhs = try apply(op, lhs, rhs)
            }
            return lhs
        }

        private mutating func parsePrefix() throws -> Double {
            guard let token = advance() else { throw ParseError.unexpectedEnd }
            switch token {
            case .number(let value):
                return value
            case .minus:
                return try -parseExpression(minBP: 70)  // 一元负号优先级高于乘除
            case .plus:
                return try parseExpression(minBP: 70)
            case .lparen:
                let value = try parseExpression()
                try expect(.rparen)
                return value
            case .identifier(let name):
                return try parseIdentifier(name)
            default:
                throw ParseError.unexpectedToken
            }
        }

        private mutating func parseIdentifier(_ name: String) throws -> Double {
            switch name {
            case "pi": return .pi
            case "e": return M_E
            default: break
            }
            // 函数调用
            try expect(.lparen)
            let arg = try parseExpression()
            try expect(.rparen)
            switch name {
            case "sin": return sin(arg)
            case "cos": return cos(arg)
            case "tan": return tan(arg)
            case "sqrt": return sqrt(arg)
            case "log": return log10(arg)
            case "ln": return log(arg)
            case "abs": return abs(arg)
            case "round": return (arg).rounded()
            case "floor": return floor(arg)
            case "ceil": return ceil(arg)
            default: throw ParseError.unknownFunction(name)
            }
        }

        private func infixBindingPower(_ token: Token) -> (Int, Int)? {
            switch token {
            case .plus, .minus: return (10, 11)
            case .star, .slash, .percent: return (20, 21)
            case .caret: return (31, 30)  // 右结合
            default: return nil
            }
        }

        private func apply(_ op: Token, _ lhs: Double, _ rhs: Double) throws -> Double {
            switch op {
            case .plus: return lhs + rhs
            case .minus: return lhs - rhs
            case .star: return lhs * rhs
            case .slash:
                guard rhs != 0 else { throw ParseError.divisionByZero }
                return lhs / rhs
            case .percent:
                guard rhs != 0 else { throw ParseError.divisionByZero }
                return lhs.truncatingRemainder(dividingBy: rhs)
            case .caret: return pow(lhs, rhs)
            default: throw ParseError.unexpectedToken
            }
        }
    }

    /// 解析并求值；输入不是合法算式时 throws
    static func evaluate(_ input: String) throws -> Double {
        let tokens = try tokenize(input)
        guard !tokens.isEmpty else { throw ParseError.unexpectedEnd }
        // 纯数字（如 "42"）不当作算式，避免搜索数字文件名时误触发
        var parser = Parser(tokens: tokens)
        let result = try parser.parseExpression()
        guard parser.pos == tokens.count else { throw ParseError.unexpectedToken }
        return result
    }

    /// 快速预判：query 看起来像算式才值得尝试解析
    static func looksLikeExpression(_ input: String) -> Bool {
        guard let first = input.first else { return false }
        guard first.isNumber || first == "(" || first == "-" || first == "." || first == "+" else {
            // 函数名开头：sin( sqrt( 等
            let lowered = input.lowercased()
            let functions = ["sin(", "cos(", "tan(", "sqrt(", "log(", "ln(", "abs(", "round(", "floor(", "ceil(", "pi", "e^"]
            return functions.contains { lowered.hasPrefix($0) }
        }
        // 纯数字串不算算式（避免干扰其他搜索）
        return input.contains { "+-*/%^()×÷−".contains($0) }
    }

    /// 结果格式化：整数不带小数点，小数最多 10 位有效数字
    static func format(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "错误" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        formatter.groupingSeparator = ""
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
