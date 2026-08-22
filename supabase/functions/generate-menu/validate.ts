// `generate-menu` の検証。**純関数だけを置く**（`validate_test.ts` の対象）。
//
// `fetch` も `Deno.env` も DB も触らない。
//
// ここの主役は [assertMenusConsistent] である。**AI が返した `menu_id` が、
// こちらの渡した集合の中にあるか**を照合する（ADR-0021・§4 L6）。
// この照合があるから、幻覚した種目が画面に出ることが構造的に起きない。

import { AppError } from '../_shared/errors.ts';
import {
  BODY_PARTS,
  MACHINE_MAX,
  MENU_MAX,
  SuggestedMenu,
} from './schema.ts';

export interface GenerateMenuRequest {
  bodyPart: string;
  machineIds: number[];
}

/// リクエストを読む（§3.3）。違反は ERR-VALIDATION-001（400）。
export function parseGenerateMenuRequest(body: unknown): GenerateMenuRequest {
  const record = (body ?? {}) as Record<string, unknown>;

  const bodyPart = record.body_part;
  if (typeof bodyPart !== 'string' || !(BODY_PARTS as readonly string[]).includes(bodyPart)) {
    throw validationError(`body_part=${String(bodyPart)}`);
  }

  const raw = record.machine_ids;
  if (!Array.isArray(raw) || raw.length === 0) {
    throw validationError('machine_ids が空、または配列でない');
  }
  if (raw.length > MACHINE_MAX) {
    throw validationError(`machine_ids が ${raw.length} 件（上限 ${MACHINE_MAX}）`);
  }

  const machineIds: number[] = [];
  for (const value of raw) {
    if (typeof value !== 'number' || !Number.isInteger(value) || value <= 0) {
      throw validationError('machine_ids に整数でない値がある');
    }
    // 重複を許すと、同じ器具の種目が二重に候補へ載る。
    if (machineIds.includes(value)) {
      throw validationError(`machine_ids に重複がある: ${value}`);
    }
    machineIds.push(value);
  }

  return { bodyPart, machineIds };
}

/// AI 応答の型を見る（ERR-AI-SCHEMA・502）。
///
/// **型だけ。** 集合との照合は [assertMenusConsistent] が別に行う。
/// ERR-ID が違う（502 は同じだが原因が違い、ログに残す内容も違う）。
export function parseSuggestedMenus(data: unknown): SuggestedMenu[] {
  const record = (data ?? {}) as Record<string, unknown>;
  const menus = record.menus;
  if (!Array.isArray(menus)) throw schemaError('menus が配列でない');
  if (menus.length === 0) throw schemaError('menus が空');

  const result: SuggestedMenu[] = [];
  for (const item of menus) {
    const row = (item ?? {}) as Record<string, unknown>;
    const menuId = row.menu_id;
    const order = row.order;
    const reason = row.reason;
    if (typeof menuId !== 'number' || !Number.isInteger(menuId)) {
      throw schemaError('menu_id が整数でない');
    }
    if (typeof order !== 'number' || !Number.isInteger(order)) {
      throw schemaError('order が整数でない');
    }
    if (typeof reason !== 'string') throw schemaError('reason が文字列でない');
    result.push({ menu_id: menuId, order, reason });
  }
  return result;
}

/// **入力集合との照合**（ERR-MENU-007・502・§4 L6）。
///
/// 3つを見る。どれも「AI が勝手なことをしていないか」の検査である。
///
/// | 検査 | なぜ要るか |
/// |---|---|
/// | `menu_id` が入力集合に在るか | **幻覚した種目を通さない**（ADR-0021 の中心） |
/// | `menu_id` が重複していないか | 同じ種目を2回やらせない |
/// | `order` が `1..N` の連番か | 実施順として使えない並びを通さない |
///
/// 件数上限（[MENU_MAX]）もここで見る。`response_schema` では表せない。
export function assertMenusConsistent(
  menus: SuggestedMenu[],
  allowedMenuIds: Set<number>,
): void {
  if (menus.length > MENU_MAX) {
    throw menuError(`menus が ${menus.length} 件（上限 ${MENU_MAX}）`);
  }

  const seen = new Set<number>();
  for (const menu of menus) {
    if (!allowedMenuIds.has(menu.menu_id)) {
      // **集合外の ID。** 参考情報として通さない。
      throw menuError(
        `集合外の menu_id。返答 ${menus.length} 件 / 入力集合 ${allowedMenuIds.size} 件`,
      );
    }
    if (seen.has(menu.menu_id)) {
      throw menuError(`menu_id が重複。返答 ${menus.length} 件`);
    }
    seen.add(menu.menu_id);
  }

  // `1..N` の連番。欠番も重複も弾く。
  const orders = menus.map((m) => m.order).sort((a, b) => a - b);
  for (let i = 0; i < orders.length; i++) {
    if (orders[i] !== i + 1) {
      throw menuError(`order が 1..${menus.length} の連番でない`);
    }
  }
}

/// 実施順で並べ替える。応答は `order` 昇順で返す（§3.1）。
export function sortByOrder(menus: SuggestedMenu[]): SuggestedMenu[] {
  return [...menus].sort((a, b) => a.order - b.order);
}

function validationError(detail: string): AppError {
  return new AppError(
    'ERR-VALIDATION-001',
    400,
    '入力を確認してください。',
    false,
    detail,
  );
}

function schemaError(detail: string): AppError {
  return new AppError(
    'ERR-AI-SCHEMA',
    502,
    'メニューを作れませんでした。もう一度お試しください。',
    false,
    detail,
  );
}

function menuError(detail: string): AppError {
  return new AppError(
    'ERR-MENU-007',
    502,
    'メニューを作れませんでした。もう一度お試しください。',
    false,
    detail,
  );
}
