import Foundation

/// The value of one penalty component. A missing amount is never zero.
public enum ComponentValue: Equatable, Sendable {
    case amount(cents: Int, componentID: String)
    case notApplicable(note: String)
    case notInstalled(note: String)
    case notVerified(note: String)
    case requiresInput(String)
    case courtDetermined(note: String)

    public var display: String {
        switch self {
        case .amount(let c, _): return Money.format(cents: c)
        case .notApplicable: return "Not applicable"
        case .notInstalled: return "Not installed"
        case .notVerified: return "Not verified"
        case .requiresInput(let what): return "Needs: \(what)"
        case .courtDetermined: return "Court-determined"
        }
    }

    public var isKnownForTotal: Bool {
        switch self {
        case .amount, .notApplicable: return true
        default: return false
        }
    }
}

/// Demerit points: a verified zero is different from an unknown value.
public enum PointsValue: Equatable, Sendable {
    case points(Int, componentID: String)
    case notApplicable(note: String)
    case notInstalled(note: String)
    case notVerified(note: String)

    public var display: String {
        switch self {
        case .points(let n, _): return "\(n)"
        case .notApplicable: return "Not applicable"
        case .notInstalled: return "Not installed"
        case .notVerified: return "Not verified"
        }
    }
}

public enum TotalValue: Equatable, Sendable {
    case total(cents: Int)
    case cannotVerify(missing: [String])
    case courtDetermined(String)

    public var display: String {
        switch self {
        case .total(let c): return Money.format(cents: c)
        case .cannotVerify: return "Total cannot be verified."
        case .courtDetermined: return "No fixed ticket total — court-determined"
        }
    }
}

public enum Money {
    public static func format(cents: Int) -> String {
        let dollars = cents / 100
        let rem = abs(cents % 100)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_CA")
        let d = f.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
        return "$\(d).\(String(format: "%02d", rem))"
    }
}

/// A statutory amount computed from installed text (for example a per-km/h fine on conviction).
/// Kept separate from ticket amounts; never presented as the ordinary ticket amount.
public struct StatutoryCalculation: Equatable, Sendable {
    public let componentID: String
    public let cents: Int?
    public let explanation: String
    public let provisionID: String?
}

public struct StatutoryRangeLine: Equatable, Sendable, Identifiable {
    public var id: String { componentID }
    public let componentID: String
    public let minCents: Int?
    public let maxCents: Int?
    public let applies: String
    public let provisionID: String?
    public let notes: String?
}

public struct PenaltyBreakdown: Equatable, Sendable {
    public let offenceEntryID: String
    public let setFine: ComponentValue
    public let victimFineSurcharge: ComponentValue
    public let courtCosts: ComponentValue
    public let otherCharges: ComponentValue
    public let total: TotalValue
    public let demeritPoints: PointsValue
    public let statutoryRanges: [StatutoryRangeLine]
    public let statutoryCalculations: [StatutoryCalculation]
    /// Administrative monetary penalties (by-law AMPS) are shown separately and never added to a ticket total.
    public let administrativePenalties: [ComponentValue]
    public let notes: [String]
    /// Every displayed amount/points value maps to its component record (and so to its installed source).
    public let componentSources: [String: String?]   // component_id -> provision_id
}

public struct PenaltyInputs: Equatable, Sendable {
    public var offenceDate: Date?
    public var kmhOverLimit: Int?
    public var convictionOrdinal: Int?   // 1 = first
    public var prosecutedByIndictment: Bool?

    public init(offenceDate: Date? = nil, kmhOverLimit: Int? = nil, convictionOrdinal: Int? = nil, prosecutedByIndictment: Bool? = nil) {
        self.offenceDate = offenceDate
        self.kmhOverLimit = kmhOverLimit
        self.convictionOrdinal = convictionOrdinal
        self.prosecutedByIndictment = prosecutedByIndictment
    }
}

/// Deterministic calculator over installed penalty components.
public enum PenaltyCalculator {

    struct PerUnitBracket: Decodable {
        let fromInclusive: Int
        let toExclusive: Int?
        let centsPerUnit: Int
        let label: String
    }

    struct Conditions: Decodable {
        let type: String?
        let input: String?
        let brackets: [PerUnitBracket]?
        let applies: String?
        let presentation: String?
    }

    static func conditions(_ c: PenaltyComponentRecord) -> Conditions? {
        guard let json = c.conditionsJSON, let data = json.data(using: .utf8) else { return nil }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try? d.decode(Conditions.self, from: data)
    }

    /// Selects the component record in effect on `date` using its own effective dates.
    /// If none matches (or dates are missing where required) the component is treated as not verified.
    static func effective(_ records: [PenaltyComponentRecord], on date: Date?) -> [PenaltyComponentRecord] {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return records.filter { r in
            guard r.effectiveFrom != nil || r.effectiveTo != nil else { return true }
            guard let d = date else { return false }
            if let from = r.effectiveFrom.flatMap({ f.date(from: $0) }), d < from { return false }
            if let to = r.effectiveTo.flatMap({ f.date(from: $0) }), d >= to { return false }
            return true
        }
    }

    static func value(for kind: PenaltyComponentKind, in records: [PenaltyComponentRecord], datedRecordsExist: Bool) -> ComponentValue {
        let matching = records.filter { $0.component == kind }
        guard let r = matching.first else {
            return datedRecordsExist
                ? .notVerified(note: "No version of this component is installed for the offence date.")
                : .notInstalled(note: "No record installed.")
        }
        switch r.status {
        case .verifiedExtraction:
            if let a = r.amountCents { return .amount(cents: a, componentID: r.id) }
            return .courtDetermined(note: r.notes ?? "Depends on the court's decision.")
        case .notInstalled: return .notInstalled(note: r.notes ?? "")
        case .notVerified: return .notVerified(note: r.notes ?? "")
        case .notApplicable: return .notApplicable(note: r.notes ?? "")
        }
    }

    public static func breakdown(offenceEntryID: String, components all: [PenaltyComponentRecord], inputs: PenaltyInputs) -> PenaltyBreakdown {
        let anyDated = all.contains { $0.effectiveFrom != nil || $0.effectiveTo != nil }
        let records = effective(all, on: inputs.offenceDate)
        let setFine = value(for: .setFine, in: records, datedRecordsExist: anyDated)
        let vfs = value(for: .victimFineSurcharge, in: records, datedRecordsExist: anyDated)
        let costs = value(for: .courtCosts, in: records, datedRecordsExist: anyDated)
        let otherRecs = records.filter { $0.component == .otherCharge }
        let other: ComponentValue = otherRecs.isEmpty
            ? .notApplicable(note: "No other prescribed charge is recorded for this offence in installed material.")
            : value(for: .otherCharge, in: records, datedRecordsExist: anyDated)

        var notes: [String] = []
        let lines: [(String, ComponentValue)] = [("Set fine", setFine), ("Victim fine surcharge", vfs), ("Court costs", costs), ("Other prescribed charges", other)]
        let total: TotalValue
        if case .notApplicable = setFine, case .courtDetermined = vfs {
            total = .courtDetermined("This offence has no set fine in the installed material; penalties are determined by a court within the statutory limits shown.")
        } else if case .notApplicable = setFine {
            total = .courtDetermined("No set fine applies in the installed material; any penalty is court-determined.")
        } else if lines.allSatisfy({ $0.1.isKnownForTotal }) {
            let sum = lines.reduce(0) { acc, l in
                if case .amount(let c, _) = l.1 { return acc + c }
                return acc
            }
            total = .total(cents: sum)
        } else {
            total = .cannotVerify(missing: lines.filter { !$0.1.isKnownForTotal }.map { $0.0 })
        }

        let pointsRec = records.first { $0.component == .demeritPoints }
        let points: PointsValue
        if let p = pointsRec {
            switch p.status {
            case .verifiedExtraction:
                points = p.points.map { PointsValue.points($0, componentID: p.id) } ?? PointsValue.notVerified(note: "Points value missing from record.")
            case .notApplicable: points = .notApplicable(note: p.notes ?? "")
            case .notInstalled: points = .notInstalled(note: p.notes ?? "")
            case .notVerified: points = .notVerified(note: p.notes ?? "")
            }
        } else {
            points = anyDated ? .notVerified(note: "No points record for the offence date.") : .notInstalled(note: "No points record installed.")
        }
        notes.append("Issuing a ticket does not itself establish that demerit points have been recorded; points follow a conviction under the applicable regulation.")

        var ranges: [StatutoryRangeLine] = []
        var calcs: [StatutoryCalculation] = []
        for r in records where r.component == .statutoryRange && r.status == .verifiedExtraction {
            let cond = conditions(r)
            if cond?.type == "per-unit-bracket", let brackets = cond?.brackets {
                calcs.append(perUnit(r, brackets: brackets, input: inputs.kmhOverLimit, presentation: cond?.presentation))
            } else {
                ranges.append(StatutoryRangeLine(componentID: r.id, minCents: r.rangeMinCents, maxCents: r.rangeMaxCents,
                                                 applies: cond?.applies ?? "On conviction", provisionID: r.provisionID, notes: r.notes))
            }
        }
        if !ranges.isEmpty || !calcs.isEmpty {
            notes.append("Statutory fines and ranges apply on conviction. They are not ticket amounts and are never added to a ticket total.")
        }
        let amps: [ComponentValue] = records.filter { $0.component == .administrativePenalty }.map { r in
            switch r.status {
            case .verifiedExtraction: return r.amountCents.map { ComponentValue.amount(cents: $0, componentID: r.id) } ?? ComponentValue.notVerified(note: "Amount missing.")
            case .notInstalled: return .notInstalled(note: r.notes ?? "")
            case .notVerified: return .notVerified(note: r.notes ?? "")
            case .notApplicable: return .notApplicable(note: r.notes ?? "")
            }
        }
        if !amps.isEmpty {
            notes.append("Administrative penalties are a separate municipal process and are not part of an offence ticket total.")
        }
        var sources: [String: String?] = [:]
        for r in all { sources[r.id] = r.provisionID }
        return PenaltyBreakdown(offenceEntryID: offenceEntryID, setFine: setFine, victimFineSurcharge: vfs, courtCosts: costs,
                                otherCharges: other, total: total, demeritPoints: points, statutoryRanges: ranges,
                                statutoryCalculations: calcs, administrativePenalties: amps, notes: notes, componentSources: sources)
    }

    static func perUnit(_ r: PenaltyComponentRecord, brackets: [PerUnitBracket], input: Int?, presentation: String?) -> StatutoryCalculation {
        guard let units = input else {
            return StatutoryCalculation(componentID: r.id, cents: nil, explanation: "Enter the km/h over the limit to calculate the statutory fine on conviction.", provisionID: r.provisionID)
        }
        guard units > 0 else {
            return StatutoryCalculation(componentID: r.id, cents: nil, explanation: "No amount: the value entered is not over the limit.", provisionID: r.provisionID)
        }
        for b in brackets where units >= b.fromInclusive && (b.toExclusive == nil || units < b.toExclusive!) {
            let cents = units * b.centsPerUnit
            return StatutoryCalculation(componentID: r.id, cents: cents,
                                        explanation: "\(units) × \(Money.format(cents: b.centsPerUnit)) (\(b.label)) = \(Money.format(cents: cents)). \(presentation ?? "")",
                                        provisionID: r.provisionID)
        }
        return StatutoryCalculation(componentID: r.id, cents: nil, explanation: "No installed bracket covers \(units).", provisionID: r.provisionID)
    }
}

/// Generic surcharge rule used for bracket/percentage surcharges loaded from verified data files.
/// Brackets and rounding are applied exactly as recorded. (No real surcharge schedule is installed;
/// see coverage gaps. Tests exercise this engine with clearly fictional data.)
public struct SurchargeRule: Codable, Equatable, Sendable {
    public enum Rounding: String, Codable, Sendable {
        case none, roundHalfUpToDollar = "round-half-up-dollar", truncateToDollar = "truncate-dollar"
    }
    public struct Bracket: Codable, Equatable, Sendable {
        public let fineFromCents: Int        // inclusive
        public let fineToCents: Int?         // inclusive upper bound, nil = open
        public let fixedCents: Int?
        public let percent: Double?
        public init(fineFromCents: Int, fineToCents: Int?, fixedCents: Int?, percent: Double?) {
            self.fineFromCents = fineFromCents
            self.fineToCents = fineToCents
            self.fixedCents = fixedCents
            self.percent = percent
        }
    }
    public let id: String
    public let effectiveFrom: Date
    public let effectiveTo: Date?           // exclusive
    public let brackets: [Bracket]
    public let rounding: Rounding

    public init(id: String, effectiveFrom: Date, effectiveTo: Date?, brackets: [Bracket], rounding: Rounding) {
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
        self.brackets = brackets
        self.rounding = rounding
    }

    public func applies(on date: Date) -> Bool {
        date >= effectiveFrom && (effectiveTo == nil || date < effectiveTo!)
    }

    public func surcharge(forFineCents fine: Int) -> Int? {
        guard let b = brackets.first(where: { fine >= $0.fineFromCents && ($0.fineToCents == nil || fine <= $0.fineToCents!) }) else {
            return nil
        }
        if let fixed = b.fixedCents { return fixed }
        guard let pct = b.percent else { return nil }
        let raw = Double(fine) * pct / 100.0
        switch rounding {
        case .none: return Int(raw.rounded(.toNearestOrAwayFromZero))
        case .roundHalfUpToDollar: return Int((raw / 100.0).rounded(.toNearestOrAwayFromZero)) * 100
        case .truncateToDollar: return Int((raw / 100.0).rounded(.towardZero)) * 100
        }
    }

    /// Picks the rule in effect on the given date. Returns nil (never the latest rule) if none applies.
    public static func select(_ rules: [SurchargeRule], on date: Date) -> SurchargeRule? {
        rules.first { $0.applies(on: date) }
    }
}
