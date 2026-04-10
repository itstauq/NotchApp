import {
  Circle,
  Inline,
  Text,
  useTheme,
} from "@skylane/api";

/**
 * @param {{
 *   currentRoundNumber: number
 *   rounds: number
 *   labelSize: number
 *   dotSize: number
 *   dotGap: number
 *   spacing: number
 * }} props
 */
export function CycleProgress({
  currentRoundNumber,
  rounds,
  labelSize,
  dotSize,
  dotGap,
  spacing,
}) {
  const theme = useTheme();

  return (
    <Inline alignment="center" spacing={spacing}>
      <Text
        size={labelSize}
        weight="semibold"
        tone="tertiary"
        alignment="center"
        frame={{ maxWidth: null }}
        lineClamp={1}
        minimumScaleFactor={0.85}
      >
        {`Cycle ${currentRoundNumber} of ${rounds}`}
      </Text>

      <Inline alignment="center" spacing={dotGap}>
        {Array.from({ length: rounds }, (_, index) => (
          <Circle
            key={`${rounds}-${index}`}
            size={dotSize}
            fill={index < currentRoundNumber
              ? theme.colors.primary
              : theme.colors.border}
          />
        ))}
      </Inline>
    </Inline>
  );
}
