import 'package:flutter/material.dart';

import '../data/body_part_filter_repository.dart';
import '../data/machine_repository.dart';
import '../domain/machine.dart';
import 'error_snack_bar.dart';
import 'machine_list_page.dart';

/// 部位で器具を絞り込む画面（FEAT-02・SCR-02 / SCR-03 で共用）。
///
/// 部位は5値の**単一選択**（RULE-003）。`SegmentedButton` を使うことで
/// 複数選択が構造的に起きない（ERR-MACHINE-021 の担保・§3.1）。
///
/// SCR-03（トレーニング）で使うときは [selectable] を立てる。違いは選択UIの
/// 有無だけである（§7）。器具が0件のときは [onSubmit] のボタンを**非活性**に
/// する。AI に渡す情報が無く、呼んでも課金だけが発生するため（§10 #1）。
class BodyPartFilterPage extends StatefulWidget {
  const BodyPartFilterPage({
    super.key,
    this.repository,
    this.machineRepository,
    this.selectable = false,
    this.onSubmit,
  });

  /// テストから差し替えられるよう開けてある。省略時は共有クライアントを使う。
  final BodyPartFilterRepository? repository;

  /// ジム一覧の取得元（FEAT-01 C-09）。**ジムの取得は FEAT-01 の担当**であり、
  /// 同じ SELECT を本機能側に写さない。
  final MachineRepository? machineRepository;

  /// 器具を選ばせるか（SCR-03）。既定は表示だけ（SCR-02）。
  final bool selectable;

  /// 選んだ器具の受け渡し先（FEAT-03 の `machine_ids`・§1 #4）。
  ///
  /// `null` のときは確定ボタンを出さない。押せない導線を置かないためである。
  final ValueChanged<List<TrainingMachine>>? onSubmit;

  @override
  State<BodyPartFilterPage> createState() => _BodyPartFilterPageState();
}

class _BodyPartFilterPageState extends State<BodyPartFilterPage> {
  late final BodyPartFilterRepository _repository =
      widget.repository ?? BodyPartFilterRepository();
  late final MachineRepository _machineRepository =
      widget.machineRepository ?? MachineRepository();

  List<Gym> _gyms = const [];

  /// 絞り込むジム。ジムが1件のときも既定値を入れる `[仮]`（§7）。
  int? _gymId;

  /// 選んだ部位。`null` は未選択（初期状態）。
  BodyPart? _bodyPart;

  MachineListResult? _result;

  /// ジムと部位の組をキーにした保持（§7）。同じ組の再選択では取りに行かない。
  final _cache = <String, MachineListResult>{};

  /// 選んだ器具（SCR-03）。器具IDで持つ。
  final _selectedIds = <int>{};

  /// 要求ごとに進める世代（§7）。**古い応答の描画を捨てるために使う。**
  ///
  /// Dart に `AbortController` に相当する仕組みが無い。往復は中断しない。
  /// 捨てるのは描画だけである。
  int _generation = 0;

  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadGyms();
  }

  /// ジムの一覧を読む（FEAT-01 C-09）。
  Future<void> _loadGyms() async {
    setState(() => _isLoading = true);
    try {
      final gyms = await _machineRepository.fetchGyms();
      if (!mounted) return;
      setState(() {
        _gyms = gyms;
        // 未選択のまま部位だけ選ばせない。既定値を入れる `[仮]`（§7）。
        _gymId = gyms.isEmpty ? null : gyms.first.id;
      });
    } catch (error) {
      if (!mounted) return;
      // 写像は error_mapper（W-05）に任せる。ここで例外を分類しない。
      showError(context, error, onRetry: _loadGyms);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 器具を引き直す。部位が未選択なら何も出さない。
  Future<void> _load() async {
    final bodyPart = _bodyPart;
    if (bodyPart == null) {
      setState(() {
        _result = null;
        _hasError = false;
      });
      return;
    }

    final filter = MachineFilter.tryCreate(
      bodyPartLabel: bodyPart.label,
      gymId: _gymId,
    );
    if (filter == null) {
      // 5値以外・ジムの指定が不正。**PostgREST を呼ばない**（§2 ①）。
      // `SegmentedButton` と `BodyPart` 型のため部位側は構造的に起きない。
      showAppFailure(
        context,
        _gymId != null && _gymId! < 1
            ? errGymIdNotAllowed
            : errBodyPartNotAllowed,
      );
      return;
    }

    final key = '${_gymId ?? 0}/${bodyPart.label}';
    final cached = _cache[key];
    if (cached != null) {
      // 同じジム・同じ部位は取りに行かない（NFR-PERF-02 の体感短縮）。
      setState(() {
        _result = cached;
        _hasError = false;
        _isLoading = false;
      });
      return;
    }

    final generation = ++_generation;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final result = await _repository.findMachines(filter);
      // 追い越された応答は捨てる。最後に選んだ部位の結果だけを描く。
      if (!mounted || generation != _generation) return;
      setState(() {
        _cache[key] = result;
        _result = result;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      showError(context, error, onRetry: _load);
    }
  }

  /// 部位を切り替える。選択済みの器具は持ち越さない。
  void _selectBodyPart(BodyPart? bodyPart) {
    setState(() {
      _bodyPart = bodyPart;
      _selectedIds.clear();
    });
    _load();
  }

  /// ジムを切り替える。**部位の選択は保持する**（§7）。
  void _selectGym(int? gymId) {
    setState(() {
      _gymId = gymId;
      _selectedIds.clear();
    });
    _load();
  }

  /// 器具登録（SCR-02）へ送る。戻ったら保持を全部捨てて引き直す。
  ///
  /// 部分破棄にしない。紐づけの差し替えは選択中以外の部位の結果も変えるため（§7）。
  Future<void> _openMachineList() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MachineListPage(repository: _machineRepository),
      ),
    );
    if (!mounted) return;
    _cache.clear();
    await _loadGyms();
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final selected = result == null
        ? const <TrainingMachine>[]
        : result.machines
              .where((machine) => _selectedIds.contains(machine.id))
              .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('部位から器具をさがす')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ジムが1件のときは選択UIを出さない `[仮]`（§7）。結果は同じになる。
          if (_gyms.length >= 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: DropdownButtonFormField<int>(
                initialValue: _gymId,
                decoration: const InputDecoration(labelText: 'ジム'),
                items: [
                  for (final gym in _gyms)
                    DropdownMenuItem<int>(value: gym.id, child: Text(gym.name)),
                ],
                onChanged: _selectGym,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<BodyPart>(
                segments: [
                  for (final part in BodyPart.values)
                    ButtonSegment(value: part, label: Text(part.label)),
                ],
                // 単一選択。複数値が渡らない（ERR-MACHINE-021 の構造的担保）。
                selected: _bodyPart == null ? const <BodyPart>{} : {_bodyPart!},
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    _selectBodyPart(selection.isEmpty ? null : selection.first),
              ),
            ),
          ),
          Expanded(child: _buildResult(result)),
        ],
      ),
      bottomNavigationBar: widget.onSubmit == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  // 器具0件のときは押させない（§7・TC-FEAT02-19）。
                  onPressed: selected.isEmpty
                      ? null
                      : () => widget.onSubmit!(selected),
                  child: const Text('選んだ器具でメニューを作る'),
                ),
              ),
            ),
    );
  }

  Widget _buildResult(MachineListResult? result) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError) {
      // 失敗の文言は SnackBar 側で出している。ここは引き直す導線だけ置く。
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('器具を取得できませんでした。'),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: _load, child: const Text('再試行')),
          ],
        ),
      );
    }
    if (result == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('部位を選ぶと器具が表示されます。'),
        ),
      );
    }
    if (result.isEmpty) {
      // **0件はエラーではない**（§10 #1）。空状態として扱い、登録へ導く。
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fitness_center_outlined, size: 48),
              const SizedBox(height: 12),
              const Text('この部位で使える器具がありません。'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openMachineList,
                icon: const Icon(Icons.add),
                label: const Text('器具を登録する'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: result.machines.length,
      itemBuilder: (_, index) => _buildTile(result.machines[index]),
    );
  }

  Widget _buildTile(TrainingMachine machine) {
    // 種目名の `Chip`。畳み込みで1台にまとめた分がここに全部並ぶ（§7）。
    final subtitle = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final menu in machine.menus)
          Chip(label: Text(menu.name), visualDensity: VisualDensity.compact),
        // 部位は種目から導いた集合。重複は畳んである（RULE-003 の並び）。
        for (final part in machine.bodyParts)
          Chip(label: Text(part.label), visualDensity: VisualDensity.compact),
        Chip(
          label: Text(machine.gymName),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );

    if (!widget.selectable) {
      return ListTile(title: Text(machine.name), subtitle: subtitle);
    }
    return CheckboxListTile(
      value: _selectedIds.contains(machine.id),
      onChanged: (checked) => setState(() {
        if (checked == true) {
          _selectedIds.add(machine.id);
        } else {
          _selectedIds.remove(machine.id);
        }
      }),
      title: Text(machine.name),
      subtitle: subtitle,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
