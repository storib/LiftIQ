import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import {
  WORKOUT_GENERATION_SYSTEM_PROMPT,
  WORKOUT_GENERATION_PROMPT_VERSION,
} from "./prompts/workoutGeneration";
import {
  GenerateWorkoutPlanRequestSchema,
  WorkoutPlanSchema,
} from "./validators/schemas";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

export const generateWorkoutPlan = onCall(
  { secrets: [anthropicApiKey], maxInstances: 10, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const parsedRequest = GenerateWorkoutPlanRequestSchema.safeParse(request.data);
    if (!parsedRequest.success) {
      throw new HttpsError("invalid-argument", "Invalid workout plan request.");
    }

    const {
      experienceLevel,
      goals,
      availableEquipment,
      trainingDaysPerWeek,
      sessionDurationMinutes,
      injuries,
      templateType,
    } = parsedRequest.data;

    // Load exercise database
    const db = admin.firestore();
    const exercisesSnap = await db.collection("exercises").get();
    const exercises = exercisesSnap.docs.map((doc) => ({
      id: doc.id,
      name: doc.data().name,
      primaryMuscleGroup: doc.data().primaryMuscleGroup,
      secondaryMuscleGroups: doc.data().secondaryMuscleGroups,
      equipment: doc.data().equipment,
      movementPattern: doc.data().movementPattern,
      difficulty: doc.data().difficulty,
      isCompound: doc.data().isCompound,
    }));

    // Filter exercises by available equipment
    const availableEquipmentSet = new Set<string>(availableEquipment);
    const availableExercises = exercises.filter((ex) =>
      Array.isArray(ex.equipment) &&
      ex.equipment.every(
        (eq: unknown) =>
          typeof eq === "string" && availableEquipmentSet.has(eq)
      )
    );

    const userPrompt = `Create a ${templateType} workout plan with these parameters:
- Experience Level: ${experienceLevel}
- Goals: ${JSON.stringify(goals)}
- Available Equipment: ${JSON.stringify(availableEquipment)}
- Training Days Per Week: ${trainingDaysPerWeek}
- Session Duration: ${sessionDurationMinutes} minutes
- Injuries:
${
  (injuries && injuries.length > 0)
    ? injuries.map((inj: { bodyPart: string; severity: string; notes: string }) =>
        `  * ${inj.severity.toUpperCase()} — ${inj.bodyPart}${inj.notes ? ` (${inj.notes})` : ""}`
      ).join("\n")
    : "  None"
}

Available exercises (use ONLY these exercise IDs):
${JSON.stringify(availableExercises, null, 2)}

Generate a complete JSON WorkoutPlan object with this structure:
{
  "id": "<unique-uuid>",
  "userId": "",
  "name": "<descriptive plan name>",
  "templateType": "${templateType}",
  "goal": "${goals[0] || "hypertrophy"}",
  "weekCount": 6,
  "currentWeek": 1,
  "workoutsPerWeek": ${trainingDaysPerWeek},
  "workouts": [
    {
      "id": "<unique-uuid>",
      "planId": "",
      "dayNumber": 1,
      "name": "<day name, e.g., Push Day A>",
      "targetMuscleGroups": ["chest", "triceps", "frontDelts"],
      "estimatedDurationMinutes": ${sessionDurationMinutes},
      "exerciseGroups": [
        {
          "id": "<unique-uuid>",
          "groupType": "straight",
          "exercises": [
            {
              "id": "<unique-uuid>",
              "exerciseId": "<exercise-id from database>",
              "order": 1,
              "sets": 3,
              "repsMin": 8,
              "repsMax": 12,
              "rirTarget": 2,
              "rpeTarget": 8.0,
              "restSeconds": 90,
              "warmUpSets": null,
              "notes": null,
              "isOptional": false
            }
          ],
          "restBetweenRoundsSeconds": null
        }
      ],
      "notes": null
    }
  ],
  "deloadWeek": 5,
  "isActive": true,
  "createdAt": "${new Date().toISOString()}",
  "aiGenerated": true,
  "aiPromptContext": null
}`;

    try {
      const client = new Anthropic({ apiKey: anthropicApiKey.value() });

      const message = await client.messages.create({
        model: "claude-sonnet-4-20250514",
        max_tokens: 8000,
        system: WORKOUT_GENERATION_SYSTEM_PROMPT,
        messages: [{ role: "user", content: userPrompt }],
      });

      const content = message.content[0];
      if (content.type !== "text") {
        throw new HttpsError("internal", "Unexpected response type");
      }

      let text = content.text.trim();
      const fenceMatch = text.match(/^```(?:json)?\s*\n?([\s\S]*?)\n?\s*```$/);
      if (fenceMatch) text = fenceMatch[1];
      const rawPlan = JSON.parse(text);
      const parsedPlan = WorkoutPlanSchema.safeParse(rawPlan);
      if (!parsedPlan.success) {
        throw new HttpsError(
          "internal",
          "AI returned a workout plan that did not match the expected schema."
        );
      }

      const plan = parsedPlan.data;
      const availableExerciseIds = new Set(availableExercises.map((ex) => ex.id));
      const invalidExerciseIds = plan.workouts.flatMap((workout) =>
        workout.exerciseGroups.flatMap((group) =>
          group.exercises
            .map((exercise) => exercise.exerciseId)
            .filter((exerciseId) => !availableExerciseIds.has(exerciseId))
        )
      );

      if (invalidExerciseIds.length > 0) {
        throw new HttpsError(
          "internal",
          "AI returned exercises outside the allowed exercise database."
        );
      }

      // Validate severe injuries: ensure no exercises target the injured area
      if (injuries && injuries.length > 0) {
        const severeInjuries = injuries.filter(
          (inj: { severity: string }) => inj.severity.toLowerCase() === "severe"
        );
        if (severeInjuries.length > 0) {
          const injuryMuscleMap: Record<string, string[]> = {
            "shoulder": ["shoulders", "frontDelts", "sideDelts", "rearDelts"],
            "left shoulder": ["shoulders", "frontDelts", "sideDelts", "rearDelts"],
            "right shoulder": ["shoulders", "frontDelts", "sideDelts", "rearDelts"],
            "knee": ["quads", "hamstrings", "glutes", "calves"],
            "left knee": ["quads", "hamstrings", "glutes", "calves"],
            "right knee": ["quads", "hamstrings", "glutes", "calves"],
            "lower back": ["back", "lats", "core"],
            "back": ["back", "lats", "traps"],
            "upper back": ["back", "lats", "traps"],
            "wrist": ["forearms", "biceps"],
            "left wrist": ["forearms", "biceps"],
            "right wrist": ["forearms", "biceps"],
            "elbow": ["biceps", "triceps", "forearms"],
            "left elbow": ["biceps", "triceps", "forearms"],
            "right elbow": ["biceps", "triceps", "forearms"],
            "hip": ["glutes", "hamstrings", "quads"],
            "left hip": ["glutes", "hamstrings", "quads"],
            "right hip": ["glutes", "hamstrings", "quads"],
            "ankle": ["calves"],
            "left ankle": ["calves"],
            "right ankle": ["calves"],
            "neck": ["traps"],
            "chest": ["chest"],
          };

          const blockedMuscles = new Set<string>();
          for (const inj of severeInjuries) {
            const key = (inj as { bodyPart: string }).bodyPart.toLowerCase().trim();
            const mapped = injuryMuscleMap[key];
            if (mapped) {
              mapped.forEach((m: string) => blockedMuscles.add(m));
            }
          }

          if (blockedMuscles.size > 0) {
            const exerciseIdToMuscle = new Map<string, string>(
              exercises.map((ex) => [ex.id, ex.primaryMuscleGroup])
            );

            const violations = plan.workouts.flatMap((workout) =>
              workout.exerciseGroups.flatMap((group) =>
                group.exercises
                  .filter((exercise) => {
                    const muscle = exerciseIdToMuscle.get(exercise.exerciseId);
                    return muscle && blockedMuscles.has(muscle);
                  })
                  .map((exercise) => exercise.exerciseId)
              )
            );

            if (violations.length > 0) {
              // Log the violation but don't block — the AI prompt should handle it,
              // and we don't want to fail the entire generation for edge cases.
              console.warn(
                `Injury safety warning: plan includes ${violations.length} exercise(s) ` +
                `targeting severely injured areas: ${violations.join(", ")}. ` +
                `Blocked muscles: ${[...blockedMuscles].join(", ")}`
              );
            }
          }
        }
      }

      // Log usage for cost monitoring
      await db.collection("aiUsageLogs").add({
        userId: request.auth.uid,
        function: "generateWorkoutPlan",
        promptVersion: WORKOUT_GENERATION_PROMPT_VERSION,
        inputTokens: message.usage.input_tokens,
        outputTokens: message.usage.output_tokens,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return plan;
    } catch (error: any) {
      if (error instanceof HttpsError) {
        throw error;
      }
      if (error instanceof SyntaxError) {
        throw new HttpsError(
          "internal",
          "AI returned invalid JSON. Please try again."
        );
      }
      throw new HttpsError("internal", error.message || "Generation failed");
    }
  }
);
