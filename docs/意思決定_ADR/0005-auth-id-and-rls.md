---
status: draft
---

# ADR-0005: 認証IDを uuid に統一し RLS を `auth.uid()` 比較にする

> **目的**: 1つの設計決定を記録する雛形（1決定＝1ファイル）。本ファイルをコピーし `NNNN-短い決定名.md`（NNNN＝DEC番号のゼロ埋め）で起票する。
> **書き方**:（記入例は example-suido-fax の対応ファイル参照）実データは書かず、`{ }` を自プロジェクトの語に置き換える。**ステータスは `Proposed`（起票）→ `Accepted`（確定）→（必要時）`Superseded by ADR-NNNN`（後継で置換）** で遷移。決定を覆す場合は本ファイルを消さず、新ADRを起こして履歴を残す。確定後は要件・データモデル・アーキ等へ反映し、未決台帳のステータスを更新して初めてクローズ。

- **DEC-ID**: DEC-D03（認証方式）の未決部分を確定。`50_詳細設計/06_DB設計規約.md §4.2` の案A/B/C に対応
- **ステータス**: Accepted（岡田さん決定・2026-08-08）
- **日付**: 2026-08-08
- **決定者**: 岡田さん
- **前提TODO**: なし

## 背景・課題（Context）
> 📝 ここに何を・なぜ決める必要があるかを記載。関連する要件ID（FEAT/NFR/DM/IF/ST/ERR）を明記する。{決定が必要な理由／制約／前提}

- **対象要件**: NFR-SEC-01（本人以外を遮断）・FEAT-06（初期設定）。
- **決定が必要な理由**: ADR-0004 は本人分離を RLS で行うと決めた。しかし型が合わない。
- `users.id` は `bigint`（`01_DB物理設計.md §1.1`）。`auth.uid()` は `uuid` を返す。
- `user_id = auth.uid()` は `bigint = uuid` の比較になる。**RLSポリシーが1行も書けない。**
- **影響範囲**: `users` と、`user_id` を持つ履歴4表。
- 履歴4表＝`gym_visits` / `training_menus` / `training_sessions` / `meal_logs`（DM-01〜09）。
- **制約**: 実装は未着手。DDL はまだ Supabase に適用していない。
- **単一ユーザー運用では顕在化しない。** `users` の行が1件のため、どの案でも動いてしまう。
- FEAT-06 のサインアップ時に `users` 行を作る方式も `[仮]` のままだった。

## 選択肢（Options / Alternatives）
> 📝 ここに検討した案を記載（採用案・却下案の両方）。{案／概要／長所／短所}

| 案 | 概要 | 長所 | 短所 |
|---|---|---|---|
| **A（採用）** | `users.id` を uuid にし `auth.users(id)` を参照する | RLS が `user_id = auth.uid()` の最短形で書ける。Supabase の定石 | `users.id` と履歴4表の `user_id` を型変更する。INDEXサイズが増える |
| B | `users` に `auth_user_id uuid unique` 列を足す | 既存の bigint 型を維持できる。追加は1列 | 全ポリシーにサブクエリが入る。書き間違いが漏洩に直結する |
| C | RLS を使わず、アプリ側で `user_id` を絞る | 型の不一致が起きない | anon key は端末に埋め込まれる公開鍵。アプリ側の絞り込みは防御にならない |

## 決定（Decision）
> 📝 ここに採用案と、具体値・方式を実装が迷わない粒度で記載。{採用案／確定した具体値・方式}

案 **A** を採用する。`users.id` を uuid にして `auth.users.id` と一致させる。

### 型変更（正本は `01_DB物理設計.md`）

```sql
-- users は auth.users を親に持つ
CREATE TABLE users (
  id                    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name                  text NOT NULL,
  target_training_count int  NULL CHECK (target_training_count >= 0),
  weight_kg             float NULL CHECK (weight_kg > 0),
  created_at            timestamptz NOT NULL DEFAULT now()
);
```

- `users.id` に**自動採番は無い**。`auth.users.id` の値をそのまま使う。
- `user_id` が uuid になる表＝`gym_visits` / `training_menus` / `training_sessions` / `meal_logs`。
- **他テーブルの `id` は bigint のまま。** 変えるのは `users.id` と各 `user_id` だけ。
- `users.id` → `auth.users(id)` の FK は `ON DELETE CASCADE`。退会で本人データを消す。

### サインアップ時の行作成（トリガ）

FEAT-06 で暫定採用していた「案a: トリガ」を確定する。

```sql
CREATE FUNCTION handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.users (id, name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'name', ''));  -- [仮]
  RETURN NEW;
END; $$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION handle_new_user();
```

- `raw_user_meta_data` の扱いと `name` の既定値は `[仮]`。

### RLSポリシー（正本は `01_DB物理設計.md §3`）

3区分に分かれる。

| 区分 | テーブル | ポリシー |
|---|---|---|
| **本人のみ** | `users` | `id = auth.uid()` |
| | `training_menus` / `gym_visits` / `training_sessions` / `meal_logs` | `user_id = auth.uid()` |
| **共通マスタ** | `gyms` / `training_machines` / `foods` | `TO authenticated USING (true)` |
| **親経由** | `machine_menus` | `EXISTS (… training_menus m WHERE m.id = menu_id AND m.user_id = auth.uid())` |
| | `training_session_details` | `EXISTS (… training_sessions s WHERE s.id = session_id AND s.user_id = auth.uid())` |

- 全テーブルで `ALTER TABLE … ENABLE ROW LEVEL SECURITY` を必ず入れる。
- ポリシー名は `p_<テーブル名>_<用途>` とする（`06_DB設計規約.md §4.1`）。
- `FOR SELECT/INSERT/UPDATE/DELETE` の分割と `WITH CHECK` の細部は `[仮]`。

## 根拠（Rationale）
> 📝 ここになぜその案かを記載。トレードオフ・却下理由を明示する。{選定理由／却下した案の理由}

**案Aを採る理由**

| # | 理由 |
|---|---|
| 1 | RLS が `user_id = auth.uid()` の1行で書ける。読み違いが起きにくい |
| 2 | Supabase の標準構成に一致する。参考情報が多く、実装時に迷わない |
| 3 | 実装前なので型変更のコストは実質ゼロ。データ移行が発生しない |
| 4 | uuid で INDEX サイズは増える。本PJは行数が小さく影響が無視できる |

**案Bを却下した理由**

- 全テーブルの RLS でサブクエリが必要になる。
- 本構成では RLS が唯一の防御線になる（`06_DB設計規約.md §4.1`）。
- ポリシー1行の書き間違いが、そのままデータ漏洩になる。

**案Cを採れない理由**

- Supabase の anon key は端末に埋め込まれる公開鍵である。
- 鍵を取り出せば、誰でも PostgREST を直接叩ける。
- したがってアプリ側の絞り込みは防御にならない。RLS の代替にはできない。
- ADR-0004 の決定（RLSで本人分離）からも外れる。

## 影響（Consequences）
> 📝 ここに決定がもたらす影響を記載。{反映先ドキュメントの該当箇所／関連テスト観点／前提が崩れた場合の再検討条件}

- 反映先:
  - `02_設計/50_詳細設計/01_DB物理設計.md`（§1.1・§2 の型、§3 の DDL・RLS・トリガ）
  - `02_設計/30_データ・IF設計/01_データモデル.md`（識別子の型、§8 の該当論点を解決に）
  - `02_設計/50_詳細設計/06_DB設計規約.md §4.2`（案A採用で確定。§2 の識別子型に例外を追記）
  - `02_設計/50_詳細設計/08_機能別詳細設計/`: FEAT-01・FEAT-02・FEAT-03・FEAT-06
- **残る懸念**: ⚠️ 要確認（人間判断）: 共通マスタは認証済みなら誰でも書き換えられる。
  - 対象は `gyms` / `training_machines` / `foods` の3表。
  - 単一ユーザー運用では実害が無い。Phase2（NFR-SCALE-01）で見直しが要る。
- 関連テスト観点: TC-（サインアップでトリガが `users` 行を作ること／他人の行がRLSで見えないこと／`anon` ロールで一切読めないこと）
- 前提が崩れた場合の再検討条件: Supabase Auth 以外の認証へ移る場合。`auth.users` への FK が成立しなくなる。

## 反映チェック（クローズ条件）
> 📝 ここにクローズに必要なチェック項目を記載（確定後に消化する）。

- [ ] `01_DB物理設計.md` の `users.id` と履歴4表の `user_id` を uuid に更新
- [ ] `01_DB物理設計.md §3` に RLSポリシー3区分とサインアップトリガを反映
- [ ] `06_DB設計規約.md §4.2` を「案A採用」で確定し ⚠️ を解消
- [ ] `01_データモデル.md` の識別子型と §8 の該当論点を更新
- [ ] FEAT-01/02/03/06 の RLS 記述を `auth.uid()` 比較に統一
- [ ] 関連テスト観点を確認
