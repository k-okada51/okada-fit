import 'package:flutter_test/flutter_test.dart';

import 'package:okada_fit/data/body_part_filter_repository.dart';
import 'package:okada_fit/domain/machine.dart';

/// 部位選択と器具の絞り込み（W-09・FEAT-02）の単体テスト。
///
/// ネットワークを使わない。Supabase の初期化もしない。
/// 見るのは埋め込み select の応答を畳む純関数と、条件の組み立てだけである。
///
/// 主戦場は**畳み込み**（`groupMachines`）。起点が `training_menus` のため、
/// 1台の器具は紐づく種目の件数だけ返る。埋め込み select に `DISTINCT` は無く、
/// 畳み忘れても**例外は出ない。同じ器具が並ぶだけ**である（FEAT-02 §10 #10）。
/// 気付ける場所がここしかないため、ここを厚くする。
void main() {
  group('畳み込み（§5 の DISTINCT 相当・TC-FEAT02-14）', () {
    test('1. 同じ器具が複数の種目で返っても1台に畳まれる', () {
      // ケーブルマシン1台が「背中」の種目2つに紐づく。
      // 部位「背中」で引くと**同じ器具が2行**返ってくる（§5 の例）。
      final rows = [
        _menuRow(
          id: 11,
          name: 'ラットプルダウン',
          bodyPart: '背中',
          machines: [_machineRow(id: 1, name: 'ケーブルマシン')],
        ),
        _menuRow(
          id: 12,
          name: 'シーテッドロー',
          bodyPart: '背中',
          machines: [_machineRow(id: 1, name: 'ケーブルマシン')],
        ),
      ];

      final machines = groupMachines(rows);

      // 畳んでいなければここが 2 になる。一覧に同じ器具が2回並ぶ。
      expect(machines.length, 1);
      expect(machines.single.id, 1);
    });

    test('2. 畳んだ後も種目名は全部残る（どの種目で引っかかったか分かる）', () {
      final rows = [
        _menuRow(
          id: 11,
          name: 'ラットプルダウン',
          bodyPart: '背中',
          machines: [_machineRow(id: 1, name: 'ケーブルマシン')],
        ),
        _menuRow(
          id: 12,
          name: 'シーテッドロー',
          bodyPart: '背中',
          machines: [_machineRow(id: 1, name: 'ケーブルマシン')],
        ),
      ];

      final menus = groupMachines(rows).single.menus;

      // 器具は1件、種目は2件。片方を捨てない（§3 の menus）。
      expect(menus.length, 2);
      expect(menus.map((menu) => menu.name).toList(), const [
        'シーテッドロー',
        'ラットプルダウン',
      ]);
      expect(menus.map((menu) => menu.id).toSet(), {11, 12});
    });

    test('2b. 同じ器具×同じ種目は二重に積まない（uq_mm_machine_menu と同じ規則）', () {
      // 中間行が重なった応答が来ても、種目は1件のままにする。
      final rows = [
        _menuRow(
          id: 11,
          name: 'ラットプルダウン',
          bodyPart: '背中',
          machines: [
            _machineRow(id: 1, name: 'ケーブルマシン'),
            _machineRow(id: 1, name: 'ケーブルマシン'),
          ],
        ),
      ];

      final machines = groupMachines(rows);
      expect(machines.length, 1);
      expect(machines.single.menus.length, 1);
    });

    test('3. 同名でも id が違えば畳まない（TC-FEAT02-10）', () {
      // 畳み込みのキーは `training_machines.id`。**名前で畳まない**（§4）。
      // 同名の別マシンが同じジムに2台ある運用を潰さないため。
      final rows = [
        _menuRow(
          id: 11,
          name: 'ラットプルダウン',
          bodyPart: '背中',
          machines: [
            _machineRow(id: 1, name: 'ケーブルマシン'),
            _machineRow(id: 2, name: 'ケーブルマシン'),
          ],
        ),
      ];

      final machines = groupMachines(rows);
      expect(machines.length, 2);
      expect(machines.map((machine) => machine.id).toList(), const [1, 2]);
    });

    test('4. 1台が複数部位の種目を持っても1件（TC-FEAT02-15/16）', () {
      // 絞り込みなしで引いた場合。menus に全部位分の種目が入る。
      final rows = [
        _menuRow(
          id: 11,
          name: 'ラットプルダウン',
          bodyPart: '背中',
          machines: [_machineRow(id: 1, name: 'ケーブルマシン')],
        ),
        _menuRow(
          id: 12,
          name: 'ケーブルフライ',
          bodyPart: '胸',
          machines: [_machineRow(id: 1, name: 'ケーブルマシン')],
        ),
      ];

      final machine = groupMachines(rows).single;
      expect(machine.menus.length, 2);
      // 部位は種目から導く。並びは RULE-003（胸→背中）。
      expect(machine.bodyParts, const [BodyPart.chest, BodyPart.back]);
    });
  });

  group('0件（§10 #1・TC-FEAT02-03/13）', () {
    test('5. 応答が空なら空のリスト。例外にしない', () {
      expect(groupMachines(const []), isEmpty);

      final result = MachineListResult(
        bodyPart: BodyPart.back,
        gymId: null,
        machines: groupMachines(const []),
      );
      // 0件は正常系。`total: 0` で返す。
      expect(result.total, 0);
      expect(result.isEmpty, isTrue);
      expect(result.machineIds, isEmpty);
      // 要求した部位はそのまま返る（取り違えの検出用・§3）。
      expect(result.bodyPart, BodyPart.back);
    });

    test('6. 器具が0台の種目は畳み込みで消える（TC-FEAT02-13）', () {
      // `machine_menus` が空配列の種目。件数に加算しない。
      final rows = [
        _menuRow(id: 11, name: '腕立て伏せ', bodyPart: '胸'),
        _menuRow(
          id: 12,
          name: 'ベンチプレス',
          bodyPart: '胸',
          machines: [_machineRow(id: 1, name: 'ベンチプレス台')],
        ),
      ];

      final machines = groupMachines(rows);
      expect(machines.length, 1);
      expect(machines.single.id, 1);
    });
  });

  group('並びの決定性（§4・TC-FEAT02-09）', () {
    test('7. 並びは ジム名 → 器具名 → id', () {
      final machines = sortFilteredMachines(
        groupMachines([
          _menuRow(
            id: 11,
            name: 'ベンチプレス',
            bodyPart: '胸',
            machines: [
              _machineRow(id: 1, name: 'ベンチプレス台', gymName: 'Bジム'),
              _machineRow(id: 2, name: 'チェストプレス', gymName: 'Aジム'),
              _machineRow(id: 3, name: 'インクラインベンチ', gymName: 'Aジム'),
            ],
          ),
        ]),
      );

      // Aジムが先。同じジムなら器具名。
      expect(machines.map((machine) => machine.id).toList(), const [3, 2, 1]);
    });

    test('7b. 入力の順番が変わっても結果の順番は変わらない', () {
      final forward = sortFilteredMachines(groupMachines(_shuffledRows()));
      final backward = sortFilteredMachines(
        groupMachines(_shuffledRows().reversed.toList()),
      );

      // PostgREST の `order` は DB の照合順序に依存する。応答の順に頼らない。
      expect(
        forward.map((machine) => machine.id).toList(),
        backward.map((machine) => machine.id).toList(),
      );
      // 器具の中の種目も同じ。`Set` や取得順に依存させない。
      expect(
        forward.first.menus.map((menu) => menu.id).toList(),
        backward.first.menus.map((menu) => menu.id).toList(),
      );
    });

    test('7c. 器具の中の種目は 部位順 → 種目名 の昇順', () {
      final rows = [
        _menuRow(
          id: 11,
          name: 'ラットプルダウン',
          bodyPart: '背中',
          machines: [_machineRow(id: 1, name: 'ケーブルマシン')],
        ),
        _menuRow(
          id: 12,
          name: 'トライセプス押し下げ',
          bodyPart: '腕',
          machines: [_machineRow(id: 1, name: 'ケーブルマシン')],
        ),
        _menuRow(
          id: 13,
          name: 'ケーブルフライ',
          bodyPart: '胸',
          machines: [_machineRow(id: 1, name: 'ケーブルマシン')],
        ),
      ];

      // RULE-003 の並び（胸→背中→腕）。宣言順がそのまま部位の並びである。
      expect(
        groupMachines(rows).single.menus.map((menu) => menu.name).toList(),
        const ['ケーブルフライ', 'ラットプルダウン', 'トライセプス押し下げ'],
      );
    });
  });

  group('条件の検証（ERR-MACHINE-020 / 022・TC-FEAT02-05）', () {
    test('8. 部位が5値以外なら条件を作れない（＝呼び出しを発行しない）', () {
      for (final label in const ['胸', '背中', '脚', '肩', '腕']) {
        expect(MachineFilter.tryCreate(bodyPartLabel: label), isNotNull);
      }

      // 5値以外。`MachineFilter` が作れない＝ PostgREST を呼ぶ手段が無い。
      expect(MachineFilter.tryCreate(bodyPartLabel: '腹'), isNull);
      expect(MachineFilter.tryCreate(bodyPartLabel: '全身'), isNull);
      expect(MachineFilter.tryCreate(bodyPartLabel: 'chest'), isNull);
      expect(MachineFilter.tryCreate(bodyPartLabel: ''), isNull);
      // ⚠️ 設計 §3.1 は trim 後に一致と定めるが、W-08 の `parseBodyPart` に
      // 揃えて trim しない。アプリとDBで判定をずらさないことを優先した。
      expect(MachineFilter.tryCreate(bodyPartLabel: ' 胸 '), isNull);

      // `null` は「部位で絞らない」。FEAT-01 の一覧用途と共用する（§4）。
      final noFilter = MachineFilter.tryCreate(bodyPartLabel: null);
      expect(noFilter, isNotNull);
      expect(noFilter!.bodyPart, isNull);
    });

    test('8b. gymId は 1 以上（ERR-MACHINE-022）', () {
      expect(MachineFilter.tryCreate(bodyPartLabel: '胸', gymId: 1), isNotNull);
      expect(MachineFilter.tryCreate(bodyPartLabel: '胸', gymId: 0), isNull);
      expect(MachineFilter.tryCreate(bodyPartLabel: '胸', gymId: -1), isNull);
      // 未指定は絞らない。ジムが1件のときの既定（§7）。
      expect(MachineFilter.tryCreate(bodyPartLabel: '胸')!.gymId, isNull);
    });

    test('8c. ジム指定時だけ !inner が2段付く（§3）', () {
      final noGym = MachineFilter.tryCreate(bodyPartLabel: '胸')!;
      final byGym = MachineFilter.tryCreate(bodyPartLabel: '胸', gymId: 3)!;

      // 経路は3ホップ。1往復で取る（N+1 を作らない・NFR-PERF-02）。
      expect(noGym.select, contains('machine_menus'));
      expect(noGym.select, contains('training_machines'));
      expect(noGym.select, contains('gyms'));
      expect(noGym.select.contains('!inner'), isFalse);

      // `!inner` を落とすと器具が0台の種目行が残る。2段とも要る。
      expect(byGym.select, contains('machine_menus!inner'));
      expect(byGym.select, contains('training_machines!inner'));
    });

    test('8d. 応答に5値以外が混ざったら FormatException（DB の CHECK が外れた場合）', () {
      final rows = [
        _menuRow(
          id: 11,
          name: '腹筋ローラー',
          bodyPart: '腹',
          machines: [_machineRow(id: 1, name: 'アブローラー')],
        ),
      ];
      // 黙って捨てない。W-08 の `TrainingMenu.fromJson` と同じ扱いにする。
      expect(() => groupMachines(rows), throwsFormatException);
    });
  });

  group('埋め込み select の応答の組み立て（§3 の生JSON・TC-FEAT02-02）', () {
    test('9. ネスト構造から器具・ジム・種目を取り出せる', () {
      final machine = groupMachines([
        {
          'id': 11,
          'name': 'ラットプルダウン',
          'body_part': '背中',
          'machine_menus': [
            {
              'training_machines': {
                'id': 1,
                'name': '  ケーブルマシン  ',
                'gym_id': 3,
                'gyms': {'id': 3, 'name': 'エニタイム東京'},
              },
            },
          ],
        },
      ]).single;

      expect(machine.id, 1);
      // 前後の空白は落とす（W-08 の平坦化と同じ扱い）。
      expect(machine.name, 'ケーブルマシン');
      expect(machine.gymId, 3);
      // ジム名は入れ子 `gyms` から取る。器具ごとの再照会（N+1）をしない。
      expect(machine.gymName, 'エニタイム東京');
      expect(machine.menus.single.id, 11);
      expect(machine.menus.single.name, 'ラットプルダウン');
      expect(machine.menus.single.bodyPart, BodyPart.back);
    });

    test('9b. bigint が文字列で返っても int になる', () {
      // ドライバによっては bigint が文字列で来る。
      final machine = groupMachines([
        {
          'id': '11',
          'name': 'ラットプルダウン',
          'body_part': '背中',
          'machine_menus': [
            {
              'training_machines': {
                'id': '1',
                'name': 'ケーブルマシン',
                'gym_id': '3',
                'gyms': {'id': '3', 'name': 'エニタイム東京'},
              },
            },
          ],
        },
      ]).single;

      expect(machine.id, 1);
      expect(machine.gymId, 3);
    });

    test('9c. 中間行に器具が無い場合は捨てる', () {
      // `!inner` を付けない経路では、器具側が空で返ることがある。
      final rows = [
        {
          'id': 11,
          'name': 'ラットプルダウン',
          'body_part': '背中',
          'machine_menus': [
            {'training_machines': null},
          ],
        },
      ];
      expect(groupMachines(rows), isEmpty);
    });

    test('9d. FEAT-03 に渡す machine_ids が取れる（§1 #4）', () {
      final result = MachineListResult(
        bodyPart: BodyPart.back,
        gymId: 3,
        machines: sortFilteredMachines(groupMachines(_shuffledRows())),
      );
      expect(result.total, result.machines.length);
      expect(result.machineIds, result.machines.map((m) => m.id).toList());
      expect(result.gymId, 3);
    });
  });
}

/// 埋め込み select が返す種目1行を作る（§3 の生JSON）。
Map<String, dynamic> _menuRow({
  required int id,
  required String name,
  required String bodyPart,
  List<Map<String, dynamic>> machines = const [],
}) => {
  'id': id,
  'name': name,
  'body_part': bodyPart,
  // 中間行1つに器具1台。器具が無い種目では空配列になる。
  'machine_menus': [
    for (final machine in machines) {'training_machines': machine},
  ],
};

/// ネストした器具1台を作る。
Map<String, dynamic> _machineRow({
  required int id,
  required String name,
  int gymId = 3,
  String gymName = 'エニタイム東京',
}) => {
  'id': id,
  'name': name,
  'gym_id': gymId,
  'gyms': {'id': gymId, 'name': gymName},
};

/// 並びのテスト用。同じ器具が複数の行に散らばった応答。
List<Map<String, dynamic>> _shuffledRows() => [
  _menuRow(
    id: 12,
    name: 'シーテッドロー',
    bodyPart: '背中',
    machines: [
      _machineRow(id: 1, name: 'ケーブルマシン'),
      _machineRow(id: 3, name: 'ロープーリー', gymName: 'Aジム'),
    ],
  ),
  _menuRow(
    id: 11,
    name: 'ラットプルダウン',
    bodyPart: '背中',
    machines: [
      _machineRow(id: 2, name: 'ラットマシン'),
      _machineRow(id: 1, name: 'ケーブルマシン'),
    ],
  ),
];
