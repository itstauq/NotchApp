import { Button, Stack, Text, useLocalStorage } from "@skylane/api";

export default function Widget({ environment }) {
  const [count, setCount] = useLocalStorage("count", 0);

  console.info(`render hello widget span=${environment.span} count=${count}`);

  return (
    <Stack spacing={10}>
      <Text>Hello from Skylane</Text>
      <Text tone="secondary">{`Span ${environment.span} • Count ${count}`}</Text>
      <Button title="Increment" onClick={() => setCount((value) => value + 1)} />
    </Stack>
  );
}
