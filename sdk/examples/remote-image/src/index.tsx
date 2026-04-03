import { Image, RoundedRect, Stack, Text } from "@notchapp/api";

const REMOTE_IMAGE_URL = "https://placehold.co/224x112/png?text=Remote+Image";

export default function Widget() {
  return (
    <Stack spacing={10}>
      <RoundedRect
        fill="#0f172a"
        frame={{ maxWidth: "infinity", height: 112 }}
        clipShape={{ type: "roundedRect", cornerRadius: 18 }}
      >
        <Image src={REMOTE_IMAGE_URL} contentMode="fit" />
      </RoundedRect>
      <Text>Remote image</Text>
      <Text tone="secondary">Host-fetched over HTTPS</Text>
    </Stack>
  );
}
