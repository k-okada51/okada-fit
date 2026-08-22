import 'package:flutter_test/flutter_test.dart';

import 'package:okada_fit/domain/dashboard.dart';
import 'package:okada_fit/domain/nutrition.dart';

/// ダッシュボード（W-17・FEAT-05）の単体テスト。
///
/// **日付は端末TZで解決して RPC へ渡す**（案A・2026-08-08 確定）。
/// ここがずれると、深夜の記録が前日に寄ったり月境で欠けたりする。
void main() {
  group('RPC へ渡す日付（§3・案A）', () {
    test('1. month は当月の初日〜末日', () {
      final r = buildDashboardRange(DateTime(2026, 8, 22, 23, 59), DashboardPeriod.month);
      expect(r.today, '2026-08-22');
      expect(r.rangeStart, '2026-08-01');
      expect(r.rangeEnd, '2026-08-31');
      expect(r.monthStart, '2026-08-01');
      expect(r.monthEnd, '2026-08-31');
    });

    test('2. 月末は翌月0日で求める（閏年の判定を書かない）', () {
      final leap = buildDashboardRange(DateTime(2028, 2, 10), DashboardPeriod.month);
      expect(leap.monthEnd, '2028-02-29', reason: '2028 は閏年');
      final normal = buildDashboardRange(DateTime(2026, 2, 10), DashboardPeriod.month);
      expect(normal.monthEnd, '2026-02-28');
      // 30日の月。
      expect(buildDashboardRange(DateTime(2026, 4, 5), DashboardPeriod.month).monthEnd,
          '2026-04-30');
      // 年またぎ。
      expect(buildDashboardRange(DateTime(2026, 12, 5), DashboardPeriod.month).monthEnd,
          '2026-12-31');
    });

    test('3. week は月曜から日曜', () {
      // 2026-08-22 は土曜日。
      expect(DateTime(2026, 8, 22).weekday, DateTime.saturday);
      final r = buildDashboardRange(DateTime(2026, 8, 22), DashboardPeriod.week);
      expect(r.rangeStart, '2026-08-17', reason: '月曜');
      expect(r.rangeEnd, '2026-08-23', reason: '日曜');

      // 日曜そのものは、その週の最終日になる（前の月曜が始まり）。
      final sunday = buildDashboardRange(DateTime(2026, 8, 23), DashboardPeriod.week);
      expect(sunday.rangeStart, '2026-08-17');
      expect(sunday.rangeEnd, '2026-08-23');

      // 月曜そのものは、その日が始まり。
      final monday = buildDashboardRange(DateTime(2026, 8, 17), DashboardPeriod.week);
      expect(monday.rangeStart, '2026-08-17');
      expect(monday.rangeEnd, '2026-08-23');
    });

    test('4. day は当日だけ。month_start/end は期間に依存しない', () {
      final r = buildDashboardRange(DateTime(2026, 8, 22), DashboardPeriod.day);
      expect(r.rangeStart, '2026-08-22');
      expect(r.rangeEnd, '2026-08-22');
      // トレーニング回数は常に今月（§3）。
      expect(r.monthStart, '2026-08-01');
      expect(r.monthEnd, '2026-08-31');
    });

    test('5. RPC の引数名が契約どおり', () {
      final params = buildDashboardRange(DateTime(2026, 8, 22), DashboardPeriod.week)
          .toParams(DashboardPeriod.week);
      expect(params.keys.toSet(), {
        'p_period',
        'p_today',
        'p_range_start',
        'p_range_end',
        'p_month_start',
        'p_month_end',
      });
      expect(params['p_period'], 'week');
    });
  });

  group('応答の読み取り', () {
    test('6. protein_gauge は階層ごと null になりうる（§3）', () {
      // **素で参照すると落ちる。** 体重未設定のとき階層が消える。
      final d = Dashboard.fromJson({
        'protein_gauge': null,
        'training_count': {'done_days': 3, 'target': 12},
        'heatmap': [],
      });
      expect(d.weightKg, isNull);
      expect(d.intakeG, 0);
      expect(d.proteinTarget, isA<ProteinTargetUnset>());
      expect(d.ratePct, isNull, reason: 'ゲージを描かない合図');
      // ヒートマップと回数は通常どおり出る（NFR-AVAIL-05）。
      expect(d.doneDays, 3);
      expect(d.targetCount, 12);
    });

    test('7. numeric が文字列で返っても double になる（ADR-0022）', () {
      final d = Dashboard.fromJson({
        'protein_gauge': {'weight_kg': '62.5', 'intake_g': '80.4'},
        'training_count': {'done_days': '5', 'target': '12'},
        'heatmap': [],
      });
      expect(d.weightKg, 62.5);
      expect(d.intakeG, 80.4);
      expect(d.doneDays, 5);
      expect(d.targetCount, 12);
    });

    test('8. 達成率は100%で頭打ち', () {
      Dashboard make(double intake) => Dashboard.fromJson({
        'protein_gauge': {'weight_kg': 60, 'intake_g': intake},
        'training_count': {'done_days': 0, 'target': 12},
        'heatmap': [],
      });
      // 目標は 60 × 2 = 120g。
      expect(make(60).ratePct, 50);
      expect(make(120).ratePct, 100);
      expect(make(300).ratePct, 100, reason: '超えても100で止める');
      expect(make(0).ratePct, 0);
    });

    test('9. トレーニングの達成率も頭打ち。目標0回なら null', () {
      Dashboard make(int done, int target) => Dashboard.fromJson({
        'protein_gauge': null,
        'training_count': {'done_days': done, 'target': target},
        'heatmap': [],
      });
      expect(make(6, 12).trainingRatePct, 50);
      expect(make(20, 12).trainingRatePct, 100);
      // 0で割らない。「目標を置かない」は正常な設定（RULE-007）。
      expect(make(3, 0).trainingRatePct, isNull);
    });

    test('10. ヒートマップは塗る日だけが返る', () {
      final d = Dashboard.fromJson({
        'protein_gauge': null,
        'training_count': {'done_days': 2, 'target': 12},
        'heatmap': [
          {'date': '2026-08-03', 'done': true, 'menu_names': ['ベンチプレス']},
          {'date': '2026-08-10', 'done': true, 'menu_names': []},
        ],
      });
      expect(d.doneDates, {'2026-08-03', '2026-08-10'});
      expect(d.heatmap.first.menuNames, ['ベンチプレス']);
    });
  });

  group('ヒートマップのマス作り', () {
    test('11. 閉区間で日を並べる', () {
      final days = datesIn(DateTime(2026, 8, 1), DateTime(2026, 8, 31));
      expect(days.length, 31);
      expect(formatDate(days.first), '2026-08-01');
      expect(formatDate(days.last), '2026-08-31');
    });

    test('12. 月をまたいでも数え違えない', () {
      final days = datesIn(DateTime(2026, 2, 26), DateTime(2026, 3, 2));
      expect(days.map(formatDate).toList(), [
        '2026-02-26',
        '2026-02-27',
        '2026-02-28',
        '2026-03-01',
        '2026-03-02',
      ]);
    });

    test('13. 同日なら1件。逆転していれば空', () {
      expect(datesIn(DateTime(2026, 8, 5), DateTime(2026, 8, 5)).length, 1);
      expect(datesIn(DateTime(2026, 8, 6), DateTime(2026, 8, 5)), isEmpty);
    });
  });

  group('月の前後移動（デザインの ←/→）', () {
    test('14. 見る月を変えても「当日」は動かない（ゲージは常に当日）', () {
      final r = buildDashboardRange(
        DateTime(2026, 8, 22),
        DashboardPeriod.month,
        viewedMonth: DateTime(2026, 7, 1),
      );
      expect(r.today, '2026-08-22', reason: 'ゲージは当日固定（FEAT-05 §10 #5）');
      expect(r.rangeStart, '2026-07-01');
      expect(r.rangeEnd, '2026-07-31');
      // 回数もその月に合わせる。カレンダーと数字がずれないため。
      expect(r.monthStart, '2026-07-01');
      expect(r.monthEnd, '2026-07-31');
    });

    test('15. 月をまたいで動かす。日は必ず1日に落ちる', () {
      expect(shiftMonth(DateTime(2026, 1, 31), -1), DateTime(2025, 12, 1));
      expect(shiftMonth(DateTime(2026, 12, 15), 1), DateTime(2027, 1, 1));
    });

    test('16. 未来の月へは進ませない', () {
      final now = DateTime(2026, 8, 22);
      expect(canGoForward(DateTime(2026, 7, 1), now), isTrue);
      expect(canGoForward(DateTime(2026, 8, 1), now), isFalse, reason: '当月が最新');
      expect(canGoForward(DateTime(2026, 9, 1), now), isFalse);
      expect(canGoForward(DateTime(2025, 12, 1), now), isTrue, reason: '年をまたぐ過去');
    });
  });

  group('週あたりのジム（表示指標。目標ではない）', () {
    test('17. 月の実績を週へ割る', () {
      // デザインの例: 31日の月に11日行って 2.5回/週。
      expect(weeklyGymRate(11, 31), 2.5);
      expect(weeklyGymRate(0, 31), 0);
      // 28日の月なら 4週ちょうど。
      expect(weeklyGymRate(8, 28), 2.0);
    });

    test('18. 日数が0でも0除算しない', () {
      expect(weeklyGymRate(5, 0), 0);
    });

    test('19. 月の日数は翌月0日で求める', () {
      expect(daysInMonth(DateTime(2026, 2, 1)), 28);
      expect(daysInMonth(DateTime(2028, 2, 1)), 29);
      expect(daysInMonth(DateTime(2026, 4, 1)), 30);
      expect(daysInMonth(DateTime(2026, 8, 1)), 31);
    });
  });
}
