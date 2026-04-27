import * as React from "react";

import {
  Button,
  Card,
  CardContent,
  CardDescription,
  CardTitle,
  Divider,
  IconButton,
  Inline,
  Overlay,
  openURL,
  RoundedRect,
  ScrollView,
  Section,
  Spacer,
  Stack,
  Text,
  useEventCalendars,
  useEvents,
  useTheme,
} from "@skylane/api";

const DEFAULT_EVENT_COLOR = "#63ADFA";

function withAlpha(color, alpha) {
  if (typeof color !== "string") {
    return color;
  }

  const normalized = color.startsWith("#") ? color.slice(1) : color;
  if (normalized.length < 6) {
    return color;
  }

  return `#${normalized.slice(0, 6)}${alpha}`;
}

function endOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1);
}

function timePartsForEvent(event) {
  if (event.isAllDay) {
    return {
      time: "All Day",
      meridiem: "",
    };
  }

  const date = new Date(event.startMs);
  const formatter = new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
  const parts = formatter.formatToParts(date);
  const time = parts
    .filter(
      (part) =>
        part.type === "hour" ||
        part.type === "minute" ||
        part.type === "literal",
    )
    .map((part) => part.value)
    .join("")
    .trim();
  const meridiem =
    parts.find((part) => part.type === "dayPeriod")?.value?.toUpperCase() ?? "";

  return { time, meridiem };
}

function metaTextForEvent(event, calendarTitle) {
  const parts = [];

  if (event.location) {
    parts.push(event.location);
  }

  if (calendarTitle) {
    parts.push(calendarTitle);
  }

  return parts.join(" · ") || (event.isCurrent ? "Happening now" : "Upcoming");
}

function joinableURLForEvent(event) {
  for (const candidate of [event.url, event.location]) {
    if (typeof candidate !== "string") {
      continue;
    }

    const normalized = candidate.trim();
    if (normalized.startsWith("https://")) {
      return normalized;
    }
  }

  return undefined;
}

function getLayoutMetrics(span) {
  if (span >= 7) {
    return {
      sectionPaddingY: 2,
      rowPaddingY: 9,
      rowGap: 12,
      timeWidth: 44,
      timeSize: 13,
      meridiemSize: 10,
      titleSize: 12,
      metaSize: 11,
      markerHeight: 40,
    };
  }

  return {
    sectionPaddingY: 0,
    rowPaddingY: 8,
    rowGap: 10,
    timeWidth: 38,
    timeSize: 12,
    meridiemSize: 10,
    titleSize: 12,
    metaSize: 11,
    markerHeight: 38,
  };
}

function detailTimeText(event) {
  if (event.isAllDay) {
    return "All-day event";
  }

  const start = new Date(event.startMs);
  const end = new Date(event.endMs);
  const formatter = new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });

  return `${formatter.format(start)} - ${formatter.format(end)}`;
}

function PermissionState({ textColor, mutedColor, onRequestAccess }) {
  return (
    <Stack
      spacing={8}
      alignment="center"
      frame={{ maxWidth: Infinity, maxHeight: Infinity }}
    >
      <Text size={12} weight="semibold" alignment="center" color={textColor}>
        Connect Calendar
      </Text>
      <Text
        size={10}
        alignment="center"
        color={mutedColor}
        frame={{ maxWidth: 180 }}
      >
        Allow this widget to read your upcoming events.
      </Text>
      <Button
        title="Enable"
        variant="secondary"
        onClick={() => onRequestAccess("fullAccess")}
      />
    </Stack>
  );
}

function MessageState({ title, body, textColor, mutedColor }) {
  return (
    <Stack
      spacing={6}
      alignment="center"
      frame={{ maxWidth: Infinity, maxHeight: Infinity }}
    >
      <Text size={12} weight="semibold" alignment="center" color={textColor}>
        {title}
      </Text>
      <Text
        size={10}
        alignment="center"
        color={mutedColor}
        frame={{ maxWidth: 190 }}
      >
        {body}
      </Text>
    </Stack>
  );
}

function EventDetailsDialog({ event, colors, onClose, onJoin }) {
  const joinURL = joinableURLForEvent(event);

  return (
    <Overlay placement="center">
      <Card
        variant="accent"
        cornerRadius={18}
        fill={colors.card}
        strokeColor={withAlpha(colors.title, "1A")}
        frame={{ maxWidth: 228 }}
      >
        <ScrollView
          fadeEdges="both"
          frame={{ maxWidth: Infinity, maxHeight: 220 }}
        >
          <CardContent
            spacing={10}
            alignment="leading"
            padding={{ top: 14, leading: 14, trailing: 14, bottom: 14 }}
          >
            <Stack
              spacing={5}
              alignment="leading"
              frame={{ maxWidth: Infinity }}
            >
              <CardTitle lineClamp={2}>{event.title}</CardTitle>
              <CardDescription color={colors.meta}>
                {detailTimeText(event)}
              </CardDescription>
            </Stack>

            {event.location ? (
              <Stack
                spacing={3}
                alignment="leading"
                frame={{ maxWidth: Infinity }}
              >
                <Text size={10} weight="bold" color={colors.time}>
                  Location
                </Text>
                <Text size={11} color={colors.title}>
                  {event.location}
                </Text>
              </Stack>
            ) : null}

            {event.notes ? (
              <Stack
                spacing={3}
                alignment="leading"
                frame={{ maxWidth: Infinity }}
              >
                <Text size={10} weight="bold" color={colors.time}>
                  Notes
                </Text>
                <Text size={11} color={colors.title}>
                  {event.notes}
                </Text>
              </Stack>
            ) : null}

            <Inline
              alignment="center"
              spacing={8}
              frame={{ maxWidth: Infinity }}
            >
              <Spacer />
              {joinURL ? (
                <Button
                  title="Join"
                  variant="secondary"
                  width={56}
                  onClick={() => onJoin(joinURL)}
                />
              ) : null}
              <Button
                title="Close"
                variant="ghost"
                width={58}
                onClick={onClose}
              />
            </Inline>
          </CardContent>
        </ScrollView>
        <Overlay placement="top-end" inset="sm">
          <IconButton
            symbol="xmark"
            variant="subtle"
            size="small"
            iconSize={9}
            width={22}
            height={22}
            color={colors.close}
            onClick={onClose}
          />
        </Overlay>
      </Card>
    </Overlay>
  );
}

function ScheduleRow({ event, metrics, colors, onOpenEvent }) {
  const { time, meridiem } = timePartsForEvent(event);
  const joinURL = joinableURLForEvent(event);

  return (
    <Stack onPress={() => onOpenEvent(event)} frame={{ maxWidth: Infinity }}>
      <Inline
        alignment="start"
        spacing={metrics.rowGap}
        padding={{ top: metrics.rowPaddingY, bottom: metrics.rowPaddingY }}
        frame={{ maxWidth: Infinity }}
      >
        <Stack
          spacing={2}
          alignment="trailing"
          frame={{ width: metrics.timeWidth }}
        >
          <Text
            size={metrics.timeSize}
            weight="bold"
            color={colors.time}
            alignment="trailing"
            lineClamp={1}
            minimumScaleFactor={0.9}
          >
            {time}
          </Text>
          {meridiem ? (
            <Text
              size={metrics.meridiemSize}
              weight="semibold"
              color={colors.meridiem}
              alignment="trailing"
              lineClamp={1}
            >
              {meridiem}
            </Text>
          ) : null}
        </Stack>

        <RoundedRect
          fill={event.color}
          cornerRadius={999}
          frame={{ width: 4, height: metrics.markerHeight }}
        />

        <Stack spacing={4} alignment="leading" frame={{ maxWidth: Infinity }}>
          <Text
            size={metrics.titleSize}
            weight="semibold"
            color={colors.title}
            lineClamp={1}
          >
            {event.title}
          </Text>
          <Inline alignment="center" spacing={6} frame={{ maxWidth: Infinity }}>
            <Text
              size={metrics.metaSize}
              weight="medium"
              color={colors.meta}
              lineClamp={1}
            >
              {event.meta}
            </Text>
            <Spacer />
            {joinURL ? (
              <Button
                title="Join"
                variant="secondary"
                width={46}
                height={22}
                onClick={() => openURL(joinURL)}
              />
            ) : null}
          </Inline>
        </Stack>
      </Inline>
    </Stack>
  );
}

export default function Widget({ environment }) {
  const theme = useTheme();
  const calendars = useEventCalendars();
  const [selectedEventID, setSelectedEventID] = React.useState(null);
  const metrics = getLayoutMetrics(environment?.span ?? 4);
  const query = React.useMemo(() => {
    const now = new Date();
    return {
      startMs: now.getTime(),
      endMs: endOfDay(now).getTime(),
      includeAllDay: true,
      limit: 12,
    };
  }, []);
  const events = useEvents(query);
  const calendarById = React.useMemo(
    () => new Map(calendars.items.map((calendar) => [calendar.id, calendar])),
    [calendars.items],
  );
  const items = React.useMemo(
    () =>
      events.items.map((event) => {
        const calendar = calendarById.get(event.calendarID);
        return {
          ...event,
          color: calendar?.color ?? DEFAULT_EVENT_COLOR,
          title: event.title ?? "Untitled Event",
          meta: metaTextForEvent(event, calendar?.title),
        };
      }),
    [calendarById, events.items],
  );
  const colors = {
    card: theme.colors.card,
    time: withAlpha(theme.colors.foreground, "D6"),
    meridiem: withAlpha(theme.colors.foreground, "57"),
    title: withAlpha(theme.colors.foreground, "E6"),
    meta: withAlpha(theme.colors.foreground, "66"),
    divider: withAlpha(theme.colors.foreground, "14"),
    close: withAlpha(theme.colors.foreground, "A6"),
  };
  const handleOpenEvent = React.useCallback((event) => {
    setSelectedEventID(event.id);
  }, []);
  const handleOpenJoin = React.useCallback((url) => {
    openURL(url);
  }, []);
  const handleCloseDetails = React.useCallback(() => {
    setSelectedEventID(null);
  }, []);
  const selectedEvent = React.useMemo(
    () => items.find((event) => event.id === selectedEventID) ?? null,
    [items, selectedEventID],
  );

  let content;
  if (
    events.authorizationStatus === "notDetermined" ||
    events.authorizationStatus === "writeOnly"
  ) {
    content = (
      <PermissionState
        textColor={colors.title}
        mutedColor={colors.meta}
        onRequestAccess={events.requestAccess}
      />
    );
  } else if (
    events.authorizationStatus === "denied" ||
    events.authorizationStatus === "restricted"
  ) {
    content = (
      <MessageState
        title="Calendar Unavailable"
        body="Calendar access is disabled for Skylane in System Settings."
        textColor={colors.title}
        mutedColor={colors.meta}
      />
    );
  } else if (events.error) {
    content = (
      <MessageState
        title="Unable to Load Events"
        body={events.error.message || "Try refreshing the widget."}
        textColor={colors.title}
        mutedColor={colors.meta}
      />
    );
  } else if (!events.isLoading && items.length === 0) {
    content = (
      <MessageState
        title="No Events Today"
        body="Your calendar is clear for the rest of the day."
        textColor={colors.title}
        mutedColor={colors.meta}
      />
    );
  } else {
    content = (
      <ScrollView
        fadeEdges="bottom"
        frame={{ maxWidth: Infinity, maxHeight: Infinity }}
      >
        <Stack spacing={0} frame={{ maxWidth: Infinity }}>
          {items.map((event, index) => (
            <Stack key={event.id} spacing={0} frame={{ maxWidth: Infinity }}>
              <ScheduleRow
                event={event}
                metrics={metrics}
                colors={colors}
                onOpenEvent={handleOpenEvent}
              />
              {index < items.length - 1 ? (
                <Divider color={colors.divider} />
              ) : null}
            </Stack>
          ))}
          <Spacer minLength={18} />
        </Stack>
      </ScrollView>
    );
  }

  return (
    <Section
      padding={{
        top: metrics.sectionPaddingY,
        bottom: metrics.sectionPaddingY,
      }}
      frame={{ maxWidth: Infinity, maxHeight: Infinity }}
    >
      {content}
      {selectedEvent ? (
        <EventDetailsDialog
          event={selectedEvent}
          colors={colors}
          onClose={handleCloseDetails}
          onJoin={handleOpenJoin}
        />
      ) : null}
    </Section>
  );
}
