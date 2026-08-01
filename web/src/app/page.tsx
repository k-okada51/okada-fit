'use client';

import {
  Container,
  Title,
  Text,
  Card,
  RingProgress,
  Center,
  Stack,
  Button,
  Group,
  Badge,
} from '@mantine/core';

// 動作確認用の仮ホーム。Claude Design のモックが届いたら差し替える。
export default function Home() {
  return (
    <Container size="xs" py="xl">
      <Stack gap="lg">
        <div>
          <Text c="dimmed" size="sm">
            🔥 セットアップ完了
          </Text>
          <Title order={2}>okada-fit</Title>
          <Text c="dimmed" size="sm">
            Next.js + Mantine の受け皿ができました
          </Text>
        </div>

        <Card withBorder radius="lg" padding="lg">
          <Center>
            <RingProgress
              size={160}
              thickness={16}
              roundCaps
              sections={[{ value: 73, color: 'teal' }]}
              label={
                <Center>
                  <Stack gap={0} align="center">
                    <Text fw={700} size="xl">
                      あと 32g
                    </Text>
                    <Text c="dimmed" size="xs">
                      目標 120g / 摂取 88g
                    </Text>
                  </Stack>
                </Center>
              }
            />
          </Center>
        </Card>

        <Button size="lg" radius="md" fullWidth>
          ＋ 食事を記録
        </Button>

        <Group justify="center">
          <Badge color="teal" variant="light">
            Mantine 動作OK
          </Badge>
        </Group>
      </Stack>
    </Container>
  );
}
