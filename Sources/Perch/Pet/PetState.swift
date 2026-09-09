import Foundation

/// What the pet is doing. Derived entirely from real usage — nothing here is
/// random or on a timer of its own.
enum PetMood: String, Codable, CaseIterable {
    case rest       // nothing for 45 minutes
    case calm       // worked today, but not just now
    case focus      // a request in the last 6 minutes
    case burst      // a request in the last 90 seconds

    var caption: String {
        switch self {
        case .rest: "Resting"
        case .calm: "Calm"
        case .focus: "Focused"
        case .burst: "Working"
        }
    }
}

struct PetStatus: Equatable {
    var mood: PetMood = .rest
    /// Wears the hat. Three consecutive days is the smallest streak worth marking.
    var streak: Int = 0
    /// Distinct models used today; two or more adds the orbiting sparks.
    var modelsToday: Int = 0
    var tokensToday: Int = 0
    var lastActivity: Date?
    var topProjectToday: String?

    /// Three consecutive days is the smallest streak worth raising a flag for.
    var carriesFlag: Bool { streak >= 3 }
    /// Two or more models in a day earns a confetti burst.
    var hasConfetti: Bool { modelsToday >= 2 && mood != .rest }

    var caption: String {
        if mood == .rest, streak > 0 { return "Resting · \(streak)d streak" }
        if hasConfetti { return "\(mood.caption) · \(modelsToday) models" }
        return mood.caption
    }

    static func derive(from rollup: Rollup, now: Date = Date()) -> PetStatus {
        var status = PetStatus()
        status.streak = rollup.currentStreak
        status.lastActivity = rollup.lastEventAt

        let today = Calendar.current.startOfDay(for: now)
        if let day = rollup.byDay[today] {
            status.tokensToday = day.totals.total
        }

        // Distinct models seen today, and today's busiest project.
        var modelsToday = Set<String>()
        var projectToday: [String: Int] = [:]
        for project in rollup.byProject.values where project.days.contains(today) {
            projectToday[project.name, default: 0] += project.totals.total
        }
        for model in rollup.byModel.values where model.days.contains(today) {
            modelsToday.insert(model.name)
        }
        status.modelsToday = modelsToday.count
        status.topProjectToday = projectToday.max { $0.value < $1.value }?.key

        guard let last = rollup.lastEventAt else { return status }
        let idle = now.timeIntervalSince(last)
        status.mood = switch idle {
        case ..<90: .burst
        case ..<360: .focus
        case ..<2_700: .calm
        default: .rest
        }
        return status
    }
}
