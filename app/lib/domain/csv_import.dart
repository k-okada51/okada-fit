/// 食事マスタCSVの読み取り（FEAT-10 §3・§4）。
///
/// **全て純関数である。** UI も Supabase も知らない。ネットワークに触れない。
/// 文字コード判定・パース・正規化・検証をここで終わらせ、
/// RPC には検証済み・正規化済みの行だけを渡す（§3.1）。
///
/// 検証が端末側にあるのは信頼境界の外である（§3.4）。
/// DB 側の砦は `foods.protein_amount` の `CHECK (>= 0)` と `uq_foods_name` の2つ。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';

import 'food.dart';

/// 受け付けるファイルサイズの上限（§3.3・1 MiB）。
///
/// **バイト列を読む前に判定する。** 読んでから弾いてもメモリは使い終わっている。
const kMaxCsvBytes = 1048576;

/// 受け付けるデータ行数の上限（ヘッダを除く・§3.3）。
const kMaxCsvDataRows = 1000;

/// 画面に出すエラー行の上限（§3.1）。超えた分は打ち切る。
const kMaxDisplayedRowErrors = 100;

/// 判定した文字コード（§4-1）。結果サマリに必ず出す。
///
/// 可視化するのは、誤判定に静かに取り込まれるのを利用者が気づけるようにするため。
/// Shift_JIS デコーダはほぼ任意のバイト列を受理してしまう（§10-4）。
enum CsvEncoding {
  utf8Bom('utf-8-bom', 'UTF-8（BOM付き）'),
  utf8Plain('utf-8', 'UTF-8'),
  shiftJis('shift_jis', 'Shift_JIS');

  const CsvEncoding(this.code, this.label);

  /// `detected_encoding` としてサマリに出す値。
  final String code;

  /// 画面に出す日本語。
  final String label;
}

/// デコードの結果。
class DecodedCsv {
  const DecodedCsv({required this.text, required this.encoding});

  /// デコード後の本文。BOM は含まない。
  final String text;

  /// 判定した文字コード。
  final CsvEncoding encoding;
}

/// ファイル全体の不備（§3.3）。行単位の不備（§3.4）とは別物である。
///
/// これが出た時点で取込は止まる。行の検証まで進まない。
///
/// ⚠️ **設計の ERR-ID が重複している。** §6 の表は ERR-FOOD-003 を「サイズ超過」、
/// ERR-FOOD-004 を「行数超過」、ERR-FOOD-006 を「ヘッダ不正」と定義する。
/// 一方 §7（2026-08-22 追加）の一覧編集の表は、同じ3つを「`name` 不正」
/// 「`protein_amount` 不正」「`uq_foods_name` 違反」に割り当てている。
/// **本実装は §6 の割り当てをこの enum に採り**、一覧編集側の ERR-ID は
/// `food.dart` のコメントに残すだけにした。編集の入力エラーは例外にせず
/// 画面に出すため、コードが ERR-ID を持つ必要が無いためである。
enum CsvFileError {
  /// ファイルサイズが上限超過（ERR-FOOD-003）。
  tooLarge('ERR-FOOD-003', 'ファイルが大きすぎます。1MB以内に分けてから取り込んでください。'),

  /// データ行が0件（ERR-FOOD-004）。
  noDataRows('ERR-FOOD-004', 'データ行がありません。ヘッダ行の下に1行以上入れてください。'),

  /// データ行が上限超過（ERR-FOOD-004）。
  tooManyRows('ERR-FOOD-004', 'データ行が多すぎます。$kMaxCsvDataRows行以内に分けてください。'),

  /// 対応する3つの文字コードで読めない（ERR-FOOD-005）。
  undecodable('ERR-FOOD-005', 'ファイルを読めませんでした。UTF-8 か Shift_JIS で保存し直してください。'),

  /// ヘッダ行が無い、または必須列が揃っていない（ERR-FOOD-006）。
  badHeader('ERR-FOOD-006', '1行目に「name,protein_amount」の見出しを入れてください。');

  const CsvFileError(this.code, this.message);

  /// ERR-ID。調査の手掛かりであり、画面には出さない。
  final String code;

  /// 利用者向け日本語。
  final String message;
}

/// パース結果の1行。
///
/// ⚠️ **設計との差**: §8 の `parseCsv` は `List<List<String>>` を返す形だが、
/// **物理行番号を一緒に返す形に変えた。** 引用符で囲んだセルは中に改行を持てるため
/// （§3.3・RFC 4180）、「何番目の行か」と「CSVファイル上の何行目か」がずれる。
/// エラー一覧の `line` は Excel の行番号と突き合わせる値である（§3.1）。
/// ずれたまま出すと利用者が該当行を探せない。
class CsvRow {
  const CsvRow({required this.line, required this.fields});

  /// CSVファイル上の物理行番号。**ヘッダ行が1**（§3.1）。
  final int line;

  /// セルの並び。引用符は外し、`""` は `"` に戻してある。
  final List<String> fields;

  /// 全列が空か。空行はエラーにせずスキップする（§3.3）。
  bool get isBlank => fields.every((field) => field.trim().isEmpty);
}

/// 行単位のエラー（§3.1）。この3点で1件を特定する。
class RowError {
  const RowError({
    required this.line,
    required this.column,
    required this.reason,
  });

  /// CSVファイル上の物理行番号（ヘッダ行＝1）。
  final int line;

  /// `name` ／ `protein_amount` ／ `-`。
  final String column;

  /// 理由（§3.4 の `reason_code`）。
  final FoodReason reason;

  /// 画面に出す1行。
  String get display => '$line行目 $column: ${reason.message}';
}

/// RPC へ送る1行。**検証済み・正規化済みである。**
class FoodRow {
  const FoodRow({required this.name, required this.proteinAmount});

  /// 正規化後の食品名（§4-5）。原文は送らないし保存もしない。
  final String name;

  /// 1食分あたりのタンパク質量(g)（ADR-0012）。小数第1位に丸め済み。
  final double proteinAmount;

  /// `p_rows` の要素（§3.2）。**キーは DB の列名そのまま。**
  Map<String, dynamic> toJson() => {
    'name': name,
    'protein_amount': proteinAmount,
  };
}

/// 取込前の検証結果（§3.1 の7段の出力）。
///
/// [fileError] が入っていれば行の検証まで進んでいない。
/// [errors] が1件でもあれば RPC を呼んではならない（ERR-FOOD-002）。
class FoodsCsvResult {
  const FoodsCsvResult._({
    this.fileError,
    this.encoding,
    this.rows = const [],
    this.errors = const [],
    this.warningLines = const [],
    this.skippedEmptyCount = 0,
    this.errorsTruncated = false,
    this.totalErrorCount = 0,
  });

  /// ファイル全体の不備で止まった。
  const FoodsCsvResult.failed(CsvFileError error, {CsvEncoding? encoding})
    : this._(fileError: error, encoding: encoding);

  /// ファイル全体は通り、行の検証まで終わった。
  const FoodsCsvResult.validated({
    required CsvEncoding encoding,
    required List<FoodRow> rows,
    required List<RowError> errors,
    required List<int> warningLines,
    required int skippedEmptyCount,
    required bool errorsTruncated,
    required int totalErrorCount,
  }) : this._(
         encoding: encoding,
         rows: rows,
         errors: errors,
         warningLines: warningLines,
         skippedEmptyCount: skippedEmptyCount,
         errorsTruncated: errorsTruncated,
         totalErrorCount: totalErrorCount,
       );

  /// ファイル全体の不備。無ければ `null`。
  final CsvFileError? fileError;

  /// 判定した文字コード。デコード前に止まった場合は `null`。
  final CsvEncoding? encoding;

  /// RPC へ送れる行。[errors] があるときは送らない。
  final List<FoodRow> rows;

  /// 行単位のエラー。画面表示用に [kMaxDisplayedRowErrors] 件で切ってある。
  final List<RowError> errors;

  /// 数式扱いされうる `name` の物理行番号（§4-4）。**取込は止めない。**
  final List<int> warningLines;

  /// 空行としてスキップした件数（`skipped_empty_count`）。
  final int skippedEmptyCount;

  /// [errors] を打ち切ったか。
  final bool errorsTruncated;

  /// 打ち切る前のエラー総数。
  final int totalErrorCount;

  /// RPC を呼んでよいか。
  bool get isReadyToSend =>
      fileError == null && errors.isEmpty && rows.isNotEmpty;
}

/// ファイルサイズの判定（§3.1 の2段）。**バイト列を読む前に呼ぶ。**
CsvFileError? checkCsvSize(int sizeBytes) =>
    sizeBytes > kMaxCsvBytes ? CsvFileError.tooLarge : null;

/// 拡張子の判定（§3.3）。`file_picker` の絞り込みをすり抜けた場合の保険。
bool isCsvFileName(String fileName) => fileName.toLowerCase().endsWith('.csv');

/// 文字コードを判定してデコードする（§4-1）。読めなければ `null`。
///
/// | # | 判定 | 結果 |
/// |---|---|---|
/// | 1 | 先頭3バイトが `EF BB BF` | `utf-8-bom`（BOMを除去して UTF-8） |
/// | 2 | `utf8.decode(bytes, allowMalformed: false)` が通る | `utf-8` |
/// | 3 | `shiftJis.decode(bytes)` が通る | `shift_jis` |
/// | 4 | いずれも失敗 | `null`（ERR-FOOD-005） |
///
/// **順序が肝である。** UTF-8 を厳密に試してから Shift_JIS へ落とす。
/// 逆順にすると Shift_JIS デコーダがほぼ何でも受理し、UTF-8 の日本語が
/// エラーにならないまま文字化けして取り込まれる（§4-1・§10-4）。
DecodedCsv? detectAndDecode(Uint8List bytes) {
  // 1. BOM 付き UTF-8。BOM を落としてから読む。
  //    落とさないと1列目のヘッダ名が `﻿name` になり、ヘッダ検証で落ちる。
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    try {
      return DecodedCsv(
        text: utf8.decode(bytes.sublist(3), allowMalformed: false),
        encoding: CsvEncoding.utf8Bom,
      );
    } on FormatException {
      // BOM を名乗っているのに UTF-8 として壊れている。
      // Shift_JIS へは落とさない。ファイル自体が壊れていると見る。
      return null;
    }
  }

  // 2. UTF-8（厳密）。`allowMalformed: false` にすることが判定の本体である。
  try {
    return DecodedCsv(
      text: utf8.decode(bytes, allowMalformed: false),
      encoding: CsvEncoding.utf8Plain,
    );
  } on FormatException {
    // 次へ。
  }

  // 3. Shift_JIS(CP932)。`charset` は純 Dart のため単体テストで確認できる（§4-1）。
  try {
    return DecodedCsv(
      text: shiftJis.decode(bytes),
      encoding: CsvEncoding.shiftJis,
    );
  } catch (_) {
    // 未定義のバイト列は `FormatException`、2バイト目が欠けた末尾は `RangeError`。
    // どちらも「読めない」で同じ扱いにする。型で分けても利用者に返す答えは変わらない。
    return null;
  }
}

/// RFC 4180 に沿ってパースする（§3.3）。
///
/// - 区切りは `,` のみ。TSV・セミコロン区切りは対象外。
/// - 改行は LF / CRLF。**CR単独は行の区切りにしない**（非対応・§3.3）。
/// - `"` で囲んだセルの中のカンマ・改行・`""` を復元する。
/// - **末尾の改行で空の行を作らない。** Excel が付ける最後の改行を空行に数えないため。
List<CsvRow> parseCsv(String text) {
  final rows = <CsvRow>[];
  final fields = <String>[];
  final field = StringBuffer();

  var line = 1; // いま読んでいる物理行
  var rowStart = 1; // 組み立て中の行の開始行
  var inQuotes = false;
  // 行の区切りより後に1文字でも読んだか。末尾の改行で空行を作らないための印。
  var pending = false;
  var index = 0;

  void endRow() {
    fields.add(field.toString());
    field.clear();
    rows.add(CsvRow(line: rowStart, fields: List<String>.of(fields)));
    fields.clear();
    pending = false;
  }

  while (index < text.length) {
    final ch = text[index];

    if (inQuotes) {
      if (ch == '"') {
        // `""` はセル内の `"` 1文字。閉じ引用符ではない。
        if (index + 1 < text.length && text[index + 1] == '"') {
          field.write('"');
          index += 2;
          continue;
        }
        inQuotes = false;
        index++;
        continue;
      }
      // 引用符の中の改行はセルの一部。行は区切らないが物理行は進む。
      if (ch == '\n') line++;
      field.write(ch);
      index++;
      continue;
    }

    // 引用符はセルの先頭でだけ開く。途中の `"` はただの文字として扱う。
    if (ch == '"' && field.isEmpty) {
      inQuotes = true;
      pending = true;
      index++;
      continue;
    }

    if (ch == ',') {
      fields.add(field.toString());
      field.clear();
      pending = true;
      index++;
      continue;
    }

    if (ch == '\r' && index + 1 < text.length && text[index + 1] == '\n') {
      endRow();
      index += 2;
      line++;
      rowStart = line;
      continue;
    }

    if (ch == '\n') {
      endRow();
      index++;
      line++;
      rowStart = line;
      continue;
    }

    // CR単独はここへ来る。行を区切らず、ただの文字として持つ（§3.3 非対応）。
    field.write(ch);
    pending = true;
    index++;
  }

  // 末尾に改行が無いまま終わった分だけ最後の行にする。
  // 改行で終わっていれば pending は false のままで、空の行は生まれない。
  if (pending) endRow();

  return rows;
}

/// ヘッダの正の列名と、Excel で人が作る想定のエイリアス（§3.3）。
const _nameHeaders = {'name', '食品名'};
const _proteinHeaders = {'protein_amount', 'タンパク質量'};

/// 数式として解釈されうる先頭文字（§4-4・CSVインジェクション）。
const _formulaPrefixes = {'=', '+', '@', '\t', '\r'};

/// 全行を検証する（§3.4）。**DBに触れない。2パスで全件を返す。**
///
/// 1行でも違反があれば呼び出し側は RPC を呼ばない（ERR-FOOD-002）。
/// どの行が悪いかを全部見せてから直させるため、最初の違反で止めない。
///
/// 正規化はこの中で1回だけ適用する。二重適用を避けるため、
/// [normalizeFoodName] を画面やリポジトリから呼ばない（§8）。
FoodsCsvResult validateFoodsCsv(List<CsvRow> rows, CsvEncoding encoding) {
  if (rows.isEmpty) {
    return const FoodsCsvResult.failed(CsvFileError.badHeader);
  }

  // ヘッダは1行目。列順はヘッダ名で解決する（§3.3・列取り違え防止）。
  final header = rows.first.fields
      .map((cell) => cell.trim().toLowerCase())
      .toList();
  // 2列ちょうどでないヘッダは受けない（§3.3 列構成）。
  if (header.length != 2) {
    return FoodsCsvResult.failed(CsvFileError.badHeader, encoding: encoding);
  }
  final nameIndex = header.indexWhere(_nameHeaders.contains);
  final proteinIndex = header.indexWhere(_proteinHeaders.contains);
  if (nameIndex < 0 || proteinIndex < 0 || nameIndex == proteinIndex) {
    return FoodsCsvResult.failed(CsvFileError.badHeader, encoding: encoding);
  }

  final dataRows = rows.skip(1).toList();
  final blankCount = dataRows.where((row) => row.isBlank).length;
  final filled = dataRows.where((row) => !row.isBlank).toList();

  // 上限・下限はどちらも空行を除いた件数で見る（§3.3）。
  if (filled.isEmpty) {
    return FoodsCsvResult.failed(CsvFileError.noDataRows, encoding: encoding);
  }
  if (filled.length > kMaxCsvDataRows) {
    return FoodsCsvResult.failed(CsvFileError.tooManyRows, encoding: encoding);
  }

  final foodRows = <FoodRow>[];
  final errors = <RowError>[];
  final warningLines = <int>[];
  // 同一ファイル内の重複判定。比較は正規化後の文字列で行う（§3.4）。
  final seenNames = <String>{};

  for (final row in filled) {
    // 列数はヘッダと同じ2列ちょうど。過不足はどちらも列の取り違えを招く。
    if (row.fields.length != 2) {
      errors.add(
        RowError(
          line: row.line,
          column: '-',
          reason: FoodReason.columnCountMismatch,
        ),
      );
      continue;
    }

    final rawName = row.fields[nameIndex];
    final rawProtein = row.fields[proteinIndex];

    // 数式扱いの警告は原文で見る。TAB・CR は正規化で消えてしまうため（§4-4）。
    if (rawName.isNotEmpty && _formulaPrefixes.contains(rawName[0])) {
      warningLines.add(row.line);
    }

    // 正規化してから検証する。長さも重複も正規化後の文字列で判定する（§3.1）。
    final name = normalizeFoodName(rawName);
    final nameReason = checkFoodName(name);
    if (nameReason != null) {
      errors.add(
        RowError(line: row.line, column: 'name', reason: nameReason),
      );
    } else if (!seenNames.add(name)) {
      // 2件目以降を重複として挙げる。**どちらを採るか決められないためエラーにする。**
      // 後勝ちで黙って捨てない（§3.4）。
      errors.add(
        RowError(
          line: row.line,
          column: 'name',
          reason: FoodReason.duplicateName,
        ),
      );
    }

    final proteinReason = checkProteinAmount(rawProtein);
    if (proteinReason != null) {
      errors.add(
        RowError(
          line: row.line,
          column: 'protein_amount',
          reason: proteinReason,
        ),
      );
    }

    // 妥当な行だけ積む。エラーが1件でもあれば呼び出し側が送信をやめる。
    if (nameReason == null && proteinReason == null) {
      foodRows.add(
        FoodRow(name: name, proteinAmount: parseProteinAmount(rawProtein)!),
      );
    }
  }

  final truncated = errors.length > kMaxDisplayedRowErrors;
  return FoodsCsvResult.validated(
    encoding: encoding,
    rows: foodRows,
    errors: truncated ? errors.sublist(0, kMaxDisplayedRowErrors) : errors,
    warningLines: warningLines,
    skippedEmptyCount: blankCount,
    errorsTruncated: truncated,
    totalErrorCount: errors.length,
  );
}

/// バイト列から検証結果までを一息で作る（§3.1 の2〜6段）。
///
/// 画面はこれ1本を呼ぶ。段ごとの関数も公開してあるのはテストのためである。
FoodsCsvResult prepareFoodsCsv(Uint8List bytes) {
  // サイズは選択時に見ているが、ここでも見る。呼び忘れても上限を破らせない。
  final tooLarge = checkCsvSize(bytes.length);
  if (tooLarge != null) return FoodsCsvResult.failed(tooLarge);

  final decoded = detectAndDecode(bytes);
  if (decoded == null) {
    return const FoodsCsvResult.failed(CsvFileError.undecodable);
  }

  return validateFoodsCsv(parseCsv(decoded.text), decoded.encoding);
}
