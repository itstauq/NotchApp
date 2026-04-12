const React = require("react");
const { callRpc, subscribeHostEvent } = require("../runtime");
const { useHostMutation, useHostSubscriptionResource } = require("./internal");

const audioStateEventName = "audio.state";
const playbackStates = new Set(["playing", "paused", "stopped"]);

function createEmptyAudioState() {
  return {
    playbackState: "stopped",
    players: [],
  };
}

function normalizeString(value) {
  return typeof value === "string" && value.trim() !== "" ? value : undefined;
}

function normalizeVolume(value) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return undefined;
  }

  return Math.min(Math.max(value, 0), 1);
}

function normalizePlaybackState(value) {
  return typeof value === "string" && playbackStates.has(value) ? value : undefined;
}

function normalizePlayer(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const id = normalizeString(value.id);
  const src = normalizeString(value.src);
  if (id === undefined || src === undefined) {
    return null;
  }

  return {
    id,
    src,
    playbackState: normalizePlaybackState(value.playbackState) ?? "stopped",
    volume: normalizeVolume(value.volume) ?? 1,
    loop: value.loop === true,
  };
}

function normalizePlayers(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map(normalizePlayer)
    .filter(Boolean)
    .sort((left, right) => left.id.localeCompare(right.id));
}

function derivePlaybackState(players, requestedState) {
  if (requestedState) {
    return requestedState;
  }

  if (players.length === 0) {
    return "stopped";
  }

  return players.some((player) => player.playbackState === "playing")
    ? "playing"
    : "paused";
}

function normalizeAudioState(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return createEmptyAudioState();
  }

  const players = normalizePlayers(value.players);
  return {
    playbackState: derivePlaybackState(players, normalizePlaybackState(value.playbackState)),
    players,
  };
}

function useAudio() {
  const actionMutation = useHostMutation(async (input) => {
    return callRpc(input.method, input.params ?? {});
  });
  const audioResource = useHostSubscriptionResource({
    initialData: createEmptyAudioState(),
    load: React.useCallback(() => callRpc("audio.getState", {}), []),
    subscribe: React.useCallback((listener) => {
      return subscribeHostEvent(audioStateEventName, listener);
    }, []),
    normalize: normalizeAudioState,
    onResolved: actionMutation.clearError,
  });

  const invoke = React.useCallback((method, params) => {
    const pending = actionMutation.mutate({ method, params });
    pending.catch(() => {});
    return pending;
  }, [actionMutation.mutate]);

  const play = React.useCallback((options = {}) => {
    return invoke("audio.play", {
      playerId: options.playerId,
      src: options.src,
      loop: options.loop,
      volume: options.volume,
    });
  }, [invoke]);
  const pause = React.useCallback((playerId) => {
    return invoke("audio.pause", { playerId });
  }, [invoke]);
  const togglePlayPause = React.useCallback((playerId) => {
    return invoke("audio.togglePlayPause", { playerId });
  }, [invoke]);
  const stop = React.useCallback((playerId) => {
    return invoke("audio.stop", { playerId });
  }, [invoke]);
  const setVolume = React.useCallback((playerId, value) => {
    return invoke("audio.setVolume", { playerId, value });
  }, [invoke]);
  const pauseAll = React.useCallback(() => {
    return invoke("audio.pauseAll", {});
  }, [invoke]);
  const resumeAll = React.useCallback(() => {
    return invoke("audio.resumeAll", {});
  }, [invoke]);
  const stopAll = React.useCallback(() => {
    return invoke("audio.stopAll", {});
  }, [invoke]);

  return {
    ...audioResource.data,
    isLoading: audioResource.isLoading,
    isPending: actionMutation.isPending,
    error: actionMutation.error ?? audioResource.error,
    refresh: audioResource.refresh,
    play,
    pause,
    togglePlayPause,
    stop,
    setVolume,
    pauseAll,
    resumeAll,
    stopAll,
  };
}

module.exports = {
  useAudio,
  normalizeAudioState,
  createEmptyAudioState,
};
