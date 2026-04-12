import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { describe, it, beforeAll, afterAll, beforeEach } from "vitest";
import * as fs from "fs";
import * as path from "path";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  const rulesPath = path.resolve(__dirname, "../../firestore.rules");
  testEnv = await initializeTestEnvironment({
    projectId: "liftiq-rules-test",
    firestore: {
      rules: fs.readFileSync(rulesPath, "utf8"),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// ── Helpers ──

function authedDb(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

function unauthDb() {
  return testEnv.unauthenticatedContext().firestore();
}

const USER_A = "user-a";
const USER_B = "user-b";

const validUserDoc = {
  id: USER_A,
  email: "a@test.com",
  displayName: "User A",
  profile: { experienceLevel: "beginner", goals: [], availableEquipment: [] },
  createdAt: new Date(),
  updatedAt: new Date(),
};

// ══════════════════════════════════════════
// User document rules
// ══════════════════════════════════════════

describe("users/{userId}", () => {
  it("allows owner to create their own user doc with valid fields", async () => {
    const db = authedDb(USER_A);
    await assertSucceeds(db.collection("users").doc(USER_A).set(validUserDoc));
  });

  it("denies creating a user doc with mismatched id", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .set({ ...validUserDoc, id: "wrong-id" })
    );
  });

  it("denies creating a user doc with empty displayName", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .set({ ...validUserDoc, displayName: "" })
    );
  });

  it("denies creating a user doc with extra fields", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .set({ ...validUserDoc, secretField: "hack" })
    );
  });

  it("denies another user from reading someone else's doc", async () => {
    // Seed user A's doc via admin
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc(USER_A).set(validUserDoc);
    });
    const db = authedDb(USER_B);
    await assertFails(db.collection("users").doc(USER_A).get());
  });

  it("denies unauthenticated access", async () => {
    const db = unauthDb();
    await assertFails(db.collection("users").doc(USER_A).get());
  });

  it("denies update that changes email", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc(USER_A).set(validUserDoc);
    });
    const db = authedDb(USER_A);
    await assertFails(
      db.collection("users").doc(USER_A).update({ email: "hacked@test.com" })
    );
  });

  it("denies update with empty displayName", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc(USER_A).set(validUserDoc);
    });
    const db = authedDb(USER_A);
    await assertFails(
      db.collection("users").doc(USER_A).update({ displayName: "" })
    );
  });

  it("allows owner to delete their own doc", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc(USER_A).set(validUserDoc);
    });
    const db = authedDb(USER_A);
    await assertSucceeds(db.collection("users").doc(USER_A).delete());
  });
});

// ══════════════════════════════════════════
// Personal Records rules
// ══════════════════════════════════════════

describe("users/{userId}/personalRecords/{prId}", () => {
  const validPR = {
    id: "pr-1",
    userId: USER_A,
    exerciseId: "bench-press",
    exerciseName: "Bench Press",
    type: "weight",
    value: 100,
    previousValue: 95,
    achievedAt: new Date(),
    sessionId: "session-1",
  };

  it("allows owner to create a valid PR", async () => {
    const db = authedDb(USER_A);
    await assertSucceeds(
      db
        .collection("users")
        .doc(USER_A)
        .collection("personalRecords")
        .doc("pr-1")
        .set(validPR)
    );
  });

  it("denies PR with invalid type", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .collection("personalRecords")
        .doc("pr-2")
        .set({ ...validPR, id: "pr-2", type: "invalidType" })
    );
  });

  it("denies PR with zero or negative value", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .collection("personalRecords")
        .doc("pr-3")
        .set({ ...validPR, id: "pr-3", value: 0 })
    );
  });

  it("denies PR with mismatched userId", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .collection("personalRecords")
        .doc("pr-4")
        .set({ ...validPR, id: "pr-4", userId: USER_B })
    );
  });

  it("denies updating a PR to an invalid value", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("users")
        .doc(USER_A)
        .collection("personalRecords")
        .doc("pr-1")
        .set(validPR);
    });
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .collection("personalRecords")
        .doc("pr-1")
        .update({ value: 0 })
    );
  });

  it("denies user B from reading user A's PRs", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("users")
        .doc(USER_A)
        .collection("personalRecords")
        .doc("pr-1")
        .set(validPR);
    });
    const db = authedDb(USER_B);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .collection("personalRecords")
        .doc("pr-1")
        .get()
    );
  });
});

// ══════════════════════════════════════════
// Workout Sessions rules
// ══════════════════════════════════════════

describe("users/{userId}/workoutSessions/{sessionId}", () => {
  const validSession = {
    id: "session-1",
    userId: USER_A,
    workoutName: "Push Day A",
    status: "inProgress",
    startedAt: new Date(),
    exerciseLogs: [],
    durationSeconds: 0,
  };

  it("allows owner to create a valid session", async () => {
    const db = authedDb(USER_A);
    await assertSucceeds(
      db
        .collection("users")
        .doc(USER_A)
        .collection("workoutSessions")
        .doc("session-1")
        .set(validSession)
    );
  });

  it("denies session with invalid status", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .collection("workoutSessions")
        .doc("session-2")
        .set({ ...validSession, id: "session-2", status: "hacked" })
    );
  });

  it("denies session with mismatched userId", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .collection("workoutSessions")
        .doc("session-3")
        .set({ ...validSession, id: "session-3", userId: USER_B })
    );
  });
});

// ══════════════════════════════════════════
// Workout Plans rules
// ══════════════════════════════════════════

describe("users/{userId}/workoutPlans/{planId}", () => {
  const validPlan = {
    id: "plan-1",
    userId: USER_A,
    name: "PPL Program",
    templateType: "ppl",
    goal: "hypertrophy",
    weekCount: 6,
    currentWeek: 1,
    workoutsPerWeek: 4,
    workouts: [],
    isActive: true,
    createdAt: new Date(),
    aiGenerated: true,
  };

  it("allows owner to create a valid plan", async () => {
    const db = authedDb(USER_A);
    await assertSucceeds(
      db
        .collection("users")
        .doc(USER_A)
        .collection("workoutPlans")
        .doc("plan-1")
        .set(validPlan)
    );
  });

  it("denies plan with workoutsPerWeek > 7", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .collection("workoutPlans")
        .doc("plan-2")
        .set({ ...validPlan, id: "plan-2", workoutsPerWeek: 8 })
    );
  });

  it("denies plan with empty name", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .collection("workoutPlans")
        .doc("plan-3")
        .set({ ...validPlan, id: "plan-3", name: "" })
    );
  });

  it("denies updating plan workoutsPerWeek outside the valid range", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("users")
        .doc(USER_A)
        .collection("workoutPlans")
        .doc("plan-1")
        .set(validPlan);
    });
    const db = authedDb(USER_A);
    await assertFails(
      db
        .collection("users")
        .doc(USER_A)
        .collection("workoutPlans")
        .doc("plan-1")
        .update({ workoutsPerWeek: 8 })
    );
  });
});

// ══════════════════════════════════════════
// Global collections
// ══════════════════════════════════════════

describe("exercises (global read-only)", () => {
  it("allows authenticated read", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("exercises")
        .doc("bench-press")
        .set({ name: "Bench Press" });
    });
    const db = authedDb(USER_A);
    await assertSucceeds(db.collection("exercises").doc("bench-press").get());
  });

  it("denies unauthenticated read", async () => {
    const db = unauthDb();
    await assertFails(db.collection("exercises").doc("bench-press").get());
  });

  it("denies any client write", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db.collection("exercises").doc("new-ex").set({ name: "Hack" })
    );
  });
});

// ══════════════════════════════════════════
// AI usage logs (deny all client access)
// ══════════════════════════════════════════

describe("aiUsageLogs (server-only)", () => {
  it("denies authenticated read", async () => {
    const db = authedDb(USER_A);
    await assertFails(db.collection("aiUsageLogs").doc("log-1").get());
  });

  it("denies authenticated write", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db.collection("aiUsageLogs").doc("log-1").set({ userId: USER_A })
    );
  });
});

// ══════════════════════════════════════════
// Catch-all deny
// ══════════════════════════════════════════

describe("unknown collections", () => {
  it("denies access to arbitrary collections", async () => {
    const db = authedDb(USER_A);
    await assertFails(
      db.collection("secretStuff").doc("doc-1").set({ data: "hack" })
    );
  });
});
