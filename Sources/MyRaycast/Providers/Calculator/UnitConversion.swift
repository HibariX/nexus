import Foundation

/// 单位换算：`100m to ft` / `32f to c` / `1gb to mb`
nonisolated enum UnitConversion {

    struct Conversion {
        let input: Measurement<Dimension>
        let output: Measurement<Dimension>

        var formatted: String {
            let fmt = MeasurementFormatter()
            fmt.unitOptions = .providedUnit
            fmt.numberFormatter.maximumFractionDigits = 6
            return fmt.string(from: output)
        }
    }

    private static let aliases: [String: Dimension] = {
        var map: [String: Dimension] = [:]
        func add(_ names: [String], _ unit: Dimension) {
            for n in names { map[n] = unit }
        }
        // 长度
        add(["m", "meter", "meters", "米"], UnitLength.meters)
        add(["km", "kilometer", "kilometers", "千米", "公里"], UnitLength.kilometers)
        add(["cm", "centimeter", "centimeters", "厘米"], UnitLength.centimeters)
        add(["mm", "millimeter", "millimeters", "毫米"], UnitLength.millimeters)
        add(["mi", "mile", "miles", "英里"], UnitLength.miles)
        add(["ft", "foot", "feet", "英尺"], UnitLength.feet)
        add(["in", "inch", "inches", "英寸"], UnitLength.inches)
        add(["yd", "yard", "yards", "码"], UnitLength.yards)
        add(["nmi", "海里"], UnitLength.nauticalMiles)
        // 质量
        add(["kg", "kilogram", "kilograms", "千克", "公斤"], UnitMass.kilograms)
        add(["g", "gram", "grams", "克"], UnitMass.grams)
        add(["mg", "毫克"], UnitMass.milligrams)
        add(["t", "ton", "tons", "吨"], UnitMass.metricTons)
        add(["lb", "lbs", "pound", "pounds", "磅"], UnitMass.pounds)
        add(["oz", "ounce", "ounces", "盎司"], UnitMass.ounces)
        add(["jin", "斤"], UnitMass(symbol: "斤", converter: UnitConverterLinear(coefficient: 0.5)))
        // 温度
        add(["c", "celsius", "摄氏度"], UnitTemperature.celsius)
        add(["f", "fahrenheit", "华氏度"], UnitTemperature.fahrenheit)
        add(["k", "kelvin", "开尔文"], UnitTemperature.kelvin)
        // 体积
        add(["l", "liter", "liters", "升"], UnitVolume.liters)
        add(["ml", "毫升"], UnitVolume.milliliters)
        add(["gal", "gallon", "gallons", "加仑"], UnitVolume.gallons)
        add(["cup", "cups", "杯"], UnitVolume.cups)
        // 速度
        add(["kmh", "kph", "km/h"], UnitSpeed.kilometersPerHour)
        add(["mph", "mi/h"], UnitSpeed.milesPerHour)
        add(["m/s", "ms", "mps"], UnitSpeed.metersPerSecond)
        add(["knot", "knots", "节"], UnitSpeed.knots)
        // 时长
        add(["s", "sec", "second", "seconds", "秒"], UnitDuration.seconds)
        add(["min", "minute", "minutes", "分钟"], UnitDuration.minutes)
        add(["h", "hr", "hour", "hours", "小时"], UnitDuration.hours)
        // 信息存储
        add(["b", "byte", "bytes", "字节"], UnitInformationStorage.bytes)
        add(["kb", "kilobyte", "kilobytes"], UnitInformationStorage.kilobytes)
        add(["mb", "megabyte", "megabytes"], UnitInformationStorage.megabytes)
        add(["gb", "gigabyte", "gigabytes"], UnitInformationStorage.gigabytes)
        add(["tb", "terabyte", "terabytes"], UnitInformationStorage.terabytes)
        // 面积
        add(["sqm", "m2", "平方米"], UnitArea.squareMeters)
        add(["sqkm", "km2", "平方千米", "平方公里"], UnitArea.squareKilometers)
        add(["sqft", "ft2", "平方英尺"], UnitArea.squareFeet)
        add(["acre", "acres", "英亩"], UnitArea.acres)
        add(["ha", "hectare", "公顷"], UnitArea.hectares)
        add(["mu", "亩"], UnitArea(symbol: "亩", converter: UnitConverterLinear(coefficient: 666.6667)))
        return map
    }()

    /// 解析 `100m to ft` 形式，不匹配或单位不兼容返回 nil
    static func convert(_ input: String) -> Conversion? {
        // Regex 非 Sendable，不能作 nonisolated static 存储属性，每次调用构造（成本可忽略）
        let pattern = /^(-?[\d.]+)\s*([a-zA-Z\/°²³\u{4e00}-\u{9fa5}]+)\s+(?:to|in|as|=|转|换)\s+([a-zA-Z\/°²³\u{4e00}-\u{9fa5}]+)$/
        guard let match = try? pattern.wholeMatch(in: input.trimmingCharacters(in: .whitespaces)) else { return nil }
        guard let value = Double(match.1) else { return nil }
        let fromKey = String(match.2).lowercased()
        let toKey = String(match.3).lowercased()

        guard let fromUnit = aliases[fromKey], let toUnit = aliases[toKey] else { return nil }
        // 同一量纲才可换算。注意内置单位是私有子类（_NSStatic_NSUnitMass），
        // 不能直接比较 type(of:)，需回溯到 Dimension 的直接子类
        guard baseDimensionClass(of: fromUnit) == baseDimensionClass(of: toUnit) else { return nil }

        let input = Measurement(value: value, unit: fromUnit)
        let output = input.converted(to: toUnit)
        return Conversion(input: input, output: output)
    }

    /// 沿 superclass 链回溯到 Dimension 的直接子类（UnitMass/UnitLength 等量纲基类）
    private static func baseDimensionClass(of unit: Dimension) -> AnyClass {
        var cls: AnyClass = type(of: unit)
        while let sup = class_getSuperclass(cls), sup != Dimension.self, sup != NSObject.self {
            cls = sup
        }
        return cls
    }
}
