import Foundation

/// Derives what the Live Activity shows from the session as the view model
/// holds it. Pure so the ordering rules — the part that can go wrong — are
/// unit-testable without ActivityKit.
enum WorkoutActivityStateBuilder {
    struct SetRef: Equatable {
        let logIndex: Int
        let setIndex: Int
    }

    /// Sets in gym-floor order. Straight groups go set by set. Superset-type
    /// groups go round by round — all warm-up rounds, then working rounds —
    /// pairing sets by position within the same set type, exactly as
    /// `restDuration(forExerciseLogIndex:setIndex:)` does. Logs the group
    /// map doesn't know about (a resumed session outliving its template)
    /// append as straight, in log order.
    static func orderedSets(
        session: WorkoutSession,
        groupMap: [Int: Int],
        groups: [ExerciseGroup]
    ) -> [SetRef] {
        let logs = session.exerciseLogs
        var ordered: [SetRef] = []
        let mappedGroupIndices = Set(groupMap.values).sorted()

        for groupIndex in mappedGroupIndices {
            let logIndices = groupMap
                .filter { $0.value == groupIndex && $0.key < logs.count }
                .map(\.key)
                .sorted()
            guard !logIndices.isEmpty else { continue }
            let groupType = groupIndex < groups.count ? groups[groupIndex].groupType : .straight

            if groupType == .straight || logIndices.count == 1 {
                for logIndex in logIndices {
                    for setIndex in logs[logIndex].sets.indices {
                        ordered.append(SetRef(logIndex: logIndex, setIndex: setIndex))
                    }
                }
                continue
            }

            for setType in [SetType.warmUp, SetType.working] {
                let perLog: [(logIndex: Int, setIndices: [Int])] = logIndices.map { logIndex in
                    let indices = logs[logIndex].sets.indices.filter { logs[logIndex].sets[$0].setType == setType }
                    return (logIndex, indices)
                }
                let rounds = perLog.map(\.setIndices.count).max() ?? 0
                for round in 0..<rounds {
                    for entry in perLog where round < entry.setIndices.count {
                        ordered.append(SetRef(logIndex: entry.logIndex, setIndex: entry.setIndices[round]))
                    }
                }
            }
        }

        for logIndex in logs.indices where groupMap[logIndex] == nil {
            for setIndex in logs[logIndex].sets.indices {
                ordered.append(SetRef(logIndex: logIndex, setIndex: setIndex))
            }
        }
        return ordered
    }

    static func currentAndNext(
        ordered: [SetRef],
        session: WorkoutSession,
        completedSetIds: Set<String>
    ) -> (current: SetRef?, next: SetRef?) {
        let remaining = ordered.filter { ref in
            let set = session.exerciseLogs[ref.logIndex].sets[ref.setIndex]
            return !completedSetIds.contains(set.id)
        }
        return (remaining.first, remaining.count > 1 ? remaining[1] : nil)
    }

    static func contentState(
        session: WorkoutSession,
        completedSetIds: Set<String>,
        groupMap: [Int: Int],
        groups: [ExerciseGroup],
        setInputs: [String: SetInput],
        suggestedSetInputs: [String: SetInput],
        unitSystem: UnitSystem,
        restEndDate: Date?,
        restTotalSeconds: Int?
    ) -> WorkoutActivityAttributes.ContentState {
        let ordered = orderedSets(session: session, groupMap: groupMap, groups: groups)
        let (current, next) = currentAndNext(ordered: ordered, session: session, completedSetIds: completedSetIds)
        let totalSets = session.exerciseLogs.reduce(0) { $0 + $1.sets.count }
        let completed = session.exerciseLogs.flatMap(\.sets).filter { completedSetIds.contains($0.id) }.count
        let rest: (Date?, Int?) = restEndDate.map { ($0, restTotalSeconds) } ?? (nil, nil)

        guard let current else {
            return WorkoutActivityAttributes.ContentState(
                exerciseName: "All sets done",
                setLabel: "Tap Finish in LiftIQ",
                nextUpLabel: nil,
                completedSets: completed,
                totalSets: totalSets,
                restEndDate: rest.0,
                restTotalSeconds: rest.1
            )
        }

        let log = session.exerciseLogs[current.logIndex]
        let nextLabel: String? = next.map { nextRef in
            let nextLog = session.exerciseLogs[nextRef.logIndex]
            if nextRef.logIndex == current.logIndex {
                var label = "Next: \(setName(in: nextLog, setIndex: nextRef.setIndex))"
                if let weight = weightText(setId: nextLog.sets[nextRef.setIndex].id, setInputs: setInputs, suggested: suggestedSetInputs, unitSystem: unitSystem) {
                    label += " · \(weight)"
                }
                return label
            }
            return "Next: \(nextLog.exerciseName)"
        }

        return WorkoutActivityAttributes.ContentState(
            exerciseName: log.exerciseName,
            setLabel: setLabel(
                log: log, setIndex: current.setIndex, groups: groups,
                setInputs: setInputs, suggested: suggestedSetInputs, unitSystem: unitSystem
            ),
            nextUpLabel: nextLabel,
            completedSets: completed,
            totalSets: totalSets,
            restEndDate: rest.0,
            restTotalSeconds: rest.1
        )
    }

    // MARK: - Labels

    /// "Set 2 of 3" / "Warm-up 1 of 2", counting within the set's type.
    static func setName(in log: ExerciseLog, setIndex: Int) -> String {
        let set = log.sets[setIndex]
        let sameType = log.sets.indices.filter { log.sets[$0].setType == set.setType }
        let position = (sameType.firstIndex(of: setIndex) ?? 0) + 1
        let prefix = set.setType == .warmUp ? "Warm-up" : "Set"
        return "\(prefix) \(position) of \(sameType.count)"
    }

    private static func setLabel(
        log: ExerciseLog,
        setIndex: Int,
        groups: [ExerciseGroup],
        setInputs: [String: SetInput],
        suggested: [String: SetInput],
        unitSystem: UnitSystem
    ) -> String {
        var parts = [setName(in: log, setIndex: setIndex)]
        let set = log.sets[setIndex]
        if set.setType == .working,
           let planned = groups.flatMap(\.exercises).first(where: { $0.exerciseId == log.exerciseId }) {
            parts.append(planned.repsMin == planned.repsMax ? "\(planned.repsMin) reps" : "\(planned.repsMin)-\(planned.repsMax) reps")
        } else if let reps = Int(setInputs[set.id]?.reps ?? ""), reps > 0 {
            parts.append("\(reps) reps")
        } else if let reps = Int(suggested[set.id]?.reps ?? ""), reps > 0 {
            parts.append("\(reps) reps")
        }
        if let weight = weightText(setId: set.id, setInputs: setInputs, suggested: suggested, unitSystem: unitSystem) {
            parts.append(weight)
        }
        return parts.joined(separator: " · ")
    }

    /// Typed weight first, then the ghost; both are already display units.
    private static func weightText(
        setId: String,
        setInputs: [String: SetInput],
        suggested: [String: SetInput],
        unitSystem: UnitSystem
    ) -> String? {
        let typed = Double(setInputs[setId]?.weight ?? "") ?? 0
        let ghost = Double(suggested[setId]?.weight ?? "") ?? 0
        let value = typed > 0 ? typed : ghost
        guard value > 0 else { return nil }
        return "\(value.formatted(decimals: 1)) \(UnitConversionService.weightLabel(for: unitSystem))"
    }
}
