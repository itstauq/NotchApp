/**
 * @typedef {"focus" | "shortBreak" | "longBreak"} SessionKind
 * @typedef {"idle" | "running" | "paused"} SessionStatus
 * @typedef {{
 *   focusMinutes: number
 *   shortBreakMinutes: number
 *   longBreakMinutes: number
 *   rounds: number
 * }} PomodoroPreferences
 * @typedef {{
 *   version: number
 *   sessionKind: SessionKind
 *   status: SessionStatus
 *   endsAtMs: number | null
 *   remainingMs: number | null
 *   completedFocusCount: number
 * }} PomodoroState
 * @typedef {{
 *   currentRoundNumber: number
 *   completedRoundCount: number
 *   stageName: string
 *   primaryLabel: string
 *   remainingMs: number
 * }} PomodoroViewModel
 */

export const SESSION_KINDS = Object.freeze({
  focus: "focus",
  shortBreak: "shortBreak",
  longBreak: "longBreak",
});

export const SESSION_COMPLETE_NOTIFICATION_ID = "session-complete";
export const STORAGE_KEY = "pomodoroState";
export const STATE_VERSION = 1;
export const DEFAULT_PREFERENCES = Object.freeze({
  focusMinutes: 25,
  shortBreakMinutes: 5,
  longBreakMinutes: 15,
  rounds: 4,
});

const STATUS_VALUES = new Set(["idle", "running", "paused"]);
const SESSION_KIND_VALUES = new Set(Object.values(SESSION_KINDS));

function finiteNumber(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  return null;
}

function normalizeInteger(value, fallback, { min = 1, max = Infinity } = {}) {
  const parsed = finiteNumber(value);
  if (parsed == null) {
    return fallback;
  }

  const normalized = Math.floor(parsed);
  if (!Number.isFinite(normalized) || normalized < min) {
    return fallback;
  }

  return Math.min(normalized, max);
}

export function normalizePreferences(rawPreferences = {}) {
  return {
    focusMinutes: normalizeInteger(
      rawPreferences.focusMinutes,
      DEFAULT_PREFERENCES.focusMinutes
    ),
    shortBreakMinutes: normalizeInteger(
      rawPreferences.shortBreakMinutes,
      DEFAULT_PREFERENCES.shortBreakMinutes
    ),
    longBreakMinutes: normalizeInteger(
      rawPreferences.longBreakMinutes,
      DEFAULT_PREFERENCES.longBreakMinutes
    ),
    rounds: normalizeInteger(rawPreferences.rounds, DEFAULT_PREFERENCES.rounds, {
      min: 1,
      max: 8,
    }),
  };
}

/** @returns {PomodoroState} */
export function createDefaultState() {
  return {
    version: STATE_VERSION,
    sessionKind: SESSION_KINDS.focus,
    status: "idle",
    endsAtMs: null,
    remainingMs: null,
    completedFocusCount: 0,
  };
}

/**
 * @param {unknown} rawState
 * @returns {PomodoroState}
 */
export function normalizeState(rawState) {
  if (!rawState || typeof rawState !== "object" || Array.isArray(rawState)) {
    return createDefaultState();
  }

  const sessionKind = SESSION_KIND_VALUES.has(rawState.sessionKind)
    ? rawState.sessionKind
    : SESSION_KINDS.focus;
  const status = STATUS_VALUES.has(rawState.status) ? rawState.status : "idle";
  const endsAtMs = finiteNumber(rawState.endsAtMs);
  const remainingMs = finiteNumber(rawState.remainingMs);
  const completedFocusCount = Math.max(
    0,
    normalizeInteger(rawState.completedFocusCount, 0, {
      min: 0,
      max: Number.MAX_SAFE_INTEGER,
    })
  );

  if (status === "running" && endsAtMs == null) {
    return toIdleState(sessionKind, completedFocusCount);
  }

  if (status === "paused" && remainingMs == null) {
    return toIdleState(sessionKind, completedFocusCount);
  }

  return {
    version: STATE_VERSION,
    sessionKind,
    status,
    endsAtMs: status === "running" ? endsAtMs : null,
    remainingMs: status === "paused" ? Math.max(0, remainingMs) : null,
    completedFocusCount,
  };
}

/**
 * @param {SessionKind} sessionKind
 * @param {PomodoroPreferences} preferences
 */
function sessionDurationMinutes(sessionKind, preferences) {
  switch (sessionKind) {
    case SESSION_KINDS.shortBreak:
      return preferences.shortBreakMinutes;
    case SESSION_KINDS.longBreak:
      return preferences.longBreakMinutes;
    default:
      return preferences.focusMinutes;
  }
}

/**
 * @param {SessionKind} sessionKind
 * @param {PomodoroPreferences} preferences
 */
export function sessionDurationMs(sessionKind, preferences) {
  return sessionDurationMinutes(sessionKind, preferences) * 60 * 1000;
}

/**
 * @param {SessionKind} sessionKind
 * @param {number} completedFocusCount
 * @returns {PomodoroState}
 */
function toIdleState(sessionKind, completedFocusCount) {
  return {
    version: STATE_VERSION,
    sessionKind,
    status: "idle",
    endsAtMs: null,
    remainingMs: null,
    completedFocusCount: Math.max(0, Math.floor(completedFocusCount || 0)),
  };
}

/**
 * @param {PomodoroState} state
 * @param {PomodoroPreferences} preferences
 * @param {number} [nowMs]
 */
export function getDisplayRemainingMs(state, preferences, nowMs = Date.now()) {
  if (state.status === "running" && state.endsAtMs != null) {
    return Math.max(0, state.endsAtMs - nowMs);
  }

  if (state.status === "paused" && state.remainingMs != null) {
    return Math.max(0, state.remainingMs);
  }

  return sessionDurationMinutes(state.sessionKind, preferences) * 60 * 1000;
}

/**
 * @param {PomodoroState} state
 * @param {PomodoroPreferences} preferences
 */
export function getCurrentRoundNumber(state, preferences) {
  if (state.sessionKind === SESSION_KINDS.focus) {
    return Math.min(
      Math.max(1, state.completedFocusCount + 1),
      preferences.rounds
    );
  }

  return Math.min(
    Math.max(1, state.completedFocusCount),
    preferences.rounds
  );
}

/**
 * @param {PomodoroState} state
 * @param {PomodoroPreferences} preferences
 */
export function getCompletedRoundCount(state, preferences) {
  return Math.min(
    Math.max(0, state.completedFocusCount),
    preferences.rounds
  );
}

export function stageNameForSession(sessionKind) {
  switch (sessionKind) {
    case SESSION_KINDS.shortBreak:
      return "Short Break";
    case SESSION_KINDS.longBreak:
      return "Long Break";
    default:
      return "Focus";
  }
}

export function primaryLabelForStatus(status) {
  switch (status) {
    case "running":
      return "Pause";
    case "paused":
      return "Resume";
    default:
      return "Start";
  }
}

/**
 * @param {PomodoroState} state
 * @param {PomodoroPreferences} preferences
 * @param {number} [nowMs]
 * @returns {PomodoroViewModel}
 */
export function createPomodoroViewModel(state, preferences, nowMs = Date.now()) {
  return {
    currentRoundNumber: getCurrentRoundNumber(state, preferences),
    completedRoundCount: getCompletedRoundCount(state, preferences),
    stageName: stageNameForSession(state.sessionKind),
    primaryLabel: primaryLabelForStatus(state.status),
    remainingMs: getDisplayRemainingMs(state, preferences, nowMs),
  };
}

/**
 * @param {PomodoroState} state
 * @param {PomodoroPreferences} preferences
 * @param {number} [nowMs]
 * @returns {PomodoroState}
 */
export function startOrResumeSession(state, preferences, nowMs = Date.now()) {
  if (state.status === "running") {
    return state;
  }

  const remainingMs =
    state.status === "paused" && state.remainingMs != null
      ? Math.max(0, state.remainingMs)
      : sessionDurationMs(state.sessionKind, preferences);

  return {
    ...state,
    status: "running",
    endsAtMs: nowMs + remainingMs,
    remainingMs: null,
  };
}

/**
 * @param {PomodoroState} state
 * @param {PomodoroPreferences} preferences
 * @param {number} [nowMs]
 * @returns {PomodoroState}
 */
export function pauseSession(state, preferences, nowMs = Date.now()) {
  if (state.status !== "running" || state.endsAtMs == null) {
    return state;
  }

  return {
    ...state,
    status: "paused",
    endsAtMs: null,
    remainingMs: getDisplayRemainingMs(state, preferences, nowMs),
  };
}

/**
 * @param {PomodoroState} state
 * @returns {PomodoroState}
 */
export function resetCurrentSession(state) {
  return toIdleState(state.sessionKind, state.completedFocusCount);
}

/**
 * @param {PomodoroState} state
 * @param {SessionKind | string} sessionKind
 * @returns {PomodoroState}
 */
export function switchSession(state, sessionKind) {
  const nextSessionKind = SESSION_KIND_VALUES.has(sessionKind)
    ? sessionKind
    : SESSION_KINDS.focus;

  return toIdleState(nextSessionKind, state.completedFocusCount);
}

/**
 * @returns {PomodoroState}
 */
export function resetCycle() {
  return toIdleState(SESSION_KINDS.focus, 0);
}

/**
 * @param {PomodoroState} state
 * @param {PomodoroPreferences} preferences
 * @returns {PomodoroState}
 */
export function advanceCompletedSession(state, preferences) {
  if (state.sessionKind === SESSION_KINDS.focus) {
    const nextCompletedFocusCount = state.completedFocusCount + 1;

    if (nextCompletedFocusCount >= preferences.rounds) {
      return toIdleState(SESSION_KINDS.longBreak, nextCompletedFocusCount);
    }

    return toIdleState(SESSION_KINDS.shortBreak, nextCompletedFocusCount);
  }

  if (state.sessionKind === SESSION_KINDS.shortBreak) {
    return toIdleState(SESSION_KINDS.focus, state.completedFocusCount);
  }

  return toIdleState(SESSION_KINDS.focus, 0);
}

/**
 * @param {PomodoroState} state
 * @param {PomodoroPreferences} preferences
 * @param {number} [nowMs]
 * @returns {PomodoroState}
 */
export function syncElapsedSession(state, preferences, nowMs = Date.now()) {
  if (
    state.status !== "running"
    || state.endsAtMs == null
    || state.endsAtMs > nowMs
  ) {
    return state;
  }

  return advanceCompletedSession(state, preferences);
}

/**
 * @param {SessionKind | string} sessionKind
 * @param {number} deliverAtMs
 */
export function notificationPayloadForSession(sessionKind, deliverAtMs) {
  switch (sessionKind) {
    case SESSION_KINDS.shortBreak:
      return {
        title: "Short break complete",
        body: "Time to get back to focus.",
        deliverAtMs,
      };
    case SESSION_KINDS.longBreak:
      return {
        title: "Long break complete",
        body: "Your next cycle is ready to start.",
        deliverAtMs,
      };
    default:
      return {
        title: "Focus complete",
        body: "Time for a short break.",
        deliverAtMs,
      };
  }
}
