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

function normalizeNumber(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
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

function normalizeEventItem(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const id = normalizeString(value.id);
  const calendarID = normalizeString(value.calendarID);
  const startMs = normalizeNumber(value.startMs);
  const endMs = normalizeNumber(value.endMs);
  if (!id || !calendarID || startMs === undefined || endMs === undefined) {
    return null;
  }

  return {
    id,
    calendarID,
    title: normalizeString(value.title),
    location: normalizeString(value.location),
    notes: normalizeString(value.notes),
    url: normalizeString(value.url),
    startMs,
    endMs,
    isAllDay: value.isAllDay === true,
    isCurrent: value.isCurrent === true,
    isPast: value.isPast === true,
    isUpcoming: value.isUpcoming === true,
  };
}

function normalizeEventItems(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.map(normalizeEventItem).filter(Boolean);
}

function createEmptyEventsSnapshot() {
  return {
    authorizationStatus: "notDetermined",
    accessLevel: "none",
    items: [],
  };
}

function normalizeEventsSnapshot(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return createEmptyEventsSnapshot();
  }

  return {
    authorizationStatus: normalizeAuthorizationStatus(value.authorizationStatus),
    accessLevel: normalizeAccessLevel(value.accessLevel),
    items: normalizeEventItems(value.items),
  };
}

function normalizeEventQuery(query = {}) {
  const normalized = {};

  if (query && typeof query === "object" && !Array.isArray(query)) {
    const startMs = normalizeNumber(query.startMs);
    const endMs = normalizeNumber(query.endMs);
    const includeAllDay = normalizeBoolean(query.includeAllDay);
    const limit = normalizeNumber(query.limit);

    if (startMs !== undefined) {
      normalized.startMs = startMs;
    }

    if (endMs !== undefined) {
      normalized.endMs = endMs;
    }

    if (Array.isArray(query.calendarIDs)) {
      normalized.calendarIDs = query.calendarIDs.filter((value) => typeof value === "string" && value.trim() !== "");
    }

    if (includeAllDay !== undefined) {
      normalized.includeAllDay = includeAllDay;
    }

    if (limit !== undefined) {
      normalized.limit = limit;
    }
  }

  if (normalized.includeAllDay === undefined) {
    normalized.includeAllDay = true;
  }

  return normalized;
}

function useEvents(query = {}) {
  const normalizedQuery = React.useMemo(() => normalizeEventQuery(query), [JSON.stringify(query ?? {})]);
  const queryKey = React.useMemo(() => JSON.stringify(normalizedQuery), [normalizedQuery]);
  const resource = useHostResource(
    () => callRpc("events.getSnapshot", normalizedQuery),
    [queryKey],
    { initialData: createEmptyEventsSnapshot() }
  );
  const actionMutation = useHostMutation(async (input) => {
    return callRpc(input.method, input.params ?? {});
  });
  const data = normalizeEventsSnapshot(resource.data);

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
    openEvent(eventID) {
      invoke("events.openEvent", { eventID });
    },
    openSourceApp() {
      invoke("events.openSourceApp", {});
    },
  };
}

module.exports = {
  useEvents,
  normalizeEventsSnapshot,
  createEmptyEventsSnapshot,
};
