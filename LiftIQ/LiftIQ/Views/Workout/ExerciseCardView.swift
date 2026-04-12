import SwiftUI

struct ExerciseCardView: View {
    @Bindable var viewModel: WorkoutExecutionViewModel
    let exerciseLogIndex: Int
    let groupColor: Color?

    @State private var showVideo = false

    private var exerciseLog: ExerciseLog {
        viewModel.session.exerciseLogs[exerciseLogIndex]
    }

    private var exerciseDetail: Exercise? {
        viewModel.exerciseDetails[exerciseLog.exerciseId]
    }

    private var previousLog: ExerciseLog? {
        viewModel.previousLogs[exerciseLog.exerciseId]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Superset color bar
            if let groupColor {
                RoundedRectangle(cornerRadius: 2)
                    .fill(groupColor)
                    .frame(width: 4)
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text(exerciseLog.exerciseName)
                        .font(.headline)
                    Spacer()
                    Button {
                        viewModel.requestSwap(exerciseLogIndex: exerciseLogIndex)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Collapsible video
                if let videoId = exerciseDetail?.youtubeVideoId, !videoId.isEmpty {
                    DisclosureGroup("Form Video", isExpanded: $showVideo) {
                        YouTubePlayerView(videoId: videoId)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // Previous session data
                if let prevLog = previousLog {
                    previousSessionLine(prevLog)
                } else {
                    Text("No previous data")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Column headers
                HStack(spacing: 8) {
                    Text("SET")
                        .frame(width: 32)
                    Text("WEIGHT")
                        .frame(width: 78)
                    Spacer().frame(width: 18)
                    Text("REPS")
                        .frame(width: 60)
                    Text("RPE")
                        .frame(width: 48)
                    Spacer()
                    Image(systemName: "checkmark")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

                // Set rows
                ForEach(Array(exerciseLog.sets.enumerated()), id: \.element.id) { setIndex, setLog in
                    let prevSet = previousLog.flatMap { log in
                        setIndex < log.sets.count ? log.sets[setIndex] : nil
                    }
                    let prevWeight: Double? = prevSet.map {
                        UnitConversionService.convertWeight($0.weightKg, to: viewModel.unitSystem)
                    }

                    SetRowView(
                        setNumber: setLog.setNumber,
                        setType: setLog.setType,
                        weightText: $viewModel.weightInputs[exerciseLogIndex][setIndex],
                        repsText: $viewModel.repsInputs[exerciseLogIndex][setIndex],
                        rpeText: $viewModel.rpeInputs[exerciseLogIndex][setIndex],
                        previousWeight: prevWeight,
                        previousReps: prevSet?.reps,
                        unitSystem: viewModel.unitSystem,
                        isCompleted: viewModel.completedSetIds.contains(setLog.id),
                        isPersonalRecord: setLog.isPersonalRecord,
                        onComplete: {
                            Task {
                                await viewModel.completeSet(
                                    exerciseLogIndex: exerciseLogIndex,
                                    setIndex: setIndex,
                                    workoutService: workoutService,
                                    progressService: progressService,
                                    userId: viewModel.session.userId
                                )
                            }
                        },
                        onUncomplete: {
                            Task {
                                await viewModel.uncompleteSet(
                                    exerciseLogIndex: exerciseLogIndex,
                                    setIndex: setIndex,
                                    workoutService: workoutService,
                                    progressService: progressService
                                )
                            }
                        },
                        onSetTypeChange: { newType in
                            viewModel.updateSetType(exerciseLogIndex: exerciseLogIndex, setIndex: setIndex, newType: newType)
                        }
                    )
                }

                // Add/Remove set buttons
                HStack {
                    Button {
                        viewModel.addSet(exerciseLogIndex: exerciseLogIndex)
                    } label: {
                        Label("Add Set", systemImage: "plus.circle")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }

                    Spacer()

                    if exerciseLog.sets.count > 1 {
                        Button {
                            viewModel.removeSet(
                                exerciseLogIndex: exerciseLogIndex,
                                setIndex: exerciseLog.sets.count - 1
                            )
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.liftCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Subviews

    @Environment(AppDependencies.self) private var dependencies

    private var workoutService: WorkoutService {
        dependencies.workoutService
    }

    private var progressService: ProgressService {
        dependencies.progressService
    }

    private func previousSessionLine(_ prevLog: ExerciseLog) -> some View {
        let workingSets = prevLog.sets.filter { $0.setType == .working && $0.weightKg > 0 }
        let descriptions = workingSets.map { set in
            let w = UnitConversionService.convertWeight(set.weightKg, to: viewModel.unitSystem)
            return "\(w.formatted()) x \(set.reps)"
        }
        return Text("Last: \(descriptions.joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
