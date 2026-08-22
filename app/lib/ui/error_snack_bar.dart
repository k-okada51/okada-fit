import 'package:flutter/material.dart';

import '../data/error_mapper.dart';

/// 失敗を利用者へ知らせる。
///
/// 出し方は `ScaffoldMessenger.of(context).showSnackBar(...)` に統一する（§1）。
/// **ダイアログは使わない。** 操作を止めずに知らせる（SCR-01〜05 共通）。
///
/// 呼ぶ前に `mounted` を確かめること。await の後の `context` は無効になりうる。
void showAppFailure(
  BuildContext context,
  AppFailure failure, {
  VoidCallback? onRetry,
}) {
  // 再試行ボタンを出す条件は2つ。**両方そろったときだけ**出す。
  //
  // ① `retryable: true`（時間をおけば通る見込みがある）
  // ② 呼び出し側が再試行の手段（[onRetry]）を持っている
  //
  // ② も要る理由。画面によっては再試行の手段が無い。押せないボタンを出さない。
  //
  // ERR-AI-TIMEOUT(504) は `retryable: false` で来るため、ここに出ない。
  // 再送が EXT-01 への二重課金になるためである（§4）。仕様どおりの挙動。
  final retry = failure.retryable ? onRetry : null;

  ScaffoldMessenger.of(context)
    // 前の通知が残っていると、新しい失敗が順番待ちになる。先に消す。
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(failure.message),
        action: retry == null
            ? null
            : SnackBarAction(label: '再試行', onPressed: retry),
      ),
    );
}

/// 例外をそのまま渡す版。[mapError] を挟む手間を省くだけ。
///
/// catch した例外を握り潰さないための入口（§1 握り潰し禁止の原則）。
///
/// **利用者が自分で中断したときは何も出さない**（2026-08-22 決定）。
/// Google のアカウント選択を閉じたのにエラーが出るのは不自然であるため。
/// 判定は [isUserCanceled]。ここに置けば全画面に効く。
///
/// これは握り潰しではない。**中断はそもそも失敗ではない**という扱いである。
void showError(BuildContext context, Object error, {VoidCallback? onRetry}) {
  if (isUserCanceled(error)) return;
  showAppFailure(context, mapError(error), onRetry: onRetry);
}
