import {
  Checkbox,
  IconButton,
  Inline,
  Input,
  Row,
  ScrollView,
  Spacer,
  Stack,
  Text,
} from "@notchapp/api";

export const initialState = {
  draft: "",
  items: [],
};

function normalizeText(value) {
  return typeof value === "string" ? value : "";
}

function createItem(title) {
  const trimmed = title.trim();
  if (!trimmed) return null;

  return {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    title: trimmed,
    checked: false,
  };
}

function toggleItem(items, id) {
  return items.map((item) =>
    item.id === id ? { ...item, checked: !item.checked } : item,
  );
}

export const actions = {
  changeDraft(state, context) {
    return {
      ...state,
      draft: normalizeText(context?.payload?.value),
    };
  },

  submitDraft(state, context) {
    const submitted = normalizeText(context?.payload?.value);
    const nextItem = createItem(submitted);
    if (!nextItem) {
      return {
        ...state,
        draft: submitted,
      };
    }

    return {
      ...state,
      draft: "",
      items: [nextItem, ...(state?.items ?? [])],
    };
  },

  toggleItem(state, context) {
    const id = context?.payload?.id;
    if (!id) return state;

    return {
      ...state,
      items: toggleItem(state?.items ?? [], id),
    };
  },

  deleteItem(state, context) {
    const id = context?.payload?.id;
    if (!id) return state;

    return {
      ...state,
      items: (state?.items ?? []).filter((item) => item.id !== id),
    };
  },
};

function CaptureRow({ item }) {
  return (
    <Row action="toggleItem" payload={{ id: item.id }}>
      <Inline spacing={8}>
        <Checkbox
          checked={item.checked}
          action="toggleItem"
          payload={{ id: item.id }}
        />
        <Text
          tone={item.checked ? "tertiary" : "secondary"}
          lineClamp={1}
          strikethrough={item.checked}
        >
          {item.title}
        </Text>
        <Spacer />
        <IconButton
          symbol="trash"
          action="deleteItem"
          payload={{ id: item.id }}
          tone="secondary"
          size="large"
        />
      </Inline>
    </Row>
  );
}

export default function Widget({ environment, state, logger }) {
  const items = state?.items ?? [];
  logger.info(
    `render capture widget span=${environment.span} items=${items.length} draft=${state?.draft?.length ?? 0}`,
  );

  return (
    <Stack spacing={10}>
      <Input
        value={state?.draft ?? ""}
        placeholder="Press ↵ to capture another item"
        changeAction="changeDraft"
        submitAction="submitDraft"
      />

      <ScrollView spacing={8}>
        {items.map((item) => (
          <CaptureRow key={item.id} item={item} />
        ))}
      </ScrollView>
    </Stack>
  );
}
