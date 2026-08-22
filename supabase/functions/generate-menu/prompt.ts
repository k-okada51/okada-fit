// `generate-menu` のプロンプト（FEAT-03 §3.2.1）。
//
// 設計は「含める要素」を表で示すだけで本文を持たない。本文はここが正本。

import { MENU_MAX, MenuOption, REASON_MAX_LENGTH } from './schema.ts';

/// 役割と制約（`systemInstruction`）。
///
/// **一覧に無い種目を足させない**のがこの文の全ての目的である（ADR-0021）。
/// 自重種目を足す余地を残すと、器具0件でも生成できてしまい、EXT-01 の課金
/// だけが発生する（FEAT-02 §10 #1）。
export const MENU_SYSTEM_INSTRUCTION = [
  'あなたは筋力トレーニングの指導者です。出力は日本語で行います。',
  '与えられた種目一覧の中から、今日そのまま実施できる組み合わせを選びます。',
  '**一覧に無い種目を足してはいけません。** 自重種目も足してはいけません。',
  `選ぶのは最大 ${MENU_MAX} 件です。少なくても構いません。`,
  '選んだ種目には 1 から始まる連番で実施順を付けます。欠番も重複も作りません。',
  '順序は、大きな筋群を使う種目を先に、補助的な種目を後にします。',
  `reason には、その順にした理由を ${REASON_MAX_LENGTH} 文字以内で書きます。`,
  'menu_id は与えられた ID をそのまま使います。新しい ID を作ってはいけません。',
].join('\n');

/// 利用者の入力（`contents[0].parts[0].text`）。
///
/// **`menu_id` を必ず添える**（§3.2.1）。AI が返すのはこの ID だけである。
export function buildMenuPrompt(bodyPart: string, options: MenuOption[]): string {
  const lines = options.map(
    (o) =>
      `- menu_id=${o.menuId} / 種目=${o.menuName} / 使う器具=${
        o.machineNames.length === 0 ? '（未登録）' : o.machineNames.join('・')
      }`,
  );

  return [
    `今日鍛える部位: ${bodyPart}`,
    '',
    '実施できる種目の一覧:',
    ...lines,
    '',
    'この一覧の中から今日の組み合わせを選び、実施順を付けてください。',
  ].join('\n');
}
