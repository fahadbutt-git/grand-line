import Foundation

/// The `:` list: science and maths symbols with the words people search them
/// by, then every single-character emoji, named from Unicode. Ranked by use.
public enum SymbolTable {
    public struct Symbol: Sendable, Equatable {
        public let character: String
        public let name: String
        public let keywords: [String]
        public let isEmoji: Bool
    }

    /// Character, name, keywords.
    static let science: [(String, String, [String])] = [
        ("α", "alpha", []), ("β", "beta", []), ("γ", "gamma", []), ("δ", "delta", []), ("Δ", "Delta", ["change", "prism dioptre"]),
        ("ε", "epsilon", []), ("θ", "theta", ["angle"]), ("κ", "kappa", ["agreement"]), ("λ", "lambda", ["wavelength"]),
        ("μ", "mu", ["micro", "mean"]), ("µ", "micro sign", ["micro", "um"]), ("π", "pi", []), ("ρ", "rho", ["correlation"]),
        ("σ", "sigma", ["standard deviation", "sd"]), ("Σ", "Sigma", ["sum"]), ("τ", "tau", []), ("φ", "phi", []),
        ("χ", "chi", ["chi square"]), ("χ²", "chi squared", ["chi square"]), ("ψ", "psi", []), ("ω", "omega", []), ("Ω", "Omega", ["ohm"]),
        ("±", "plus minus", ["pm", "plusminus"]), ("×", "times", ["multiply"]), ("÷", "divide", []), ("≈", "approximately", ["approx"]),
        ("≠", "not equal", ["ne"]), ("≤", "less or equal", ["le", "lte"]), ("≥", "greater or equal", ["ge", "gte"]),
        ("≪", "much less", []), ("≫", "much greater", []), ("∞", "infinity", []), ("√", "square root", ["sqrt"]),
        ("∑", "summation", ["sum"]), ("∫", "integral", []), ("∂", "partial", []), ("∇", "nabla", ["gradient"]),
        ("∝", "proportional", []), ("∈", "element of", ["in"]), ("∅", "empty set", []), ("∩", "intersection", []), ("∪", "union", []),
        ("→", "right arrow", ["to", "yields"]), ("←", "left arrow", []), ("↑", "up arrow", ["increase"]), ("↓", "down arrow", ["decrease"]),
        ("↔", "left right arrow", []), ("⇌", "equilibrium", ["reversible"]), ("⇒", "implies", []), ("°", "degree", ["deg"]),
        ("℃", "degree celsius", ["celsius"]), ("℉", "degree fahrenheit", ["fahrenheit"]), ("Å", "angstrom", []),
        ("‰", "per mille", ["per thousand"]), ("†", "dagger", ["footnote", "died"]), ("‡", "double dagger", ["footnote"]),
        ("§", "section", []), ("¶", "pilcrow", ["paragraph"]), ("•", "bullet", []), ("·", "middle dot", ["dot"]),
        ("–", "en dash", ["range"]), ("—", "em dash", ["dash"]), ("…", "ellipsis", []), ("′", "prime", ["minutes", "feet"]),
        ("″", "double prime", ["seconds", "inches"]), ("²", "superscript two", ["squared"]), ("³", "superscript three", ["cubed"]),
        ("⁻¹", "inverse", ["per", "superscript minus one"]), ("¹", "superscript one", []), ("⁰", "superscript zero", []),
        ("₀", "subscript zero", []), ("₁", "subscript one", []), ("₂", "subscript two", ["co2", "o2"]), ("₃", "subscript three", []),
        ("♀", "female", []), ("♂", "male", []), ("✓", "check mark", ["tick"]), ("✗", "ballot x", ["cross"]),
        ("©", "copyright", []), ("®", "registered", []), ("™", "trade mark", ["tm"]), ("€", "euro", []), ("£", "pound", []), ("¥", "yen", []),
    ]

    static let emojiRanges: [ClosedRange<UInt32>] = [
        0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF, 0x2600...0x26FF, 0x2700...0x27BF,
    ]

    public static func symbols() -> [Symbol] {
        var list = science.map { Symbol(character: $0.0, name: $0.1, keywords: $0.2, isEmoji: false) }
        for range in emojiRanges {
            for value in range {
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation,
                      let name = scalar.properties.name else { continue }
                list.append(Symbol(character: String(Character(scalar)), name: name.lowercased(), keywords: [], isEmoji: true))
            }
        }
        return list
    }

    public static func results(_ symbols: [Symbol]) -> [LaunchResult] {
        symbols.map { symbol in
            LaunchResult(
                id: "sym:" + symbol.character,
                title: symbol.name,
                subtitle: symbol.isEmoji ? "Emoji" : "Symbol",
                icon: .glyph(symbol.character),
                section: .symbols,
                keywords: symbol.keywords,
                accessory: symbol.character,
                actions: [
                    LaunchAction("Paste", symbol: "doc.on.clipboard", .paste(symbol.character)),
                    .copy(symbol.character),
                ],
                providerID: "symbols"
            )
        }
    }

    public static func provider() -> CatalogProvider {
        let provider = CatalogProvider(id: "symbols", title: "Emoji and symbols", symbol: "character", prefix: .symbols, inGlobalSearch: false) {
            results(symbols())
        }
        return provider
    }
}
