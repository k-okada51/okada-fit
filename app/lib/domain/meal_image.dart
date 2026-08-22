/// 食事写真の入力検証（FEAT-08 §3.4・§4）。
///
/// **Edge Function 側と同じ規則を、送る前にも掛ける。**
/// 検証は2か所で行う（§3.4）。ここで落とせば通信も課金も起きない。
///
/// UI にも Supabase にも依存しない純関数だけを置く。
library;

import 'dart:typed_data';

/// 許可する MIME。Edge Function 側の `ALLOWED_MIME_TYPES` と同じ3つ。
const List<String> kAllowedImageMimeTypes = [
  'image/jpeg',
  'image/png',
  'image/webp',
];

/// 画像バイト長の下限。1KB を切るものは撮影の失敗か欠損である。
const int kMinImageBytes = 1024;

/// 画像バイト長の上限。端末側リサイズ後の実測は最大 303KB で、その約3倍。
const int kMaxImageBytes = 1048576;

/// 長辺の上限(px)。ADR-0003 が要求する縮小の目標値。
///
/// ⚠️ **縮小そのものは `image_picker` の `maxWidth`/`maxHeight` に任せる。**
/// 設計（§8 #10）は `resizeToMaxEdge` という Dart の純関数を想定していたが、
/// 画像のデコード・再エンコードを Dart で行うと、4000×3000 の写真で秒単位の
/// 時間とメモリを使う。`image_picker` はプラットフォーム側で縮小するため
/// 速く、依存も増えない。
///
/// 代償として**縮小結果を単体テストできない**。そのぶん、縮小後の
/// バイト長と形式は [assertImageInput] が必ず検査する。
const int kMaxImageEdgePx = 1024;

/// 画像入力の検証結果。問題が無ければ `null`。
///
/// 例外にしないのは、SCR-04 が結果領域に文言を出すだけで済ませるため
/// （§7「入力系のエラーは SnackBar を出さない」）。
class ImageInputError {
  const ImageInputError(this.code, this.message);

  /// ERR-MEAL-001 / 002 / 003。
  final String code;

  /// 利用者向け日本語。
  final String message;
}

/// 送信前の検証（§3.4）。Edge Function 側の `parseAnalyzeMealRequest` と同値。
///
/// | 検査 | ERR-ID |
/// |---|---|
/// | 空・下限未満 | ERR-MEAL-001 |
/// | 許可外 MIME・申告と実体の食い違い | ERR-MEAL-002 |
/// | 上限超え | ERR-MEAL-003 |
ImageInputError? validateImageInput(Uint8List bytes, String mimeType) {
  if (bytes.isEmpty) {
    return const ImageInputError('ERR-MEAL-001', '写真を読み取れませんでした。撮り直してください。');
  }
  if (!kAllowedImageMimeTypes.contains(mimeType)) {
    return const ImageInputError('ERR-MEAL-002', 'JPEG・PNG・WebP の写真を選んでください。');
  }
  // 上限を先に見る。大きすぎる場合は「壊れている」ではなく「大きい」と伝えたい。
  if (bytes.length > kMaxImageBytes) {
    return const ImageInputError('ERR-MEAL-003', '写真のサイズが大きすぎます。撮り直してください。');
  }
  if (bytes.length < kMinImageBytes) {
    return const ImageInputError('ERR-MEAL-001', '写真を読み取れませんでした。撮り直してください。');
  }

  // **申告値とマジックバイトの両方**を見る。拡張子や申告だけを信じない。
  final actual = sniffImageMimeType(bytes);
  if (actual == null || actual != mimeType) {
    return const ImageInputError('ERR-MEAL-002', 'JPEG・PNG・WebP の写真を選んでください。');
  }
  return null;
}

/// 先頭バイトから実際の形式を見る。判別できなければ `null`。
///
/// 見るのは3種だけ。汎用の判別器は要らない。
String? sniffImageMimeType(Uint8List bytes) {
  // JPEG: FF D8 FF
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length >= png.length) {
    var matched = true;
    for (var i = 0; i < png.length; i++) {
      if (bytes[i] != png[i]) {
        matched = false;
        break;
      }
    }
    if (matched) return 'image/png';
  }
  // WebP: "RIFF" ....（4バイトの長さ）.... "WEBP"
  if (bytes.length >= 12 &&
      _ascii(bytes, 0, 4) == 'RIFF' &&
      _ascii(bytes, 8, 12) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}

/// base64 文字列のデコード後バイト長（§4 `decodedLength`）。
///
/// **全体をデコードしない。** 400KB の文字列を実体化せずに長さだけを求める。
int decodedBase64Length(String base64) {
  final body = base64.contains(',')
      ? base64.substring(base64.indexOf(',') + 1)
      : base64;
  // 改行が混ざっていても数え違えないよう、base64 の文字だけを数える。
  var length = 0;
  var padding = 0;
  for (var i = 0; i < body.length; i++) {
    final c = body.codeUnitAt(i);
    if (c == 0x3D) {
      padding++;
      length++;
    } else if (c == 0x0A || c == 0x0D || c == 0x20) {
      continue;
    } else {
      length++;
    }
  }
  return (length ~/ 4) * 3 - padding;
}

/// ファイル名から MIME を推測する。`image_picker` は MIME を返さない。
///
/// 判別できない場合は `null`。**推測に失敗したら送らない**ほうがよい。
/// マジックバイトとの照合で結局落ちるので、先に止める。
String? mimeTypeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return null;
}

String _ascii(Uint8List bytes, int start, int end) =>
    String.fromCharCodes(bytes.sublist(start, end));
