import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:okada_fit/domain/csv_import.dart';
import 'package:okada_fit/domain/food.dart';

/// 食事マスタCSVインポート（W-10・FEAT-10）の単体テスト。
///
/// ネットワークを使わない。Supabase の初期化もしない。
/// 見るのは `domain/csv_import.dart` と `domain/food.dart` の純関数だけである。
///
/// 確かめたいのは2点。
/// 1. **Excel が吐く現実のCSVを読めるか。** BOM・Shift_JIS・CRLF・末尾改行。
/// 2. **DB の制約と同じ規則を、送信前に Dart 側で弾けているか。**
///    DB は最後の防波堤であって、そこへ到達させない。
void main() {
  /// UTF-8（BOM無し）のバイト列にする。
  Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));

  /// UTF-8（BOM付き）のバイト列にする。Excel の「UTF-8 CSV」がこれ。
  Uint8List utf8BomBytes(String text) =>
      Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);

  /// Shift_JIS のバイト列にする。Excel の既定の「CSV」がこれ。
  Uint8List shiftJisBytes(String text) =>
      Uint8List.fromList(shiftJis.encode(text));

  group('1. 文字コードの判定とデコード（§4-1）', () {
    const csv = 'name,protein_amount\n鶏むね肉,25.0\n';

    test('UTF-8（BOM無し）を読める（TC-FEAT10-01）', () {
      final decoded = detectAndDecode(utf8Bytes(csv));
      expect(decoded, isNotNull);
      expect(decoded!.encoding, CsvEncoding.utf8Plain);
      expect(decoded.text, csv);
    });

    test('UTF-8（BOM付き）を読める。BOM はヘッダ名に混入しない（TC-FEAT10-02）', () {
      final decoded = detectAndDecode(utf8BomBytes(csv));
      expect(decoded, isNotNull);
      expect(decoded!.encoding, CsvEncoding.utf8Bom);
      // BOM を落とさないと1列目が `﻿name` になり、ヘッダ検証で落ちる。
      expect(decoded.text, csv);
      expect(decoded.text.startsWith('name'), isTrue);

      // 落とし損ねていないことを、ヘッダ検証まで通して確かめる。
      final result = prepareFoodsCsv(utf8BomBytes(csv));
      expect(result.fileError, isNull);
      expect(result.rows.single.name, '鶏むね肉');
    });

    test('Shift_JIS の日本語が文字化けしない（TC-FEAT10-03）', () {
      final bytes = shiftJisBytes(csv);
      // UTF-8 として読めないバイト列であることを先に確かめる。
      // ここが通ってしまうと、この試験は判定順序を試せていない。
      expect(
        () => utf8.decode(bytes, allowMalformed: false),
        throwsFormatException,
      );

      final decoded = detectAndDecode(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.encoding, CsvEncoding.shiftJis);
      expect(decoded.text, csv);

      final result = prepareFoodsCsv(bytes);
      expect(result.encoding, CsvEncoding.shiftJis);
      expect(result.rows.single.name, '鶏むね肉');
    });

    test('日本語を含む UTF-8 が Shift_JIS と誤判定されない（TC-FEAT10-04）', () {
      // **これが判定順序の本体である。**
      // Shift_JIS デコーダは UTF-8 のバイト列も受理してしまうことがある。
      // 先に試すと、UTF-8 の日本語が**エラーにならないまま**化けて取り込まれる（§10-4）。
      const csv = 'name,protein_amount\n牛乳,6.8\n';
      final bytes = utf8Bytes(csv);

      // 逆順に組んだ場合に何が起きるかを対比で示す。例外は飛ばない。
      final garbled = shiftJis.decode(bytes);
      expect(garbled, isNot(contains('牛乳')), reason: '先に Shift_JIS を試すと化ける');
      expect(garbled, contains('迚帑ｹｳ'));

      // 判定順（BOM → UTF-8厳密 → Shift_JIS）を守れば化けない。
      final decoded = detectAndDecode(bytes);
      expect(decoded!.encoding, CsvEncoding.utf8Plain);
      expect(decoded.text, csv);

      final result = prepareFoodsCsv(bytes);
      expect(result.encoding, CsvEncoding.utf8Plain);
      expect(result.rows.single.name, '牛乳');
    });

    test('3種のどれでも読めないバイト列は null（ERR-FOOD-005）', () {
      // Shift_JIS の未定義領域。UTF-8 としても不正。
      final broken = Uint8List.fromList([0x80, 0xFF, 0xFD, 0xF8]);
      expect(detectAndDecode(broken), isNull);
      expect(
        prepareFoodsCsv(broken).fileError,
        CsvFileError.undecodable,
      );
    });
  });

  group('3. ヘッダ行の扱い（§3.3）', () {
    test('正のヘッダ・エイリアス・列順の入れ替えを受ける', () {
      expect(
        prepareFoodsCsv(utf8Bytes('name,protein_amount\n卵,6.0\n')).fileError,
        isNull,
      );
      // Excel で人が作る想定のエイリアス。
      expect(
        prepareFoodsCsv(utf8Bytes('食品名,タンパク質量\n卵,6.0\n')).fileError,
        isNull,
      );
      // 列順はヘッダ名で解決する。入れ替わっても取り違えない。
      final swapped = prepareFoodsCsv(
        utf8Bytes('protein_amount,name\n6.0,卵\n'),
      );
      expect(swapped.fileError, isNull);
      expect(swapped.rows.single.name, '卵');
      expect(swapped.rows.single.proteinAmount, 6.0);

      // 大文字・前後の空白は吸収する。
      expect(
        prepareFoodsCsv(utf8Bytes('Name, PROTEIN_AMOUNT\n卵,6.0\n')).fileError,
        isNull,
      );
    });

    test('ヘッダが無い・欠けている・3列あるものを弾く（ERR-FOOD-006）', () {
      // ヘッダ行が無い。1行目がデータでも受けない。列取り違えを検知できないため。
      expect(
        prepareFoodsCsv(utf8Bytes('卵,6.0\n')).fileError,
        CsvFileError.badHeader,
      );
      // 必須列の欠落。
      expect(
        prepareFoodsCsv(utf8Bytes('name,calories\n卵,6.0\n')).fileError,
        CsvFileError.badHeader,
      );
      // 2列ちょうどでない。
      expect(
        prepareFoodsCsv(utf8Bytes('name,protein_amount,id\n卵,6.0,1\n')).fileError,
        CsvFileError.badHeader,
      );
      // 空ファイル。
      expect(prepareFoodsCsv(utf8Bytes('')).fileError, CsvFileError.badHeader);
    });

    test('ヘッダだけでデータ行が無いものを弾く（ERR-FOOD-004）', () {
      expect(
        prepareFoodsCsv(utf8Bytes('name,protein_amount\n')).fileError,
        CsvFileError.noDataRows,
      );
      // 空行しか無い場合も同じ。空行はデータ行に数えない。
      expect(
        prepareFoodsCsv(utf8Bytes('name,protein_amount\n\n\n')).fileError,
        CsvFileError.noDataRows,
      );
    });
  });

  group('4. 空行・末尾の改行（§3.3）', () {
    test('末尾の改行が空行を作らない', () {
      // Excel は保存時に最後の改行を付ける。これを空行に数えてはならない。
      final withNewline = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵,6.0\n'),
      );
      expect(withNewline.rows.length, 1);
      expect(withNewline.skippedEmptyCount, 0);

      // 改行が無くても同じ結果になる。
      final without = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵,6.0'),
      );
      expect(without.rows.length, 1);
      expect(without.skippedEmptyCount, 0);

      // CRLF でも同じ。
      final crlf = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\r\n卵,6.0\r\n'),
      );
      expect(crlf.rows.length, 1);
      expect(crlf.skippedEmptyCount, 0);
    });

    test('途中と末尾の空行はエラーにせず数える（TC-FEAT10-10）', () {
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵,6.0\n\n鶏むね肉,25.0\n,\n\n'),
      );
      expect(result.errors, isEmpty, reason: '空行はエラーにしない');
      expect(result.rows.length, 2);
      // 空行は3つ（4行目・`,`だけの6行目・7行目）。末尾の改行は数えない。
      expect(result.skippedEmptyCount, 3);
    });

    test('行番号は物理行番号（ヘッダ行＝1・TC-FEAT10-08）', () {
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵,6.0\n\n鶏むね肉,-1\n'),
      );
      expect(result.errors.single.line, 4, reason: '空行を飛ばしても行番号は詰めない');
      expect(result.errors.single.column, 'protein_amount');
      expect(result.errors.single.reason, FoodReason.proteinNegative);
    });
  });

  group('5. 列数の過不足（§3.4）', () {
    test('2列でない行を弾く（COLUMN_COUNT_MISMATCH）', () {
      final short = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵\n'),
      );
      expect(short.errors.single.reason, FoodReason.columnCountMismatch);
      expect(short.errors.single.column, '-');
      expect(short.rows, isEmpty);

      final long = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵,6.0,余分\n'),
      );
      expect(long.errors.single.reason, FoodReason.columnCountMismatch);
    });
  });

  group('6-7. protein_amount の型・範囲（§3.4・TC-FEAT10-09）', () {
    /// 1行だけのCSVを検証して、その行の理由を取り出す。
    FoodReason? reasonOf(String protein) {
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵,$protein\n'),
      );
      return result.errors.isEmpty ? null : result.errors.single.reason;
    }

    test('数値でない行を弾く（PROTEIN_NOT_NUMBER）', () {
      expect(reasonOf('abc'), FoodReason.proteinNotNumber);
      expect(reasonOf('20g'), FoodReason.proteinNotNumber, reason: '単位付き');
      expect(reasonOf('"1,200"'), FoodReason.proteinNotNumber, reason: '桁区切り');
      expect(reasonOf('２０'), FoodReason.proteinNotNumber, reason: '全角数字');
      expect(reasonOf('1e3'), FoodReason.proteinNotNumber, reason: '指数表記');
      expect(reasonOf('.5'), FoodReason.proteinNotNumber, reason: '整数部が要る');
      expect(reasonOf('20.'), FoodReason.proteinNotNumber, reason: '小数部が要る');
      // `double.tryParse` はこの2つを通す。範囲判定が効かないため落とす。
      expect(reasonOf('NaN'), FoodReason.proteinNotNumber);
      expect(reasonOf('Infinity'), FoodReason.proteinNotNumber);
    });

    test('空を弾く（PROTEIN_EMPTY）', () {
      expect(reasonOf(''), FoodReason.proteinEmpty);
      expect(reasonOf('   '), FoodReason.proteinEmpty);
    });

    test('負数を弾く（DB の CHECK (protein_amount >= 0) と同じ規則）', () {
      expect(reasonOf('-0.1'), FoodReason.proteinNegative);
      expect(reasonOf('-1'), FoodReason.proteinNegative);
      expect(reasonOf('-25.0'), FoodReason.proteinNegative);

      // 0 は通る。DB も `>= 0` を許す。
      expect(reasonOf('0'), isNull);
      expect(reasonOf('0.0'), isNull);
    });

    test('上限を超える値を弾く（PROTEIN_TOO_LARGE）', () {
      expect(reasonOf('1000'), isNull, reason: '境界は通す');
      expect(reasonOf('1000.0'), isNull);
      expect(reasonOf('1000.1'), FoodReason.proteinTooLarge);
      expect(reasonOf('99999'), FoodReason.proteinTooLarge);
    });

    test('小数第2位以下は弾かずに丸める（ADR-0022・numeric(6,1)）', () {
      // 桁数エラーにはしない。丸めは仕様だと設計が決めている（§3.4）。
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵,20.55\n'),
      );
      expect(result.errors, isEmpty);
      // 送る前に DB と同じ丸めをしておく。保存値と送信値をずらさないため。
      expect(result.rows.single.proteinAmount, 20.6);
      expect(result.rows.single.toJson()['protein_amount'], 20.6);
    });

    test('前後の空白は落として数値と見る', () {
      // Excel 由来のセルに空白が混じることがある。型エラーにする理由が無い。
      expect(reasonOf(' 25.0 '), isNull);
    });
  });

  group('8. name の正規化（§4-5・TC-FEAT10-16）', () {
    test('前後の空白を除く（全角スペースを含む）', () {
      expect(normalizeFoodName('　鶏むね肉 '), '鶏むね肉');
      expect(normalizeFoodName('  卵  '), '卵');
      expect(normalizeFoodName('\t卵\n'), '卵');
    });

    test('全角英数字を半角にする', () {
      expect(normalizeFoodName('ＭＣＴオイル'), 'mctオイル');
      expect(normalizeFoodName('プロテイン１００'), 'プロテイン100');
      // ⚠️ 設計との差: TC-FEAT10-17 は `ＭＣＴオイル` → `MCTオイル` と書くが、
      // §4-5 の手順3（英字を小文字へ）を通すと `mctオイル` になる。
      // 手順の記述が §4-5・§3.3・DB物理設計 §1.5 の3か所で「小文字化」と
      // 揃っているため、手順どおり小文字化する側を採った。
    });

    test('英字を小文字にする', () {
      expect(normalizeFoodName('Whey'), 'whey');
      expect(normalizeFoodName('WHEY'), 'whey');
      expect(normalizeFoodName(' WHEY '), 'whey');
      // 正規化違いは同一視される（TC-FEAT10-18）。
      expect(normalizeFoodName('Whey'), normalizeFoodName(' WHEY '));
    });

    test('連続する空白を1つにする', () {
      expect(normalizeFoodName('鶏  むね肉'), '鶏 むね肉');
      expect(normalizeFoodName('鶏　　むね肉'), '鶏 むね肉', reason: '全角スペースも畳む');
      expect(normalizeFoodName('鶏 \t むね肉'), '鶏 むね肉');
    });

    test('カタカナ・ひらがなの表記ゆれは吸収しない（TC-FEAT10-19・§10-14）', () {
      // 別物を同一視する事故を避けるため、意図してここで止めている。
      expect(normalizeFoodName('鶏むね肉'), isNot(normalizeFoodName('鶏ムネ肉')));
      expect(normalizeFoodName('玉子'), isNot(normalizeFoodName('たまご')));
    });

    test('保存されるのは正規化後の文字列である（TC-FEAT10-17）', () {
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n　ＭＣＴ  オイル ,14.0\n'),
      );
      expect(result.rows.single.name, 'mct オイル');
      expect(result.rows.single.toJson()['name'], 'mct オイル');
    });

    test('空・空白のみの name を弾く（EMPTY_NAME）', () {
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n   ,6.0\n'),
      );
      expect(result.errors.single.reason, FoodReason.emptyName);
      expect(result.errors.single.column, 'name');
    });

    test('長すぎる name を弾く（NAME_TOO_LONG・正規化後で数える）', () {
      final ok = 'あ' * kMaxFoodNameLength;
      final tooLong = 'あ' * (kMaxFoodNameLength + 1);
      expect(
        prepareFoodsCsv(utf8Bytes('name,protein_amount\n$ok,6.0\n')).errors,
        isEmpty,
      );
      expect(
        prepareFoodsCsv(
          utf8Bytes('name,protein_amount\n$tooLong,6.0\n'),
        ).errors.single.reason,
        FoodReason.nameTooLong,
      );
      // 前後の空白は正規化で落ちるため、長さには数えない。
      final padded = '  $ok  ';
      expect(
        prepareFoodsCsv(utf8Bytes('name,protein_amount\n$padded,6.0\n')).errors,
        isEmpty,
      );
    });
  });

  group('9. 同一ファイル内の重複（§3.4・TC-FEAT10-10）', () {
    test('正規化後に同じになる name を端末側で弾く（DUPLICATE_NAME）', () {
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\nWhey,20.0\n WHEY ,21.0\n'),
      );
      // どちらを採るか決められないためエラーにする。後勝ちで黙って捨てない。
      expect(result.errors.single.reason, FoodReason.duplicateName);
      expect(result.errors.single.line, 3, reason: '2件目を挙げる');
      expect(result.isReadyToSend, isFalse);
    });

    test('既存マスタとの重複とは別物である', () {
      // ファイル内で重複していなければエラーにしない。
      // 既存と同名かどうかは DB（`uq_foods_name`）がスキップで処理する（§3.2）。
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵,6.0\n鶏むね肉,25.0\n'),
      );
      expect(result.errors, isEmpty);
      expect(result.isReadyToSend, isTrue);
    });
  });

  group('10. 引用符とカンマ（RFC 4180・TC-FEAT10-11）', () {
    test('引用符で囲んだセルのカンマ・改行・"" を復元する', () {
      final rows = parseCsv('a,"b,c",d\n"改\n行","二""重"\n');
      expect(rows.first.fields, ['a', 'b,c', 'd']);
      expect(rows[1].fields, ['改\n行', '二"重']);
    });

    test('セル内の改行があっても物理行番号がずれない', () {
      // 引用符の中の改行は行を区切らない。だが物理行は進む。
      // ここがずれると、エラー一覧の行番号を Excel と突き合わせられない。
      final rows = parseCsv('name,protein_amount\n"改\n行",6.0\n卵,-1\n');
      expect(rows.length, 3);
      expect(rows[1].line, 2, reason: '2行目から始まるセル');
      expect(rows[2].line, 4, reason: 'セル内の改行の分だけ進む');

      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n"改\n行",6.0\n卵,-1\n'),
      );
      expect(result.errors.single.line, 4);
    });

    test('引用符で囲んだ食品名も正規化して取り込む', () {
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n"ゆで卵, 2個",12.0\n'),
      );
      expect(result.errors, isEmpty);
      expect(result.rows.single.name, 'ゆで卵, 2個');
    });

    test('CRLF と LF が混ざっても行を取り違えない', () {
      final rows = parseCsv('a,b\r\nc,d\ne,f');
      expect(rows.map((row) => row.fields), [
        ['a', 'b'],
        ['c', 'd'],
        ['e', 'f'],
      ]);
      expect(rows.map((row) => row.line), [1, 2, 3]);
    });
  });

  group('上限とファイル全体の不備（§3.3・TC-FEAT10-12）', () {
    test('サイズはバイト列を読む前に判定できる（ERR-FOOD-003）', () {
      expect(checkCsvSize(kMaxCsvBytes), isNull, reason: '境界は通す');
      expect(checkCsvSize(kMaxCsvBytes + 1), CsvFileError.tooLarge);
    });

    test('データ行が上限を超えるものを弾く（ERR-FOOD-004）', () {
      String build(int count) {
        final buffer = StringBuffer('name,protein_amount\n');
        for (var i = 0; i < count; i++) {
          buffer.writeln('食品$i,1.0');
        }
        return buffer.toString();
      }

      expect(
        prepareFoodsCsv(utf8Bytes(build(kMaxCsvDataRows))).fileError,
        isNull,
        reason: '境界は通す',
      );
      expect(
        prepareFoodsCsv(utf8Bytes(build(kMaxCsvDataRows + 1))).fileError,
        CsvFileError.tooManyRows,
      );
    });

    test('拡張子の判定', () {
      expect(isCsvFileName('foods.csv'), isTrue);
      expect(isCsvFileName('FOODS.CSV'), isTrue);
      expect(isCsvFileName('foods.xlsx'), isFalse);
      expect(isCsvFileName('csv'), isFalse);
    });
  });

  group('検証エラーがあれば送らない（TC-FEAT10-07）', () {
    test('1行でも不正なら isReadyToSend が false になる', () {
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵,6.0\n鶏むね肉,-1\nプロテイン,20.0\n'),
      );
      // ここが false である限り、画面は RPC を呼ばない。DB は取込前のままである。
      expect(result.isReadyToSend, isFalse);
      expect(result.errors.length, 1);
      // 妥当な行は積んであるが、送らない。全件ロールバックと同じ2値に保つ（§10-11 A-1）。
      expect(result.rows.length, 2);
    });

    test('エラーは最初の1件で止めず全件見る', () {
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵,-1\n鶏むね肉,abc\n,5.0\n'),
      );
      expect(result.errors.length, 3);
      expect(result.errors.map((error) => error.line), [2, 3, 4]);
    });

    test('画面に出すエラーは100件で打ち切る（§3.1）', () {
      final buffer = StringBuffer('name,protein_amount\n');
      for (var i = 0; i < 150; i++) {
        buffer.writeln('食品$i,-1');
      }
      final result = prepareFoodsCsv(utf8Bytes(buffer.toString()));
      expect(result.errors.length, kMaxDisplayedRowErrors);
      expect(result.errorsTruncated, isTrue);
      expect(result.totalErrorCount, 150);
    });
  });

  group('数式扱いの警告（§4-4・TC-FEAT10-15）', () {
    test('= + @ で始まる name を数えるが取込は止めない', () {
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n=SUM(A1),6.0\n+卵,6.0\n@卵,6.0\n卵,6.0\n'),
      );
      expect(result.errors, isEmpty, reason: '警告であってエラーではない');
      expect(result.isReadyToSend, isTrue);
      expect(result.warningLines, [2, 3, 4]);
    });

    test('TAB・CR で始まる name も警告にする（正規化前の原文で見る）', () {
      // 正規化すると先頭の TAB・CR は消える。だから原文で判定する。
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n"\t卵",6.0\n'),
      );
      expect(result.warningLines, [2]);
      expect(result.rows.single.name, '卵', reason: '保存されるのは正規化後');
    });
  });

  group('RPC へ渡す形（§3.2）', () {
    test('キーは DB の列名そのまま（snake_case）', () {
      final result = prepareFoodsCsv(
        utf8Bytes('name,protein_amount\n卵,6.0\n'),
      );
      expect(result.rows.single.toJson(), {'name': '卵', 'protein_amount': 6.0});
      // ここに無い列を出さないため、未知列は構造的に起きない。
      expect(result.rows.single.toJson().keys.toSet(), {
        'name',
        'protein_amount',
      });
    });
  });
}
