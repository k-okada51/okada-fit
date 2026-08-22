#!/usr/bin/env bash
#
# okada-fit 日次バックアップ（ADR-0017）
#
# Supabase 無料枠には自動バックアップも PITR も無い。
# このスクリプトが唯一の復元元を作る。
# launchd から1日1回呼ばれる。手順は scripts/README.md を見る。
#
# 出力は3本。復元にはこの3本が要る（Supabase 公式の推奨構成）。
#   okada-fit-YYYYMMDD-HHMMSS-roles.sql   ロール定義
#   okada-fit-YYYYMMDD-HHMMSS-schema.sql  スキーマ（DDL）
#   okada-fit-YYYYMMDD-HHMMSS-data.sql    データ（COPY 形式）
#
# 注意: 接続文字列にはパスワードが入る。標準出力・ログには絶対に出さない。

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# 設定
# ---------------------------------------------------------------------------

# launchd は対話シェルの PATH を継承しない。ここで明示する。
# Supabase CLI は ~/.local/bin、docker は /usr/local/bin にある。
export PATH="${HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# リポジトリの位置。scripts/ の1つ上。環境変数で上書きできる。
REPO_DIR="${OKADAFIT_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# 保管先は必ずリポジトリの外。中に置くと git に載る危険がある。
BACKUP_DIR="${OKADAFIT_BACKUP_DIR:-${HOME}/okada-fit-backups}"

# 残す世代数。[仮] 14世代（＝2週間分）。運用してみて増減する。
KEEP_GENERATIONS="${OKADAFIT_KEEP_GENERATIONS:-14}"

DB_URL_FILE="${REPO_DIR}/supabase/.db-url"
SUPABASE_BIN="${OKADAFIT_SUPABASE_BIN:-${HOME}/.local/bin/supabase}"
LOG_FILE="${BACKUP_DIR}/backup.log"

# ---------------------------------------------------------------------------
# ログ
# ---------------------------------------------------------------------------

mkdir -p "${BACKUP_DIR}"

# ログは1実行1行。日時 / 状態 / 内容 のタブ区切り。
log() {
  printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "$2" >>"${LOG_FILE}"
}

# 接続文字列を伏せる。CLI のエラー文に混ざることがあるため必ず通す。
redact() {
  sed -E 's#postgres(ql)?://[^[:space:]]*#<接続文字列は伏せた>#g'
}

FAILING=0
fail() {
  if [ "${FAILING}" -eq 0 ]; then
    FAILING=1
    log "FAIL" "$1"
  fi
  printf 'backup_db.sh: %s\n' "$1" >&2
  exit 1
}

TMP_OUT="$(mktemp -t okadafit-backup)"
trap 'rm -f "${TMP_OUT}"' EXIT
# 想定外の失敗も握り潰さずログに残す。
trap 'fail "予期しないエラー（${BASH_SOURCE[0]}:${LINENO}）"' ERR

# ---------------------------------------------------------------------------
# 事前チェック
# ---------------------------------------------------------------------------

if [ ! -s "${DB_URL_FILE}" ]; then
  fail "接続情報が無い: supabase/.db-url が見つからないか空（REPO_DIR=${REPO_DIR}）"
fi

if [ ! -x "${SUPABASE_BIN}" ]; then
  fail "Supabase CLI が無い: ${SUPABASE_BIN}"
fi

if ! command -v docker >/dev/null 2>&1; then
  fail "docker コマンドが無い。Docker Desktop を入れる"
fi

# supabase db dump は Docker を使う。起動していなければここで止まる。
# 無言で失敗させない。未起動だったことをログに残す。
if ! docker info >/dev/null 2>&1; then
  fail "Docker Desktop が起動していない。起動してから再実行する"
fi

# ---------------------------------------------------------------------------
# 取得
# ---------------------------------------------------------------------------

STAMP="$(date '+%Y%m%d-%H%M%S')"
PREFIX="okada-fit-${STAMP}"

# 変数に入れるだけ。表示もログ出力もしない。
DB_URL="$(cat "${DB_URL_FILE}")"

F_ROLES="${BACKUP_DIR}/${PREFIX}-roles.sql"
F_SCHEMA="${BACKUP_DIR}/${PREFIX}-schema.sql"
F_DATA="${BACKUP_DIR}/${PREFIX}-data.sql"

# supabase link は CLI の不具合で通らない。毎回 --db-url を明示する。
# この URL はプーラー経由。この回線は IPv6 非対応で直接接続が通らないため。
run_dump() {
  local label="$1" out="$2"
  shift 2
  if ! "${SUPABASE_BIN}" db dump \
      --workdir "${REPO_DIR}" \
      --db-url "${DB_URL}" \
      -f "${out}" \
      "$@" >"${TMP_OUT}" 2>&1; then
    local msg
    msg="$(redact <"${TMP_OUT}" | tr '\n' ' ' | cut -c1-300)"
    fail "${label}の取得に失敗: ${msg}"
  fi
  if [ ! -s "${out}" ]; then
    fail "${label}の出力が空: $(basename "${out}")"
  fi
}

# 1. ロール。別プロジェクトへ復元するときに要る。
run_dump "ロール" "${F_ROLES}" --role-only
# 2. スキーマ。--data-only を付けない既定の dump が DDL になる。
run_dump "スキーマ" "${F_SCHEMA}"
# 3. データ。--use-copy で COPY 形式にする。INSERT より速く小さい。
run_dump "データ" "${F_DATA}" --data-only --use-copy

# ---------------------------------------------------------------------------
# 世代の削除
# ---------------------------------------------------------------------------

# 世代は -schema.sql の本数で数える。新しい順に KEEP_GENERATIONS 本を残す。
prune_old() {
  local n=0 f stamp
  find "${BACKUP_DIR}" -maxdepth 1 -name 'okada-fit-*-schema.sql' -type f \
    | sort -r \
    | while read -r f; do
        n=$((n + 1))
        if [ "${n}" -le "${KEEP_GENERATIONS}" ]; then
          continue
        fi
        stamp="$(basename "${f}" -schema.sql)"
        # その世代の .sql をまとめて消す。復元作業で作った派生ファイルも一緒に片付く。
        rm -f "${BACKUP_DIR}/${stamp}"-*.sql
        log "PRUNE" "${stamp} を削除（保持 ${KEEP_GENERATIONS} 世代）"
      done
}

prune_old

# ---------------------------------------------------------------------------
# 記録
# ---------------------------------------------------------------------------

size_of() {
  du -h "$1" | cut -f1 | tr -d ' '
}

log "OK" "${PREFIX} roles=$(size_of "${F_ROLES}") schema=$(size_of "${F_SCHEMA}") data=$(size_of "${F_DATA}")"

printf 'バックアップ完了: %s\n' "${BACKUP_DIR}/${PREFIX}-*.sql"
