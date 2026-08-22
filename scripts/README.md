# 日次バックアップ（scripts/）

## これは何か

**Supabase の DB を毎日ローカルへ書き出す仕組み。** ADR-0017 の実装。

無料枠には**自動バックアップが無い。PITR も使えない。**
何もしなければ、障害が起きたときに戻す先が1つも無い。
このスクリプトが唯一の復元元を作る。

| 項目 | 値 |
|---|---|
| 手段 | `supabase db dump` |
| 頻度 | 日次（1日1回・12:30） |
| 実行元 | 岡田さんの Mac。launchd の定時ジョブ |
| 保管先 | `~/okada-fit-backups/`（**リポジトリの外**） |
| RPO | 24時間（NFR-AVAIL-02 を満たす） |

**プロジェクト停止の予防も兼ねる。** 無料枠は1週間 DB を触らないと一時停止する（ADR-0020）。
日次ジョブが毎日 DB へ接続するので、停止の判定に至りにくくなる。
ただし**保証ではない。** しきい値が非公開のため、効いているか確かめる手段が無い。
停止したらダッシュボードから再開する（ADR-0020 のとおり許容する）。

## ファイル

| ファイル | 役割 |
|---|---|
| `backup_db.sh` | 取得の本体。手でも launchd からも同じものを呼ぶ |
| `jp.co.classlab.okadafit.backup.plist` | launchd の定義。**雛形。パスを置き換えて使う** |
| `README.md` | この文書 |

## 前提

| # | 前提 | 確認方法 |
|---|---|---|
| 1 | **Docker Desktop が動いている** | `docker info` がエラーにならない |
| 2 | **Supabase CLI がある** | `~/.local/bin/supabase --version` |
| 3 | `supabase/.db-url` がある | `ls -l supabase/.db-url` |

`supabase db dump` は Docker を使う。**Docker Desktop が止まっていると取得できない。**
その場合はログに `Docker Desktop が起動していない` と残って終わる。無言では失敗しない。

> ⚠️ `supabase/.db-url` には**パスワードが入る**。中身を表示・共有・コミットしない。
> `supabase/.gitignore` で除外済み。

## 出力されるもの

`~/okada-fit-backups/` に、1回の実行で3本できる。

| ファイル | 中身 | 復元での役割 |
|---|---|---|
| `okada-fit-YYYYMMDD-HHMMSS-roles.sql` | ロール定義 | **別プロジェクトへ戻すときだけ**要る |
| `okada-fit-YYYYMMDD-HHMMSS-schema.sql` | `public` のテーブル・索引・関数・RLS ポリシー | 必須 |
| `okada-fit-YYYYMMDD-HHMMSS-data.sql` | データ（`public` と `auth` の両方） | 必須 |

- `data.sql` には **`auth.users` も入る。** ログインアカウントごと戻せる。
- 3本で1世代。**古い世代は自動で消える。保持は 14世代 `[仮]`**（＝約2週間）。
  変えるときは `backup_db.sh` の `KEEP_GENERATIONS`、または環境変数 `OKADAFIT_KEEP_GENERATIONS`。

### `.gitignore` について

**追記は不要。** 保管先 `~/okada-fit-backups/` はリポジトリの外にあるため、git の対象にならない。

> ⚠️ 保管先をリポジトリの中（例 `./backups/`）に変えないこと。
> エクスポートには食事・トレーニングの記録が入る。git に載ると取り消せない。
> どうしても変えるなら、先にリポジトリ直下の `.gitignore` へ追記する。

## 設置手順

### 1. 一度、手で実行する

保管先ディレクトリを作るため、**先に手で1回流す。**
ディレクトリが無いと launchd はジョブを起動できない。

```bash
cd <リポジトリのパス>
bash scripts/backup_db.sh
```

### 2. plist のプレースホルダを置き換える

雛形には2つのプレースホルダがある。

| プレースホルダ | 置き換える値 | 例 |
|---|---|---|
| `__HOME__` | ホームディレクトリの絶対パス | `/Users/okada` |
| `__REPO_DIR__` | このリポジトリの絶対パス | `/Users/okada/dev/okada-fit` |

置き換えと設置をまとめて行うコマンド。**リポジトリのルートで実行する。**

```bash
mkdir -p ~/Library/LaunchAgents
sed -e "s#__HOME__#$HOME#g" \
    -e "s#__REPO_DIR__#$PWD#g" \
    scripts/jp.co.classlab.okadafit.backup.plist \
    > ~/Library/LaunchAgents/jp.co.classlab.okadafit.backup.plist
```

置き換え漏れが無いか確認する。

```bash
plutil -lint ~/Library/LaunchAgents/jp.co.classlab.okadafit.backup.plist
grep -c '__' ~/Library/LaunchAgents/jp.co.classlab.okadafit.backup.plist   # 0 なら OK
```

### 3. 登録する

```bash
launchctl load ~/Library/LaunchAgents/jp.co.classlab.okadafit.backup.plist
launchctl list | grep okadafit    # 出れば登録できている
```

登録しただけでは走らない。次の 12:30 に動く。

> Mac がスリープや電源オフで 12:30 を過ぎた場合、launchd は**次に起動したとき1回だけ**実行する。
> ただし長期間 Mac を触らない間は取得されない。RPO 24時間が崩れる（ADR-0017 の残課題）。

## 動作確認

### 手で1回流す

```bash
cd <リポジトリのパス>
bash scripts/backup_db.sh
```

成功すると `バックアップ完了: ...` と出て、`~/okada-fit-backups/` に3本できる。

### launchd 経由で1回流す

時刻を待たずに、登録したジョブをその場で起動する。

```bash
launchctl start jp.co.classlab.okadafit.backup
```

**これが本番と同じ経路。** PATH の設定漏れはここで露見する。

### ログの見方

**まずこれを見る。** 1実行1行。

```bash
tail -20 ~/okada-fit-backups/backup.log
```

```
2026-08-22T12:30:22+0900	OK	okada-fit-20260822-123000 roles=4.0K schema=36K data=16K
2026-08-23T12:30:03+0900	FAIL	Docker Desktop が起動していない。起動してから再実行する
```

| 状態 | 意味 |
|---|---|
| `OK` | 取得できた。ファイル名とサイズが続く |
| `FAIL` | 取得できなかった。**理由が続く** |
| `PRUNE` | 古い世代を消した |

**定期的に最終行の日付を見る。** 数日空いていたら取得が止まっている。

うまく動かないときは launchd 側の生ログも見る。

```bash
tail -50 ~/okada-fit-backups/launchd.err.log
```

### よくある失敗

| ログの内容 | 原因 | 対処 |
|---|---|---|
| `Docker Desktop が起動していない` | Docker が止まっている | Docker Desktop を起動して再実行 |
| `Supabase CLI が無い` | パスが違う | `OKADAFIT_SUPABASE_BIN` で指定する |
| `接続情報が無い` | `supabase/.db-url` が無い | ファイルを置く |
| ログに何も出ない | plist のパスが違う | `launchd.err.log` を見る |

## 復元の手順

**取っただけでは意味が無い。** 戻せることまで確かめて初めて役に立つ。

まず、戻すファイルを決める。

```bash
ls -lt ~/okada-fit-backups/*-schema.sql | head
BK=~/okada-fit-backups/okada-fit-20260822-123000    # 末尾の -schema.sql を除いた形
```

### ケースA: 同じプロジェクトへ戻す（通常はこちら）

マイグレーション失敗・データ破損など。**ログインアカウント（`auth`）は生きている。**
戻すのは `public` だけ。

**1. 今の状態をもう一度取る。** これから消すので、戻れる場所を作っておく。

```bash
cd <リポジトリのパス>
bash scripts/backup_db.sh
```

**2. `public` を作り直す。**

> ⚠️ ここは破壊的。今の `public` のデータが全部消える。手順1を必ず先にやる。

```bash
psql "$(cat supabase/.db-url)" -v ON_ERROR_STOP=1 \
  -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'
```

`schema.sql` は `CREATE TABLE IF NOT EXISTS` で書き出される。
**古いテーブルが残っていると作り直されず、データが二重になる。** だから先に落とす。

**3. スキーマを戻す。**

```bash
psql "$(cat supabase/.db-url)" --single-transaction -v ON_ERROR_STOP=1 -f "$BK-schema.sql"
```

**4. データから `public` の分だけ取り出す。**

`data.sql` には `auth` のデータも入っている。
そのまま流すと、既にいる `auth.users` と衝突して失敗する。

```bash
{
  echo "SET session_replication_role = replica;"
  sed -n '/^COPY "public"\./,/^\\\.$/p' "$BK-data.sql"
  grep -E "^SELECT pg_catalog\.setval\('\"public\"" "$BK-data.sql"
} > "$BK-data-public.sql"
```

- 1行目の `session_replication_role = replica` で**外部キーを一時的に無効にする。**
  投入順を気にしなくてよくなる。
- `setval` の行は**連番の続きを戻す。** 落とすと次の登録で ID が衝突する。

取り出せたか確認する。`COPY` の数と `\.` の数が一致していれば正しい。

```bash
grep -c '^COPY ' "$BK-data-public.sql"
grep -c '^\\\.$' "$BK-data-public.sql"
```

**5. データを戻す。**

```bash
psql "$(cat supabase/.db-url)" --single-transaction -v ON_ERROR_STOP=1 -f "$BK-data-public.sql"
```

**6. 確認する。** アプリを開いて、記録が戻っているか見る。

### ケースB: まっさらな DB へ戻す

Mac の故障後の再構築、Supabase プロジェクトを作り直した場合など。
**`auth` を含めて丸ごと戻す。**

```bash
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 -f "$BK-roles.sql"
psql "$NEW_DB_URL" --single-transaction -v ON_ERROR_STOP=1 -f "$BK-schema.sql"
psql "$NEW_DB_URL" --single-transaction -v ON_ERROR_STOP=1 -f "$BK-data.sql"
```

- `roles.sql` は**このケースでだけ**使う。
- `data.sql` の先頭に `SET session_replication_role = replica;` が入っているので、
  ケースAのような取り出しは要らない。
- **新しいプロジェクトの `.db-url` に差し替える**のを忘れない。

### 復元のリハーサル

> ⚠️ 要確認（人間判断）: **リハーサルを1度行うこと**（ADR-0017 の反映チェック）。
> 本番へ流す前に、`supabase start` のローカル DB を相手に上の手順をなぞる。
> ローカルの接続先は `postgresql://postgres:postgres@127.0.0.1:54322/postgres`。
> 上の `psql "$(cat supabase/.db-url)"` をこれに置き換えるだけでよい。

> ⚠️ `psql` の版が DB より古いと失敗することがある。
> `psql --version` と Supabase 側（PostgreSQL 17）を見比べる。古ければ更新する。

## 止め方

```bash
launchctl unload ~/Library/LaunchAgents/jp.co.classlab.okadafit.backup.plist
```

完全にやめるなら plist も消す。

```bash
rm ~/Library/LaunchAgents/jp.co.classlab.okadafit.backup.plist
```

**止めるとバックアップは取られない。** 取っていない期間は復元できない。

plist を編集したときは、`unload` してから `load` し直す。

## 残っている課題（ADR-0017）

| # | 課題 | 状態 |
|---|---|---|
| 1 | **Mac が落ちている期間は取得されない** | 許容。ログの最終行で気づく |
| 2 | **保管先が手元の1箇所** | ⚠️ 未決。Mac の故障・紛失でバックアップも同時に失う |

課題2について。クラウド同期フォルダへ置くかは決まっていない。
**エクスポートには食事・トレーニングの記録が入る。**
NFR-SEC-06（必要以上に保存しない）と併せて判断する。
