import Foundation

/// Units the calculator converts between, each as a factor (and offset, for
/// temperatures) to its dimension's base unit.
public struct UnitDef: Sendable, Equatable {
    public enum Dimension: Sendable, Equatable {
        case length, mass, volume, temperature, time, data, speed, area, pressure, energy, angle
    }

    public let symbol: String
    public let dimension: Dimension
    public let factor: Double
    public let offset: Double

    public func toBase(_ value: Double) -> Double { value * factor + offset }
    public func fromBase(_ value: Double) -> Double { (value - offset) / factor }
}

public enum Units {
    /// Converts, or nil for units of different kinds.
    public static func convert(_ value: Double, from: UnitDef, to: UnitDef) -> Double? {
        guard from.dimension == to.dimension else { return nil }
        return to.fromBase(from.toBase(value))
    }

    public static func named(_ name: String) -> UnitDef? {
        table[name.lowercased().trimmingCharacters(in: .whitespaces)]
    }

    static let table: [String: UnitDef] = {
        var t: [String: UnitDef] = [:]
        func add(_ names: [String], _ d: UnitDef.Dimension, _ factor: Double, offset: Double = 0) {
            let def = UnitDef(symbol: names[0], dimension: d, factor: factor, offset: offset)
            for name in names { t[name.lowercased()] = def }
        }
        add(["m", "meter", "meters", "metre", "metres"], .length, 1)
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], .length, 1_000)
        add(["cm", "centimeter", "centimeters", "centimetre", "centimetres"], .length, 0.01)
        add(["mm", "millimeter", "millimeters", "millimetre", "millimetres"], .length, 0.001)
        add(["µm", "um", "micron", "microns", "micrometer", "micrometers"], .length, 1e-6)
        add(["nm", "nanometer", "nanometers"], .length, 1e-9)
        add(["mi", "mile", "miles"], .length, 1_609.344)
        add(["yd", "yard", "yards"], .length, 0.9144)
        add(["ft", "foot", "feet"], .length, 0.3048)
        add(["in", "inch", "inches", "\""], .length, 0.0254)
        add(["nmi", "nautical mile", "nautical miles"], .length, 1_852)

        add(["kg", "kilogram", "kilograms", "kilo", "kilos"], .mass, 1)
        add(["g", "gram", "grams"], .mass, 0.001)
        add(["mg", "milligram", "milligrams"], .mass, 1e-6)
        add(["µg", "ug", "mcg", "microgram", "micrograms"], .mass, 1e-9)
        add(["lb", "lbs", "pound", "pounds"], .mass, 0.45359237)
        add(["oz", "ounce", "ounces"], .mass, 0.028349523125)
        add(["st", "stone", "stones"], .mass, 6.35029318)
        add(["t", "tonne", "tonnes"], .mass, 1_000)

        add(["l", "liter", "liters", "litre", "litres"], .volume, 1)
        add(["ml", "milliliter", "milliliters", "millilitre", "millilitres", "cc"], .volume, 0.001)
        add(["µl", "ul", "microliter", "microliters", "microlitre", "microlitres"], .volume, 1e-6)
        add(["dl", "deciliter", "deciliters"], .volume, 0.1)
        add(["m3", "m³", "cubic meter", "cubic meters"], .volume, 1_000)
        add(["gal", "gallon", "gallons"], .volume, 3.785411784)
        add(["qt", "quart", "quarts"], .volume, 0.946352946)
        add(["pt", "pint", "pints"], .volume, 0.473176473)
        add(["cup", "cups"], .volume, 0.2365882365)
        add(["fl oz", "floz", "fluid ounce", "fluid ounces"], .volume, 0.0295735295625)
        add(["tbsp", "tablespoon", "tablespoons"], .volume, 0.01478676478125)
        add(["tsp", "teaspoon", "teaspoons"], .volume, 0.00492892159375)

        add(["°C", "c", "celsius", "degc"], .temperature, 1, offset: 273.15)
        add(["°F", "f", "fahrenheit", "degf"], .temperature, 5.0 / 9.0, offset: 459.67 * 5.0 / 9.0)
        add(["K", "k", "kelvin"], .temperature, 1)

        add(["ms", "millisecond", "milliseconds"], .time, 0.001)
        add(["s", "sec", "secs", "second", "seconds"], .time, 1)
        add(["min", "mins", "minute", "minutes"], .time, 60)
        add(["h", "hr", "hrs", "hour", "hours"], .time, 3_600)
        add(["d", "day", "days"], .time, 86_400)
        add(["wk", "week", "weeks"], .time, 604_800)
        add(["mo", "month", "months"], .time, 2_629_746)
        add(["yr", "year", "years"], .time, 31_556_952)

        add(["bit", "bits"], .data, 0.125)
        add(["B", "byte", "bytes"], .data, 1)
        add(["KB", "kilobyte", "kilobytes"], .data, 1e3)
        add(["MB", "megabyte", "megabytes"], .data, 1e6)
        add(["GB", "gigabyte", "gigabytes"], .data, 1e9)
        add(["TB", "terabyte", "terabytes"], .data, 1e12)
        add(["KiB"], .data, 1_024)
        add(["MiB"], .data, 1_048_576)
        add(["GiB"], .data, 1_073_741_824)
        add(["TiB"], .data, 1_099_511_627_776)

        add(["m/s", "mps"], .speed, 1)
        add(["km/h", "kph", "kmh"], .speed, 1_000.0 / 3_600.0)
        add(["mph"], .speed, 0.44704)
        add(["kn", "knot", "knots"], .speed, 1_852.0 / 3_600.0)
        add(["ft/s", "fps"], .speed, 0.3048)

        add(["m²", "m2", "sq m"], .area, 1)
        add(["km²", "km2", "sq km"], .area, 1e6)
        add(["cm²", "cm2", "sq cm"], .area, 1e-4)
        add(["mm²", "mm2", "sq mm"], .area, 1e-6)
        add(["ha", "hectare", "hectares"], .area, 1e4)
        add(["acre", "acres"], .area, 4_046.8564224)
        add(["ft²", "ft2", "sq ft"], .area, 0.09290304)
        add(["mi²", "mi2", "sq mi"], .area, 2_589_988.110336)

        add(["Pa", "pa", "pascal", "pascals"], .pressure, 1)
        add(["hPa"], .pressure, 100)
        add(["kPa"], .pressure, 1_000)
        add(["mmHg", "torr"], .pressure, 133.322387415)
        add(["bar"], .pressure, 100_000)
        add(["atm"], .pressure, 101_325)
        add(["psi"], .pressure, 6_894.757293168)

        add(["J", "joule", "joules"], .energy, 1)
        add(["kJ"], .energy, 1_000)
        add(["cal", "calorie", "calories"], .energy, 4.184)
        add(["kcal", "kilocalorie", "kilocalories"], .energy, 4_184)
        add(["Wh"], .energy, 3_600)
        add(["kWh"], .energy, 3_600_000)

        add(["rad", "radian", "radians"], .angle, 1)
        add(["°", "deg", "degree", "degrees"], .angle, .pi / 180)
        return t
    }()
}
