import { Camera, Circle, Icon, RoundedRect } from "@notchapp/api";

function CameraOverlayBadge({ symbol, padding }) {
  return (
    <RoundedRect
      cornerRadius={10}
      fill="#00000047"
      width={28}
      height={24}
      padding={padding}
    >
      <Icon symbol={symbol} size={10} opacity={0.82} />
    </RoundedRect>
  );
}

export default function Widget() {
  return (
    <Camera
      frame={{ maxWidth: Infinity, maxHeight: Infinity }}
      clipShape={{ type: "roundedRect", cornerRadius: 16 }}
      background="#1e232b"
      overlay={[
        {
          alignment: "topTrailing",
          node: <CameraOverlayBadge symbol="gearshape.fill" padding={12} />,
        },
        {
          alignment: "bottomTrailing",
          node: <CameraOverlayBadge symbol="photo.badge.plus" padding={12} />,
        },
        {
          alignment: "bottomLeading",
          node: <CameraOverlayBadge symbol="waveform" padding={12} />,
        },
        {
          alignment: "topTrailing",
          node: (
            <Circle
              size={170}
              fill="#FFFFFF08"
              pointerEvents="none"
              padding={{ top: -34, trailing: -34 }}
            />
          ),
        },
      ]}
    />
  );
}
