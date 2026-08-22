// `generate-menu` — FEAT-03 今日のメニューを組む（EXT-01）。
//
// 正本は `08_機能別詳細設計/FEAT-03_AIメニュー提案.md`。
//
// ## AI に何をさせないか（ADR-0021）
//
// | AI が返すもの | AI が返さないもの |
// |---|---|
// | `menu_id`・実施順・理由 | 種目名・やり方・回数・重量 |
//
// **種目名を作らせない。** 登録済みの種目から `menu_id` で選ばせるだけなので、
// 存在しない種目を提案しようがない。幻覚が構造的に起きない。
//
// 提案は保存しない（§5）。画面の状態としてだけ持つ。

import { createClient } from 'jsr:@supabase/supabase-js@2';

import {
  AppError,
  jsonResponse,
  logJson,
  newCorrelationId,
  requireUserId,
  toErrorResponse,
} from '../_shared/errors.ts';
import { callGemini } from '../_shared/gemini.ts';
import { buildMenuPrompt, MENU_SYSTEM_INSTRUCTION } from './prompt.ts';
import {
  GENERATE_MENU_TIMEOUT_MS,
  MENU_RESPONSE_SCHEMA,
  MenuOption,
} from './schema.ts';
import {
  assertMenusConsistent,
  parseGenerateMenuRequest,
  parseSuggestedMenus,
  sortByOrder,
} from './validate.ts';

Deno.serve(async (req: Request) => {
  const correlationId = newCorrelationId();

  try {
    if (req.method !== 'POST') {
      throw new AppError('ERR-VALIDATION-001', 400, '不正なリクエストです。', false, req.method);
    }

    const authorization = req.headers.get('authorization');
    const actor = requireUserId(authorization);

    let body: unknown;
    try {
      body = await req.json();
    } catch (error) {
      throw new AppError('ERR-VALIDATION-001', 400, '入力を確認してください。', false, error);
    }
    const input = parseGenerateMenuRequest(body);

    // ② 種目一覧を DB から解決する。**AI は使わない**（RULE-004）。
    const options = await resolveMenuOptions(
      authorization!,
      input.machineIds,
      input.bodyPart,
    );

    logJson({
      level: 'info',
      event: 'external_send',
      action: '外部送信',
      target: 'EXT-01',
      actor,
      occurred_at: new Date().toISOString(),
      correlation_id: correlationId,
      model: Deno.env.get('GEMINI_MODEL') ?? '-',
      body_part: input.bodyPart,
      machine_count: input.machineIds.length,
      menu_count: options.length,
      result: 'sending',
    });

    // ③ 推論。画像は送らない（FEAT-08 だけ）。
    const { data } = await callGemini({
      parts: [{ text: buildMenuPrompt(input.bodyPart, options) }],
      systemInstruction: MENU_SYSTEM_INSTRUCTION,
      responseSchema: MENU_RESPONSE_SCHEMA,
      timeoutMs: GENERATE_MENU_TIMEOUT_MS,
      correlationId,
    });

    // ④ 型 → 集合との照合 → 並べ替え。**照合が ADR-0021 の要である。**
    const menus = parseSuggestedMenus(data);
    assertMenusConsistent(menus, new Set(options.map((o) => o.menuId)));

    return jsonResponse(200, { menus: sortByOrder(menus) });
  } catch (error) {
    return toErrorResponse(error, correlationId);
  }
});

/// `machine_ids` から、指定部位の種目一覧を解決する（§3.3・RULE-004）。
///
/// **呼び出し元の JWT でアクセスする。** service_role を使わない。
/// RLS がそのまま効くので、他人の器具を指定しても件数が合わずに弾かれる。
async function resolveMenuOptions(
  authorization: string,
  machineIds: number[],
  bodyPart: string,
): Promise<MenuOption[]> {
  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !anonKey) {
    throw new AppError(
      'ERR-AI-FAIL',
      500,
      'メニューを作れませんでした。もう一度お試しください。',
      false,
      'SUPABASE_URL / SUPABASE_ANON_KEY 未設定',
    );
  }

  const client = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });

  // 器具の実在と所有を見る。**RLS 経由の件数一致で判定する**（§3.3）。
  const { data: machines, error: machineError } = await client
    .from('training_machines')
    .select('id, name')
    .in('id', machineIds);
  if (machineError) throw wrapDbError(machineError);

  if ((machines?.length ?? 0) !== machineIds.length) {
    throw new AppError(
      'ERR-MENU-001',
      400,
      '選んだ器具が見つかりません。選び直してください。',
      false,
      `要求 ${machineIds.length} 件 / 参照できたのは ${machines?.length ?? 0} 件`,
    );
  }

  const machineNameById = new Map<number, string>(
    (machines ?? []).map((m) => [Number(m.id), String(m.name)]),
  );

  // 器具 → 種目（多対多）。指定部位の種目だけに絞る。
  const { data: links, error: linkError } = await client
    .from('machine_menus')
    .select('machine_id, menu_id, training_menus!inner(id, name, body_part)')
    .in('machine_id', machineIds)
    .eq('training_menus.body_part', bodyPart);
  if (linkError) throw wrapDbError(linkError);

  // 種目ごとに、使える器具の名前をまとめる。
  const byMenuId = new Map<number, MenuOption>();
  for (const row of links ?? []) {
    const menu = (row as Record<string, unknown>).training_menus as Record<string, unknown>;
    const menuId = Number(menu.id);
    const option = byMenuId.get(menuId) ??
      { menuId, menuName: String(menu.name), machineNames: [] };
    const machineName = machineNameById.get(Number(row.machine_id));
    if (machineName && !option.machineNames.includes(machineName)) {
      option.machineNames.push(machineName);
    }
    byMenuId.set(menuId, option);
  }

  const options = [...byMenuId.values()].sort((a, b) => a.menuId - b.menuId);

  // **1件も無ければ AI を呼ばない。** 呼んでも選ぶものが無く、課金だけ出る。
  if (options.length === 0) {
    throw new AppError(
      'ERR-MENU-002',
      400,
      '選んだ器具に、その部位の種目が登録されていません。',
      false,
      `body_part=${bodyPart} machines=${machineIds.length}`,
    );
  }

  return options;
}

function wrapDbError(error: unknown): AppError {
  return new AppError(
    'ERR-AI-FAIL',
    500,
    'メニューを作れませんでした。もう一度お試しください。',
    false,
    error,
  );
}
