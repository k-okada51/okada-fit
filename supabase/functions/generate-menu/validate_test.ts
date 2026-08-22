// `generate-menu` の純関数の単体テスト（NFR-QUAL-01）。
//
// ネットワークも Gemini も DB も使わない。**課金は一切発生しない。**
//
// 主役は `assertMenusConsistent`。**AI が返した `menu_id` が、こちらの渡した
// 集合の中にあるか**を照合する。この検査が ADR-0021 の要である。
// ここが緩むと、存在しない種目が画面に出る。
//
//   deno test supabase/functions/

import { assertEquals, assertThrows } from 'jsr:@std/assert@1';

import { AppError } from '../_shared/errors.ts';
import { MACHINE_MAX, MENU_MAX, SuggestedMenu } from './schema.ts';
import {
  assertMenusConsistent,
  parseGenerateMenuRequest,
  parseSuggestedMenus,
  sortByOrder,
} from './validate.ts';

function codeOf(fn: () => unknown): string {
  const error = assertThrows(fn, AppError);
  return (error as AppError).errorCode;
}

function menu(menuId: number, order: number): SuggestedMenu {
  return { menu_id: menuId, order, reason: 'テスト' };
}

Deno.test('リクエストの検証 — 正常系', () => {
  const parsed = parseGenerateMenuRequest({ body_part: '胸', machine_ids: [1, 2] });
  assertEquals(parsed.bodyPart, '胸');
  assertEquals(parsed.machineIds, [1, 2]);
});

Deno.test('ERR-VALIDATION-001 — body_part が RULE-003 の5値でない', () => {
  for (const value of ['腹', '', 'chest', 1, null, undefined]) {
    assertEquals(
      codeOf(() => parseGenerateMenuRequest({ body_part: value, machine_ids: [1] })),
      'ERR-VALIDATION-001',
      `value=${String(value)}`,
    );
  }
  // 5値は全部通る。
  for (const value of ['胸', '背中', '脚', '肩', '腕']) {
    assertEquals(
      parseGenerateMenuRequest({ body_part: value, machine_ids: [1] }).bodyPart,
      value,
    );
  }
});

Deno.test('ERR-VALIDATION-001 — machine_ids の空・型・上限・重複', () => {
  const bad = (ids: unknown) =>
    codeOf(() => parseGenerateMenuRequest({ body_part: '胸', machine_ids: ids }));

  assertEquals(bad([]), 'ERR-VALIDATION-001');
  assertEquals(bad('1,2'), 'ERR-VALIDATION-001');
  assertEquals(bad([1.5]), 'ERR-VALIDATION-001');
  assertEquals(bad([0]), 'ERR-VALIDATION-001');
  assertEquals(bad([-1]), 'ERR-VALIDATION-001');
  assertEquals(bad(['1']), 'ERR-VALIDATION-001');
  // 重複を許すと同じ器具の種目が二重に候補へ載る。
  assertEquals(bad([1, 1]), 'ERR-VALIDATION-001');
  // 上限。
  assertEquals(
    bad(Array.from({ length: MACHINE_MAX + 1 }, (_, i) => i + 1)),
    'ERR-VALIDATION-001',
  );
  // 上限ちょうどは通す。
  assertEquals(
    parseGenerateMenuRequest({
      body_part: '胸',
      machine_ids: Array.from({ length: MACHINE_MAX }, (_, i) => i + 1),
    }).machineIds.length,
    MACHINE_MAX,
  );
});

Deno.test('AI応答の型検証 — 正常系', () => {
  const menus = parseSuggestedMenus({
    menus: [
      { menu_id: 3, order: 2, reason: 'あとに補助種目' },
      { menu_id: 1, order: 1, reason: '大きな筋群を先に' },
    ],
  });
  assertEquals(menus.length, 2);
  assertEquals(menus[0].menu_id, 3);
});

Deno.test('ERR-AI-SCHEMA — 欠落・型違い・空', () => {
  assertEquals(codeOf(() => parseSuggestedMenus({})), 'ERR-AI-SCHEMA');
  assertEquals(codeOf(() => parseSuggestedMenus({ menus: [] })), 'ERR-AI-SCHEMA');
  assertEquals(codeOf(() => parseSuggestedMenus({ menus: 'x' })), 'ERR-AI-SCHEMA');
  assertEquals(
    codeOf(() => parseSuggestedMenus({ menus: [{ menu_id: '1', order: 1, reason: 'a' }] })),
    'ERR-AI-SCHEMA',
  );
  assertEquals(
    codeOf(() => parseSuggestedMenus({ menus: [{ menu_id: 1.5, order: 1, reason: 'a' }] })),
    'ERR-AI-SCHEMA',
  );
  assertEquals(
    codeOf(() => parseSuggestedMenus({ menus: [{ menu_id: 1, order: 'x', reason: 'a' }] })),
    'ERR-AI-SCHEMA',
  );
  assertEquals(
    codeOf(() => parseSuggestedMenus({ menus: [{ menu_id: 1, order: 1 }] })),
    'ERR-AI-SCHEMA',
  );
});

// --- ここから ADR-0021 の中心 ---

Deno.test('ERR-MENU-007 — 入力集合に無い menu_id を弾く（幻覚の遮断）', () => {
  const allowed = new Set([1, 2, 3]);
  // **99 は渡していない。** AI が作った ID である。参考情報として通さない。
  assertEquals(
    codeOf(() => assertMenusConsistent([menu(1, 1), menu(99, 2)], allowed)),
    'ERR-MENU-007',
  );
  // 集合内なら通る。
  assertMenusConsistent([menu(1, 1), menu(3, 2)], allowed);
});

Deno.test('ERR-MENU-007 — 同じ menu_id を2回返した', () => {
  const allowed = new Set([1, 2, 3]);
  assertEquals(
    codeOf(() => assertMenusConsistent([menu(1, 1), menu(1, 2)], allowed)),
    'ERR-MENU-007',
  );
});

Deno.test('ERR-MENU-007 — order が 1..N の連番でない', () => {
  const allowed = new Set([1, 2, 3]);
  // 欠番。
  assertEquals(
    codeOf(() => assertMenusConsistent([menu(1, 1), menu(2, 3)], allowed)),
    'ERR-MENU-007',
  );
  // 0 始まり。
  assertEquals(
    codeOf(() => assertMenusConsistent([menu(1, 0), menu(2, 1)], allowed)),
    'ERR-MENU-007',
  );
  // 重複。
  assertEquals(
    codeOf(() => assertMenusConsistent([menu(1, 1), menu(2, 1)], allowed)),
    'ERR-MENU-007',
  );
  // 順不同でも 1..N が揃っていれば通る。並べ替えは sortByOrder が行う。
  assertMenusConsistent([menu(1, 2), menu(2, 1)], allowed);
});

Deno.test('ERR-MENU-007 — 件数が MENU_MAX を超える', () => {
  const allowed = new Set(Array.from({ length: 10 }, (_, i) => i + 1));
  const tooMany = Array.from({ length: MENU_MAX + 1 }, (_, i) => menu(i + 1, i + 1));
  assertEquals(codeOf(() => assertMenusConsistent(tooMany, allowed)), 'ERR-MENU-007');
  // ちょうどは通す。
  const exact = Array.from({ length: MENU_MAX }, (_, i) => menu(i + 1, i + 1));
  assertMenusConsistent(exact, allowed);
  assertEquals(MENU_MAX, 6);
});

Deno.test('ERR-MENU-007 — 利用者向け文言に menu_id を出さない', () => {
  const error = assertThrows(
    () => assertMenusConsistent([menu(99, 1)], new Set([1])),
    AppError,
  ) as AppError;
  // 技術詳細は detail（ログ）にだけ入れる（02_API設計.md §5.1）。
  assertEquals(error.userMessage.includes('99'), false);
  assertEquals(error.retryable, false, '同じ入力で再送しても直らない');
});

Deno.test('応答は order 昇順で返す', () => {
  const sorted = sortByOrder([menu(5, 3), menu(1, 1), menu(3, 2)]);
  assertEquals(sorted.map((m) => m.order), [1, 2, 3]);
  assertEquals(sorted.map((m) => m.menu_id), [1, 3, 5]);
});
