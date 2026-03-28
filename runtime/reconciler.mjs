import { createRequire } from "node:module";

import { beginEpoch, pruneStaleCallbacks, register } from "./callback-registry.mjs";

const require = createRequire(import.meta.url);
const ReactReconciler = require("react-reconciler");
const { DefaultEventPriority } = require("react-reconciler/constants");

function appendChild(parent, child) {
  parent.children.push(child);
}

function removeChild(parent, child) {
  const index = parent.children.indexOf(child);
  if (index >= 0) {
    parent.children.splice(index, 1);
  }
}

function insertChild(parent, child, beforeChild) {
  const index = parent.children.indexOf(beforeChild);
  if (index === -1) {
    parent.children.push(child);
    return;
  }

  parent.children.splice(index, 0, child);
}

function flattenText(input) {
  if (input == null || input === false) {
    return "";
  }

  if (Array.isArray(input)) {
    return input.map(flattenText).join("");
  }

  if (typeof input === "string" || typeof input === "number") {
    return String(input);
  }

  return "";
}

function sanitizeProps(type, rawProps = {}) {
  const props = {};

  for (const [key, value] of Object.entries(rawProps)) {
    if (key === "children" || value === undefined) {
      continue;
    }

    props[key] = typeof value === "function" ? register(value) : value;
  }

  if (type === "Text" && props.text == null) {
    props.text = flattenText(rawProps.children);
  }

  if (type === "Button" && props.title == null) {
    props.title = flattenText(rawProps.children);
  }

  return props;
}

function snapshotRoot(children) {
  const nodes = structuredClone(children);
  if (nodes.length === 0) {
    return {
      type: "Stack",
      key: null,
      props: {
        spacing: 0,
      },
      children: [],
    };
  }

  if (nodes.length === 1) {
    return nodes[0];
  }

  return {
    type: "Stack",
    key: null,
    props: {
      spacing: 0,
    },
    children: nodes,
  };
}

const hostConfig = {
  now: Date.now,
  getRootHostContext() {
    return null;
  },
  getChildHostContext() {
    return null;
  },
  getPublicInstance(instance) {
    return instance;
  },
  prepareForCommit() {
    return null;
  },
  resetAfterCommit(container) {
    beginEpoch();
    pruneStaleCallbacks();

    container.renderRevision += 1;
    container.onCommit?.({
      kind: "full",
      renderRevision: container.renderRevision,
      data: snapshotRoot(container.children),
    });
  },
  createInstance(type, rawProps) {
    return {
      type,
      key: null,
      props: sanitizeProps(type, rawProps),
      children: [],
    };
  },
  appendInitialChild(parent, child) {
    appendChild(parent, child);
  },
  finalizeInitialChildren() {
    return false;
  },
  prepareUpdate() {
    return true;
  },
  shouldSetTextContent(type) {
    return type === "Text";
  },
  createTextInstance(text) {
    return {
      type: "__text",
      key: null,
      props: { text },
      children: [],
    };
  },
  scheduleTimeout: setTimeout,
  cancelTimeout: clearTimeout,
  noTimeout: -1,
  supportsMicrotasks: true,
  scheduleMicrotask: queueMicrotask,
  getCurrentEventPriority() {
    return DefaultEventPriority;
  },
  supportsMutation: true,
  appendChild,
  appendChildToContainer(container, child) {
    container.children.push(child);
  },
  removeChild,
  removeChildFromContainer(container, child) {
    removeChild(container, child);
  },
  insertBefore(parent, child, beforeChild) {
    insertChild(parent, child, beforeChild);
  },
  insertInContainerBefore(container, child, beforeChild) {
    insertChild(container, child, beforeChild);
  },
  commitUpdate(instance, _updatePayload, type, _oldProps, newProps) {
    instance.props = sanitizeProps(type, newProps);
  },
  commitTextUpdate(textInstance, _oldText, newText) {
    textInstance.props.text = newText;
  },
  resetTextContent(instance) {
    instance.props.text = "";
  },
  clearContainer(container) {
    container.children = [];
    return false;
  },
  detachDeletedInstance() {},
};

const reconciler = ReactReconciler(hostConfig);

export function createRenderer() {
  const container = {
    children: [],
    renderRevision: 0,
    onCommit: null,
  };

  const root = reconciler.createContainer(
    container,
    0,
    null,
    false,
    null,
    "",
    () => {},
    null
  );

  return {
    render(element) {
      reconciler.flushSync(() => {
        reconciler.updateContainer(element, root, null, null);
      });
    },
    unmount() {
      reconciler.flushSync(() => {
        reconciler.updateContainer(null, root, null, null);
      });
    },
    onCommit(callback) {
      container.onCommit = callback;
    },
  };
}
