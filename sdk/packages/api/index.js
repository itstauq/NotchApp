function flattenChildren(input) {
  if (input == null || input === false) return [];
  if (Array.isArray(input)) return input.flatMap(flattenChildren);
  return [input];
}

function extractText(input) {
  return flattenChildren(input)
    .map((item) => {
      if (typeof item === "string" || typeof item === "number") return String(item);
      if (item && typeof item.text === "string") return item.text;
      return "";
    })
    .join("");
}

function wrapNode(input) {
  if (input == null || input === false) return null;
  const flattened = flattenChildren(input);
  if (flattened.length === 0) return null;
  return { node: flattened[0] };
}

function Stack(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Stack",
    direction: props.direction ?? "vertical",
    spacing: props.spacing ?? 8,
    children: flattenChildren(props.children),
  };
}

function Inline(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Inline",
    spacing: props.spacing ?? 8,
    children: flattenChildren(props.children),
  };
}

function Spacer(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Spacer",
    children: [],
  };
}

function ScrollView(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "ScrollView",
    spacing: props.spacing ?? 8,
    children: flattenChildren(props.children),
  };
}

function Row(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Row",
    action: props.action ?? null,
    payload: props.payload ?? null,
    children: flattenChildren(props.children),
  };
}

function Text(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Text",
    text: props.text ?? extractText(props.children),
    role: props.role ?? undefined,
    tone: props.tone ?? undefined,
    lineClamp: props.lineClamp ?? undefined,
    strikethrough: props.strikethrough ?? undefined,
    children: [],
  };
}

function Icon(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Icon",
    symbol: props.symbol ?? props.icon ?? props.name ?? undefined,
    tone: props.tone ?? undefined,
    children: [],
  };
}

function IconButton(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "IconButton",
    symbol: props.symbol ?? props.icon ?? props.name ?? undefined,
    action: props.action ?? null,
    payload: props.payload ?? null,
    tone: props.tone ?? undefined,
    size: props.size ?? undefined,
    disabled: props.disabled ?? false,
    children: [],
  };
}

function Checkbox(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Checkbox",
    checked: props.checked ?? false,
    action: props.action ?? null,
    payload: props.payload ?? null,
    children: [],
  };
}

function Input(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Input",
    value: props.value ?? "",
    placeholder: props.placeholder ?? "",
    changeAction: props.changeAction ?? null,
    submitAction: props.submitAction ?? null,
    leadingAccessory: wrapNode(props.leadingAccessory),
    trailingAccessory: wrapNode(props.trailingAccessory),
    children: [],
  };
}

function Button(props = {}) {
  return {
    id: props.id ?? undefined,
    type: "Button",
    title: props.title ?? extractText(props.children),
    action: props.action ?? null,
    payload: props.payload ?? null,
    children: [],
  };
}

function requestHostCapability(type, props = {}) {
  return {
    __notchHostCapability: {
      type,
      data: props.data ?? null,
      progressAction: props.progressAction ?? null,
      successAction: props.successAction ?? null,
      cancelAction: props.cancelAction ?? null,
      errorAction: props.errorAction ?? null,
    },
  };
}

function storageGet(key, props = {}) {
  return requestHostCapability("storageGet", {
    ...props,
    data: { key },
  });
}

function storageSet(key, value, props = {}) {
  return requestHostCapability("storageSet", {
    ...props,
    data: { key, value },
  });
}

function storageRemove(key, props = {}) {
  return requestHostCapability("storageRemove", {
    ...props,
    data: { key },
  });
}

module.exports = {
  Stack,
  Inline,
  Spacer,
  ScrollView,
  Row,
  Text,
  Icon,
  IconButton,
  Checkbox,
  Input,
  Button,
  storageGet,
  storageSet,
  storageRemove,
  __internal: {
    flattenChildren,
    extractText,
    requestHostCapability,
  },
};
