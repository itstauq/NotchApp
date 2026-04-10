const MIN_SPAN = 3;
const MAX_SPAN = 6;
const DENSE_DOT_THRESHOLD = 7;

// Each metric is anchored to the hand-tuned mock at the smallest supported
// layout and the most expanded layout, then interpolated for spans in between.
const LAYOUT_SCALE = Object.freeze({
  verticalInset: { span3: 4, span6: 7 },
  sectionSpacing: { span3: 16, span6: 22 },
  headerSpacing: { span3: 8, span6: 11 },
  cycleSize: { span3: 11, span6: 11.6 },
  stageSize: { span3: 12, span6: 12.8 },
  timerSize: { span3: 38, span6: 47 },
  controlsGap: { span3: 10, span6: 13 },
  primaryWidth: { span3: 68, span6: 92 },
  primaryHeight: { span3: 34, span6: 37 },
  primaryLabelSize: { span3: 12, span6: 12.9 },
  secondarySize: { span3: 34, span6: 37 },
  secondaryIconSize: { span3: 13, span6: 13.9 },
});

function spanProgress(span) {
  return (span - MIN_SPAN) / (MAX_SPAN - MIN_SPAN);
}

function interpolate({ span3, span6 }, progress) {
  return Number((span3 + ((span6 - span3) * progress)).toFixed(1));
}

export function getLayoutMetrics(span, rounds) {
  const normalizedSpan = Math.max(
    MIN_SPAN,
    Math.min(typeof span === "number" ? span : MIN_SPAN, MAX_SPAN)
  );
  const progress = spanProgress(normalizedSpan);
  const denseDots = rounds >= DENSE_DOT_THRESHOLD;

  // These values are tuned to the mock at span 3 and span 6, then interpolated between.
  return {
    verticalInset: interpolate(LAYOUT_SCALE.verticalInset, progress),
    sectionSpacing: interpolate(LAYOUT_SCALE.sectionSpacing, progress),
    headerSpacing: interpolate(LAYOUT_SCALE.headerSpacing, progress),
    cycleSize: interpolate(LAYOUT_SCALE.cycleSize, progress),
    stageSize: interpolate(LAYOUT_SCALE.stageSize, progress),
    timerSize: interpolate(LAYOUT_SCALE.timerSize, progress),
    dotSize: denseDots ? 5 : 6,
    dotGap: denseDots ? 3 : 4,
    controlsGap: interpolate(LAYOUT_SCALE.controlsGap, progress),
    primaryWidth: interpolate(LAYOUT_SCALE.primaryWidth, progress),
    primaryHeight: interpolate(LAYOUT_SCALE.primaryHeight, progress),
    primaryLabelSize: interpolate(LAYOUT_SCALE.primaryLabelSize, progress),
    secondarySize: interpolate(LAYOUT_SCALE.secondarySize, progress),
    secondaryIconSize: interpolate(LAYOUT_SCALE.secondaryIconSize, progress),
  };
}
