import readline from "node:readline";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const widgets = new Map();
const widgetStates = new Map();

// Actions can either return next state directly or ask the host runtime to
// perform a generic platform capability and then dispatch follow-up actions.
function hostCapabilityFor(value) {
  if (!value || typeof value !== "object") {
    return null;
  }

  const capability = value.__notchHostCapability;
  if (!capability || typeof capability !== "object") {
    return null;
  }

  if (typeof capability.type !== "string" || capability.type.trim() === "") {
    throw new Error("Invalid host capability request: missing type.");
  }

  return {
    type: capability.type,
    data: capability.data ?? null,
    progressAction: typeof capability.progressAction === "string" ? capability.progressAction : null,
    successAction: typeof capability.successAction === "string" ? capability.successAction : null,
    cancelAction: typeof capability.cancelAction === "string" ? capability.cancelAction : null,
    errorAction: typeof capability.errorAction === "string" ? capability.errorAction : null,
  };
}

function nextStateFor(value) {
  if (!value || typeof value !== "object") {
    return value;
  }

  if (Object.prototype.hasOwnProperty.call(value, "__notchNextState")) {
    return value.__notchNextState;
  }

  if (Object.prototype.hasOwnProperty.call(value, "__notchHostCapability")) {
    return undefined;
  }

  return value;
}

function send(payload) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

function widgetLogger(widgetID) {
  const emit = (level) => (...parts) => {
    send({
      type: "log",
      widgetID,
      level,
      message: parts.map((part) => typeof part === "string" ? part : JSON.stringify(part)).join(" "),
    });
  };

  return {
    log: emit("log"),
    info: emit("info"),
    warn: emit("warn"),
    error: emit("error"),
  };
}

function clearWidget(widgetID, bundlePath) {
  widgetStates.delete(widgetID);
  if (bundlePath) {
    try {
      delete require.cache[require.resolve(bundlePath)];
    } catch {
      // ignore
    }
  }
  widgets.delete(widgetID);
}

function loadWidget(widgetID, bundlePath) {
  clearWidget(widgetID, bundlePath);
  const mod = require(bundlePath);
  widgets.set(widgetID, { bundlePath, mod });
}

function ensureWidget(widgetID) {
  const widget = widgets.get(widgetID);
  if (!widget) {
    throw new Error(`Widget ${widgetID} is not loaded.`);
  }
  return widget;
}

function stateFor(widgetID, instanceID, mod) {
  let instances = widgetStates.get(widgetID);
  if (!instances) {
    instances = new Map();
    widgetStates.set(widgetID, instances);
  }

  if (!instances.has(instanceID)) {
    instances.set(instanceID, structuredClone(mod.initialState ?? {}));
  }

  return instances.get(instanceID);
}

function render(widgetID, instanceID, environment) {
  const { mod } = ensureWidget(widgetID);
  const state = stateFor(widgetID, instanceID, mod);
  const logger = widgetLogger(widgetID);
  const tree = mod.default({
    environment,
    state,
    logger,
  });

  return tree;
}

function invokeAction(widgetID, instanceID, actionID, environment, payload) {
  const { mod } = ensureWidget(widgetID);
  const logger = widgetLogger(widgetID);
  const state = stateFor(widgetID, instanceID, mod);
  const action = mod.actions?.[actionID];

  if (!action) {
    throw new Error(`Unknown action '${actionID}' for widget ${widgetID}.`);
  }

  const nextState = action(state, { environment, logger, payload });
  const resolvedNextState = nextStateFor(nextState);
  const hostCapability = hostCapabilityFor(nextState);
  if (resolvedNextState !== undefined) {
    widgetStates.get(widgetID).set(instanceID, resolvedNextState);
  }
  if (hostCapability) {
    return { hostCapability };
  }

  return {};
}

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

for await (const line of rl) {
  if (!line.trim()) continue;

  let message;
  try {
    message = JSON.parse(line);
  } catch (error) {
    send({ type: "error", message: `Invalid JSON: ${error.message}` });
    continue;
  }

  try {
    switch (message.type) {
      case "load":
        loadWidget(message.widgetID, message.bundlePath);
        send({
          requestID: message.requestID,
          type: "ack",
          widgetID: message.widgetID,
          mountAction: typeof ensureWidget(message.widgetID).mod.mountAction === "string"
            ? ensureWidget(message.widgetID).mod.mountAction
            : null,
        });
        break;
      case "reload":
        loadWidget(message.widgetID, message.bundlePath);
        send({
          requestID: message.requestID,
          type: "ack",
          widgetID: message.widgetID,
          mountAction: typeof ensureWidget(message.widgetID).mod.mountAction === "string"
            ? ensureWidget(message.widgetID).mod.mountAction
            : null,
        });
        break;
      case "render": {
        const tree = render(message.widgetID, message.instanceID, message.environment);
        send({ requestID: message.requestID, type: "render", widgetID: message.widgetID, tree });
        break;
      }
      case "action":
        send({
          requestID: message.requestID,
          type: "ack",
          widgetID: message.widgetID,
          ...invokeAction(message.widgetID, message.instanceID, message.actionID, message.environment, message.payload),
        });
        break;
      default:
        throw new Error(`Unsupported message type '${message.type}'.`);
    }
  } catch (error) {
    send({
      requestID: message.requestID,
      type: "error",
      widgetID: message.widgetID,
      message: error instanceof Error ? error.message : String(error),
    });
  }
}
