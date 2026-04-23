const React = require("react");
const { callRpc, subscribeHostEvent } = require("../runtime");
const { useHostMutation, useHostResource } = require("./internal");

const eventsChangedEventName = "events.changed";
const accessLevels = new Set(["none", "writeOnly", "fullAccess"]);
const authorizationStatuses = new Set([
  "notDetermined",
  "denied",
  "restricted",
  "writeOnly",
  "fullAccess",
]);

function normalizeString(value) {
  return typeof value === "string" && value.trim() !== "" ? value : undefined;
}

function normalizeBoolean(value) {
  return typeof value === "boolean" ? value : undefined;
}

function normalizeAccessLevel(value) {
  return typeof value === "string" && accessLevels.has(value) ? value : "none";
}

function normalizeAuthorizationStatus(value) {
  return typeof value === "string" && authorizationStatuses.has(value)
    ? value
    : "notDetermined";
}

function normalizeSource(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }

  const id = normalizeString(value.id);
  if (!id) {
    return undefined;
  }

  return {
    id,
    title: normalizeString(value.title),
    kind: normalizeString(value.kind) ?? "unknown",
  };
}

function normalizeEventCalendar(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const id = normalizeString(value.id);
  const title = normalizeString(value.title);
  if (!id || !title) {
    return null;
  }

  return {
    id,
    title,
    color: normalizeString(value.color),
    source: normalizeSource(value.source),
    allowsContentModifications: normalizeBoolean(value.allowsContentModifications),
    isDefaultForNewEvents: normalizeBoolean(value.isDefaultForNewEvents),
  };
}

function normalizeCalendars(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.map(normalizeEventCalendar).filter(Boolean);
}

function createEmptyEventCalendarsSnapshot() {
  return {
    authorizationStatus: "notDetermined",
    accessLevel: "none",
    items: [],
  };
}

function normalizeEventCalendarsSnapshot(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return createEmptyEventCalendarsSnapshot();
  }

  return {
    authorizationStatus: normalizeAuthorizationStatus(value.authorizationStatus),
    accessLevel: normalizeAccessLevel(value.accessLevel),
    items: normalizeCalendars(value.items),
  };
}

function useEventCalendars() {
  const resource = useHostResource(
    () => callRpc("events.listCalendars", {}),
    [],
    { initialData: createEmptyEventCalendarsSnapshot() }
  );
  const actionMutation = useHostMutation(async (input) => {
    return callRpc(input.method, input.params ?? {});
  });
  const data = normalizeEventCalendarsSnapshot(resource.data);

  React.useEffect(() => {
    return subscribeHostEvent(eventsChangedEventName, () => {
      resource.refresh();
    });
  }, [resource.refresh]);

  const invoke = React.useCallback((method, params) => {
    const pending = actionMutation.mutate({ method, params });
    pending.catch(() => {});
    return pending;
  }, [actionMutation.mutate]);

  return {
    ...data,
    isLoading: resource.isLoading,
    isPending: actionMutation.isPending,
    error: resource.error,
    actionError: actionMutation.error,
    refresh: resource.refresh,
    requestAccess(level = "fullAccess") {
      const pending = invoke("events.requestAccess", { level });
      pending.finally(() => {
        resource.refresh();
      }).catch(() => {});
    },
  };
}

module.exports = {
  useEventCalendars,
  normalizeEventCalendarsSnapshot,
  createEmptyEventCalendarsSnapshot,
};
