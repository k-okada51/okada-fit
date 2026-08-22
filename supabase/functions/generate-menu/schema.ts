// `generate-menu`（FEAT-03）の入出力契約。
//
// 正本は `08_機能別詳細設計/FEAT-03_AIメニュー提案.md §3.2.2`・`§3.3`。
//
// **AI は `menu_id` と実施順だけを返す**（ADR-0021）。種目名もやり方も返させない。
// 渡した集合の中にしか ID が無いので、**幻覚が構造的に起きない。**

/// 部位（RULE-003）。5値のうち1つ。
export const BODY_PARTS = ['胸', '背中', '脚', '肩', '腕'] as const;

/// 1回の提案に載せる種目数の上限（ADR-0021・**確定**）。
export const MENU_MAX = 6;

/// 一度に渡せる器具の数（§3.3 `[仮]`）。
export const MACHINE_MAX = 10;

/// `reason` の文字数上限（§3.3 `[仮]`）。
export const REASON_MAX_LENGTH = 80;

/// 応答を待つ上限（§3.2 `[仮]`）。
///
/// NFR-PERF-03（≤15秒）から DB 照会と整形の余白を差し引いた値。
///
/// ⚠️ `analyze-meal` は 18 秒で 2回に1回超えた。こちらは画像を送らないぶん
/// 速いはずだが、**実測していない**。超えるようなら NFR ごと見直しになる。
export const GENERATE_MENU_TIMEOUT_MS = 13_000;

/// `generationConfig.response_schema` に載せる JSON Schema（§3.2.2）。
export const MENU_RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    menus: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          menu_id: { type: 'integer', description: '入力で渡した種目の ID' },
          order: { type: 'integer', description: '実施順。1 から始まる連番' },
          reason: {
            type: 'string',
            description: 'この順にした理由。日本語で80文字以内',
          },
        },
        required: ['menu_id', 'order', 'reason'],
      },
    },
  },
  required: ['menus'],
} as const;

/// 提案1件。
export interface SuggestedMenu {
  // deno-lint-ignore camelcase
  menu_id: number;
  order: number;
  reason: string;
}

/// プロンプトへ載せる種目1件。DB から解決したもの。
export interface MenuOption {
  menuId: number;
  menuName: string;
  /// その種目ができる器具の名前。複数ありうる（多対多・ADR-0021）。
  machineNames: string[];
}
