import {
  Button,
  IconButton,
  Inline,
  Section,
  Spacer,
  Stack,
  Text,
} from "@skylane/api";

import { CycleProgress } from "./cycle-progress";
import { getLayoutMetrics } from "./pomodoro-layout.mjs";
import { usePomodoroController } from "./use-pomodoro-controller.mjs";

function formatRemainingTime(remainingMs) {
  const totalSeconds = Math.max(0, Math.ceil(remainingMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

export default function Widget({ environment }) {
  const {
    currentRoundNumber,
    preferences,
    stageName,
    primaryLabel,
    remainingMs,
    handlePrimaryPress,
    handleResetCycle,
    handleSkipStep,
  } = usePomodoroController();
  const metrics = getLayoutMetrics(environment?.span, preferences.rounds);

  return (
    <Section
      alignment="center"
      spacing={metrics.sectionSpacing}
      padding={{
        top: metrics.verticalInset,
        bottom: metrics.verticalInset,
      }}
      frame={{ maxWidth: Infinity, maxHeight: Infinity, alignment: "center" }}
    >
      <Stack alignment="center" spacing={0} frame={{ maxWidth: Infinity, maxHeight: Infinity }}>
        <CycleProgress
          currentRoundNumber={currentRoundNumber}
          rounds={preferences.rounds}
          labelSize={metrics.cycleSize}
          dotSize={metrics.dotSize}
          dotGap={metrics.dotGap}
          spacing={metrics.headerSpacing}
        />

        <Spacer />

        <Text
          size={metrics.timerSize}
          weight="bold"
          design="monospaced"
          tone="primary"
          alignment="center"
          lineClamp={1}
          minimumScaleFactor={0.75}
        >
          {formatRemainingTime(remainingMs)}
        </Text>

        <Spacer />

        <Text
          size={metrics.stageSize}
          weight="semibold"
          tone="secondary"
          alignment="center"
          lineClamp={1}
          minimumScaleFactor={0.85}
        >
          {stageName}
        </Text>
      </Stack>

      <Inline alignment="center" spacing={metrics.controlsGap}>
        <Button
          title={primaryLabel}
          variant="default"
          size="lg"
          shape="pill"
          width={metrics.primaryWidth}
          height={metrics.primaryHeight}
          cornerRadius={metrics.primaryHeight / 2}
          fontSize={metrics.primaryLabelSize}
          weight="bold"
          onClick={handlePrimaryPress}
        />

        <IconButton
          symbol="arrow.counterclockwise"
          variant="secondary"
          width={metrics.secondarySize}
          height={metrics.secondarySize}
          iconSize={metrics.secondaryIconSize}
          onClick={handleResetCycle}
        />

        <IconButton
          symbol="forward.end.fill"
          variant="secondary"
          width={metrics.secondarySize}
          height={metrics.secondarySize}
          iconSize={metrics.secondaryIconSize}
          onClick={handleSkipStep}
        />
      </Inline>
    </Section>
  );
}
