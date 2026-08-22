/// ダッシュボード（FEAT-05・SCR-01）。
///
/// **日付はすべて端末のタイムゾーンで解決して RPC へ渡す**（案A・2026-08-08 確定）。
/// RPC 内で `CURRENT_DATE` / `now()::date` を使わない。Supabase は UTC のため、
/// サーバに任せると深夜の記録が前日に寄る。
///
/// UI にも Supabase にも依存しない。全て単体テストの対象。
library;

import 'nutrition.dart';

/// 集計期間（§3 の `p_period`）。
enum DashboardPeriod {
  day('day', '日'),
  week('week', '週'),
  month('month', '月');

  const DashboardPeriod(this.value, this.label);

  /// RPC へ渡す文字列。
  final String value;

  /// 画面のラベル。
  final String label;
}

/// RPC へ渡す日付一式（§3 の引数）。
class DashboardRange {
  const DashboardRange({
    required this.today,
    required this.rangeStart,
    required this.rangeEnd,
    required this.monthStart,
    required this.monthEnd,
  });

  final String today;

  /// ヒートマップの表示範囲（閉区間）。
  final String rangeStart;
  final String rangeEnd;

  /// 今月の初日と末日。**トレーニング回数は常に今月**で、期間に依存しない（§3）。
  final String monthStart;
  final String monthEnd;

  Map<String, dynamic> toParams(DashboardPeriod period) => {
    'p_period': period.value,
    'p_today': today,
    'p_range_start': rangeStart,
    'p_range_end': rangeEnd,
    'p_month_start': monthStart,
    'p_month_end': monthEnd,
  };
}

/// 期間から RPC の引数を組み立てる。
///
/// | 期間 | ヒートマップの範囲 |
/// |---|---|
/// | `day` | 当日1日だけ |
/// | `week` | **月曜から日曜**（`DateTime.weekday` は月=1） |
/// | `month` | 当月の初日から末日 |
///
/// 月末は「翌月の0日」で求める。`DateTime(2026, 3, 0)` は 2026-02-28 になり、
/// **閏年の判定を自分で書かずに済む。**
///
/// [viewedMonth] を渡すと、その月を見る（デザインの ←/→）。**当日は動かさない。**
/// ゲージは常に当日である（FEAT-05 §10 #5）。動くのはヒートマップと回数だけ。
DashboardRange buildDashboardRange(
  DateTime now,
  DashboardPeriod period, {
  DateTime? viewedMonth,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final base = viewedMonth ?? today;
  final monthStart = DateTime(base.year, base.month, 1);
  final monthEnd = DateTime(base.year, base.month + 1, 0);

  final (start, end) = switch (period) {
    DashboardPeriod.day => (today, today),
    DashboardPeriod.week => (
      today.subtract(Duration(days: today.weekday - 1)),
      today.add(Duration(days: 7 - today.weekday)),
    ),
    DashboardPeriod.month => (monthStart, monthEnd),
  };

  return DashboardRange(
    today: formatDate(today),
    rangeStart: formatDate(start),
    rangeEnd: formatDate(end),
    monthStart: formatDate(monthStart),
    monthEnd: formatDate(monthEnd),
  );
}

/// 週あたりのジム回数（デザインの「週あたりのジム 2.5回」）。
///
/// **目標は月次のまま**（RULE-007）。これは月の実績を週へ割った**表示指標**で、
/// 2つ目の目標ではない。
///
/// 月次の数字だけだと「今月あと何回」が分かっても、いま行くべきかが分からない。
/// 週あたりに割ると「今週は足りていない」が読める。行動を変えるのはこちらである。
///
/// 割る数は「その月の日数 ÷ 7」。31日の月なら 4.43 週で、11日行けば 2.5回/週。
/// 小数第1位まで。
double weeklyGymRate(int doneDays, int daysInMonth) {
  if (daysInMonth <= 0) return 0;
  final weeks = daysInMonth / 7;
  return (doneDays / weeks * 10).round() / 10;
}

/// その月の日数。翌月の0日で求める（閏年の判定を書かない）。
int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// 表示できる最も新しい月。**未来は見せない**（デザインの → が非活性）。
bool canGoForward(DateTime viewedMonth, DateTime now) =>
    viewedMonth.year < now.year ||
    (viewedMonth.year == now.year && viewedMonth.month < now.month);

/// 月を動かす。日は必ず1日に落とす。
DateTime shiftMonth(DateTime month, int delta) =>
    DateTime(month.year, month.month + delta, 1);

/// `YYYY-MM-DD`。
String formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// ヒートマップの1日。**返るのは塗る日だけ**（`done` は常に true・§3）。
class HeatmapDay {
  const HeatmapDay({
    required this.date,
    required this.menuNames,
  });

  final String date;

  /// ツールチップ用の種目名。重複排除・名前昇順で来る。
  final List<String> menuNames;

  factory HeatmapDay.fromJson(Map<String, dynamic> json) => HeatmapDay(
    date: json['date'] as String? ?? '',
    menuNames: [
      for (final name in (json['menu_names'] as List? ?? const []))
        if (name is String) name,
    ],
  );
}

/// RPC `get_dashboard` の戻り値。**計算済みの値は含まれない。**
class Dashboard {
  const Dashboard({
    required this.weightKg,
    required this.intakeG,
    required this.doneDays,
    required this.targetCount,
    required this.heatmap,
  });

  /// `protein_gauge.weight_kg`。**階層ごと null になりうる**（体重未設定・§3）。
  final double? weightKg;

  /// `protein_gauge.intake_g`。階層が null なら 0 として扱う。
  final double intakeG;

  /// 今月の実施日数。
  final int doneDays;

  /// 目標回数（月）。既定12（RULE-007）。
  final int targetCount;

  final List<HeatmapDay> heatmap;

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    // **階層ごと null になる。** `protein_gauge` を素で参照すると落ちる。
    final gauge = json['protein_gauge'] as Map?;
    final count = json['training_count'] as Map? ?? const {};

    return Dashboard(
      weightKg: gauge == null ? null : _asDouble(gauge['weight_kg']),
      intakeG: gauge == null ? 0 : _asDouble(gauge['intake_g']),
      doneDays: _asInt(count['done_days']),
      targetCount: _asInt(count['target']),
      heatmap: [
        for (final row in (json['heatmap'] as List? ?? const []))
          HeatmapDay.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
    );
  }

  /// ゲージの目標値。**式は書かない。** FEAT-07 の純関数に委ねる。
  ProteinTarget get proteinTarget => calcTargetProteinG(weightKg);

  /// 達成率(%)。**100%で頭打ち**（§3・FEAT-07 §7）。
  ///
  /// 目標が出せないときは `null`。ゲージを描かない合図になる。
  int? get ratePct {
    final target = proteinTarget;
    if (target is! ProteinTargetOk || target.targetG <= 0) return null;
    final rate = intakeG / target.targetG * 100;
    return rate >= 100 ? 100 : rate.round();
  }

  /// 今月の達成率(%)。目標0回のときは `null`（割れないため）。
  int? get trainingRatePct {
    if (targetCount <= 0) return null;
    final rate = doneDays / targetCount * 100;
    return rate >= 100 ? 100 : rate.round();
  }

  /// 塗る日の集合。ヒートマップの描画で毎日探索しないため。
  Set<String> get doneDates => {for (final day in heatmap) day.date};
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// 範囲に含まれる日を順に並べる。ヒートマップのマス作りに使う。
List<DateTime> datesIn(DateTime start, DateTime end) {
  final days = <DateTime>[];
  var cursor = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  // 日付の加算に `Duration(days: 1)` を使うと、夏時間のある地域で
  // 23時間・25時間の日が生じてずれる。日本では起きないが、
  // `DateTime(y, m, d + 1)` なら暦日での加算になり、そもそも起きない。
  while (!cursor.isAfter(last)) {
    days.add(cursor);
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
  return days;
}
