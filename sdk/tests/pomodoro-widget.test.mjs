import assert from "node:assert/strict";
import { test } from "node:test";
import * as pomodoro from "../../widgets/pomodoro/src/pomodoro-state.mjs";
import { getLayoutMetrics } from "../../widgets/pomodoro/src/pomodoro-layout.mjs";

test("normalizePreferences applies defaults and clamps rounds into the supported range", () => {
  assert.deepEqual(
    pomodoro.normalizePreferences({
      focusMinutes: "",
      shortBreakMinutes: "0",
      longBreakMinutes: "15",
      rounds: "12",
    }),
    {
      focusMinutes: 25,
      shortBreakMinutes: 5,
      longBreakMinutes: 15,
      rounds: 8,
    }
  );

  assert.deepEqual(
    pomodoro.normalizePreferences({
      focusMinutes: "30",
      shortBreakMinutes: "7",
      longBreakMinutes: "20",
      rounds: "1",
    }),
    {
      focusMinutes: 30,
      shortBreakMinutes: 7,
      longBreakMinutes: 20,
      rounds: 1,
    }
  );
});

test("start, pause, and reset preserve the current session rules", () => {
  const preferences = pomodoro.normalizePreferences({
    focusMinutes: "25",
    shortBreakMinutes: "5",
    longBreakMinutes: "15",
    rounds: "4",
  });

  const idleState = pomodoro.createDefaultState();
  const runningState = pomodoro.startOrResumeSession(idleState, preferences, 1_000);

  assert.equal(runningState.status, "running");
  assert.equal(runningState.endsAtMs, 1_501_000);

  const pausedState = pomodoro.pauseSession(runningState, preferences, 61_000);
  assert.equal(pausedState.status, "paused");
  assert.equal(pausedState.remainingMs, 1_440_000);

  const resetState = pomodoro.resetCurrentSession(pausedState);
  assert.equal(resetState.status, "idle");
  assert.equal(resetState.sessionKind, pomodoro.SESSION_KINDS.focus);
  assert.equal(resetState.completedFocusCount, 0);
  assert.equal(resetState.remainingMs, null);
});

test("focus completion advances through short and long breaks correctly", () => {
  const preferences = pomodoro.normalizePreferences({
    focusMinutes: "25",
    shortBreakMinutes: "5",
    longBreakMinutes: "15",
    rounds: "4",
  });

  const afterFirstFocus = pomodoro.advanceCompletedSession(
    {
      ...pomodoro.createDefaultState(),
      sessionKind: pomodoro.SESSION_KINDS.focus,
    },
    preferences
  );

  assert.equal(afterFirstFocus.sessionKind, pomodoro.SESSION_KINDS.shortBreak);
  assert.equal(afterFirstFocus.completedFocusCount, 1);
  assert.equal(afterFirstFocus.remainingMs, null);
  assert.equal(pomodoro.getDisplayRemainingMs(afterFirstFocus, preferences, 0), 300_000);

  const beforeLongBreak = {
    ...pomodoro.createDefaultState(),
    sessionKind: pomodoro.SESSION_KINDS.focus,
    completedFocusCount: 3,
  };
  const afterFourthFocus = pomodoro.advanceCompletedSession(beforeLongBreak, preferences);

  assert.equal(afterFourthFocus.sessionKind, pomodoro.SESSION_KINDS.longBreak);
  assert.equal(afterFourthFocus.completedFocusCount, 4);
  assert.equal(afterFourthFocus.remainingMs, null);
  assert.equal(pomodoro.getDisplayRemainingMs(afterFourthFocus, preferences, 0), 900_000);

  const afterLongBreak = pomodoro.advanceCompletedSession(afterFourthFocus, preferences);
  assert.equal(afterLongBreak.sessionKind, pomodoro.SESSION_KINDS.focus);
  assert.equal(afterLongBreak.completedFocusCount, 0);
  assert.equal(afterLongBreak.remainingMs, null);
  assert.equal(pomodoro.getDisplayRemainingMs(afterLongBreak, preferences, 0), 1_500_000);
});

test("idle sessions pick up new preferences immediately while paused sessions do not", () => {
  const oldPreferences = pomodoro.normalizePreferences({
    focusMinutes: "25",
    shortBreakMinutes: "5",
    longBreakMinutes: "15",
    rounds: "4",
  });
  const newPreferences = pomodoro.normalizePreferences({
    focusMinutes: "50",
    shortBreakMinutes: "10",
    longBreakMinutes: "20",
    rounds: "6",
  });

  const idleState = pomodoro.createDefaultState();
  assert.equal(pomodoro.getDisplayRemainingMs(idleState, newPreferences, 0), 3_000_000);

  const runningState = pomodoro.startOrResumeSession(idleState, oldPreferences, 0);
  const pausedState = pomodoro.pauseSession(runningState, oldPreferences, 600_000);

  assert.equal(pomodoro.getDisplayRemainingMs(pausedState, newPreferences, 0), 900_000);

  const resetState = pomodoro.resetCurrentSession(pausedState);
  assert.equal(resetState.remainingMs, null);
  assert.equal(pomodoro.getDisplayRemainingMs(resetState, newPreferences, 0), 3_000_000);
});

test("syncElapsedSession advances already-expired running sessions on remount", () => {
  const preferences = pomodoro.normalizePreferences({
    focusMinutes: "25",
    shortBreakMinutes: "5",
    longBreakMinutes: "15",
    rounds: "4",
  });

  const runningState = pomodoro.startOrResumeSession(
    pomodoro.createDefaultState(),
    preferences,
    1_000
  );

  const syncedState = pomodoro.syncElapsedSession(runningState, preferences, 1_501_000);
  assert.equal(syncedState.status, "idle");
  assert.equal(syncedState.sessionKind, pomodoro.SESSION_KINDS.shortBreak);
  assert.equal(syncedState.completedFocusCount, 1);
});

test("current round and completed round counts stay distinct during focus and breaks", () => {
  const preferences = pomodoro.normalizePreferences({ rounds: "4" });

  const focusState = {
    ...pomodoro.createDefaultState(),
    completedFocusCount: 1,
  };

  assert.equal(pomodoro.getCurrentRoundNumber(focusState, preferences), 2);
  assert.equal(pomodoro.getCompletedRoundCount(focusState, preferences), 1);

  const shortBreakState = {
    ...focusState,
    sessionKind: pomodoro.SESSION_KINDS.shortBreak,
  };

  assert.equal(pomodoro.getCurrentRoundNumber(shortBreakState, preferences), 1);
  assert.equal(pomodoro.getCompletedRoundCount(shortBreakState, preferences), 1);
});

test("notificationPayloadForSession returns stable per-session copy", () => {
  assert.deepEqual(
    pomodoro.notificationPayloadForSession(pomodoro.SESSION_KINDS.focus, 123),
    {
      title: "Focus complete",
      body: "Time for a short break.",
      deliverAtMs: 123,
    }
  );

  assert.deepEqual(
    pomodoro.notificationPayloadForSession(pomodoro.SESSION_KINDS.shortBreak, 456),
    {
      title: "Short break complete",
      body: "Time to get back to focus.",
      deliverAtMs: 456,
    }
  );

  assert.deepEqual(
    pomodoro.notificationPayloadForSession(pomodoro.SESSION_KINDS.longBreak, 789),
    {
      title: "Long break complete",
      body: "Your next cycle is ready to start.",
      deliverAtMs: 789,
    }
  );
});

test("createPomodoroViewModel combines label, timing, and progress state", () => {
  const preferences = pomodoro.normalizePreferences({
    focusMinutes: "25",
    shortBreakMinutes: "5",
    longBreakMinutes: "15",
    rounds: "4",
  });
  const pausedState = {
    ...pomodoro.createDefaultState(),
    status: "paused",
    remainingMs: 90_000,
    completedFocusCount: 2,
  };

  assert.deepEqual(
    pomodoro.createPomodoroViewModel(pausedState, preferences, 0),
    {
      currentRoundNumber: 3,
      completedRoundCount: 2,
      stageName: "Focus",
      primaryLabel: "Resume",
      remainingMs: 90_000,
    }
  );
});

test("normalizeState recovers invalid running and paused persisted states", () => {
  assert.deepEqual(
    pomodoro.normalizeState({
      sessionKind: pomodoro.SESSION_KINDS.shortBreak,
      status: "running",
      endsAtMs: null,
      remainingMs: 123,
      completedFocusCount: 2,
    }),
    {
      version: pomodoro.STATE_VERSION,
      sessionKind: pomodoro.SESSION_KINDS.shortBreak,
      status: "idle",
      endsAtMs: null,
      remainingMs: null,
      completedFocusCount: 2,
    }
  );

  assert.deepEqual(
    pomodoro.normalizeState({
      sessionKind: pomodoro.SESSION_KINDS.longBreak,
      status: "paused",
      endsAtMs: 456,
      remainingMs: null,
      completedFocusCount: 4,
    }),
    {
      version: pomodoro.STATE_VERSION,
      sessionKind: pomodoro.SESSION_KINDS.longBreak,
      status: "idle",
      endsAtMs: null,
      remainingMs: null,
      completedFocusCount: 4,
    }
  );
});

test("getLayoutMetrics interpolates span sizes and densifies dots for larger round counts", () => {
  assert.deepEqual(getLayoutMetrics(3, 4), {
    verticalInset: 4,
    sectionSpacing: 16,
    headerSpacing: 8,
    cycleSize: 11,
    stageSize: 12,
    timerSize: 38,
    dotSize: 6,
    dotGap: 4,
    controlsGap: 10,
    primaryWidth: 68,
    primaryHeight: 34,
    primaryLabelSize: 12,
    secondarySize: 34,
    secondaryIconSize: 13,
  });

  assert.deepEqual(getLayoutMetrics(6, 7), {
    verticalInset: 7,
    sectionSpacing: 22,
    headerSpacing: 11,
    cycleSize: 11.6,
    stageSize: 12.8,
    timerSize: 47,
    dotSize: 5,
    dotGap: 3,
    controlsGap: 13,
    primaryWidth: 92,
    primaryHeight: 37,
    primaryLabelSize: 12.9,
    secondarySize: 37,
    secondaryIconSize: 13.9,
  });
});
