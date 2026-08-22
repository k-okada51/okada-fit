import 'package:flutter/material.dart';

import '../data/machine_repository.dart';
import '../domain/machine.dart';
import 'error_snack_bar.dart';
import 'machine_form_page.dart';

/// SCR-02 器具一覧（FEAT-01）。
///
/// 器具は部位列を持たない。各行に出す部位は `machine_menus` →
/// `training_menus.body_part` を辿って導いたもの（§4 L-01）。
/// 1台が複数部位を持つため、部位は `Chip` を**複数**並べて出す（§7.1）。
///
/// 並びは「ジム名 → 部位 → 器具名」。PostgREST の `order` では表現できないため
/// Dart 側で並べる（§5.6・`sortMachines`）。
class MachineListPage extends StatefulWidget {
  const MachineListPage({super.key, this.repository});

  /// テストから差し替えられるよう開けてある。省略時は共有クライアントを使う。
  final MachineRepository? repository;

  @override
  State<MachineListPage> createState() => _MachineListPageState();
}

class _MachineListPageState extends State<MachineListPage> {
  late final MachineRepository _repository =
      widget.repository ?? MachineRepository();

  List<Gym> _gyms = const [];
  List<TrainingMenu> _menus = const [];
  List<TrainingMachine> _machines = const [];

  /// 一覧の絞り込みに使うジム。`null` はすべて。
  ///
  /// **登録フォームのジム欄とは別物**である（§7.3）。
  int? _filterGymId;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 一覧と選択肢を読む。3本の SELECT は並行に投げる（§2 の par）。
  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final gymsFuture = _repository.fetchGyms();
      final menusFuture = _repository.fetchMenus();
      final machinesFuture = _repository.fetchMachines(gymId: _filterGymId);
      final gyms = await gymsFuture;
      final menus = await menusFuture;
      final machines = await machinesFuture;
      if (!mounted) return;
      setState(() {
        _gyms = gyms;
        _menus = menus;
        _machines = machines;
        // 消えたジムで絞ったままにしない。
        if (!gyms.any((gym) => gym.id == _filterGymId)) _filterGymId = null;
      });
    } catch (error) {
      if (!mounted) return;
      // 写像は error_mapper（W-05）に任せる。ここで例外を分類しない。
      showError(context, error, onRetry: _load);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 登録・編集の画面へ。戻ってきたら一覧を読み直す。
  Future<void> _openForm({TrainingMachine? machine}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            MachineFormPage(machine: machine, repository: _repository),
      ),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(machine == null ? '登録しました' : '更新しました')),
      );
    await _load();
  }

  /// 器具を削除する（C-04）。`machine_menus` の子行は FK の CASCADE で消える。
  Future<void> _delete(TrainingMachine machine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('器具を削除'),
        content: Text(
          '「${machine.name}」を削除します。\n'
          '紐づけた${machine.menus.length}件の種目との対応も消えます。'
          '種目そのものは残ります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final deleted = await _repository.deleteMachine(machine.id);
      if (!mounted) return;
      if (!deleted) {
        // **戻り値が `null`＝対象が無い**（ERR-MACHINE-006）。例外ではない。
        // ここを書き忘れると「消えたように見えて消えていない」ことになる（§6.1）。
        showAppFailure(context, errMachineNotFound);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('削除しました')));
      }
    } catch (error) {
      if (!mounted) return;
      showError(context, error);
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    // ジムか種目が0件なら器具は作れない（§4 L-04）。
    final canRegister = canRegisterMachine(_gyms.length, _menus.length);

    return Scaffold(
      appBar: AppBar(title: const Text('器具')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  if (!canRegister)
                    MaterialBanner(
                      leading: const Icon(Icons.info_outline),
                      content: Text(
                        _gyms.isEmpty
                            ? 'まずジムを登録してください。'
                            : 'まず種目を登録してください。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => _openForm(),
                          child: const Text('登録へ進む'),
                        ),
                      ],
                    ),
                  // ジムが1件のときは選択UIを出さない `[仮]`（§7.1）。結果は同じになる。
                  if (_gyms.length >= 2)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: DropdownButtonFormField<int?>(
                        initialValue: _filterGymId,
                        decoration: const InputDecoration(labelText: 'ジムで絞る'),
                        items: [
                          const DropdownMenuItem<int?>(
                            child: Text('すべてのジム'),
                          ),
                          for (final gym in _gyms)
                            DropdownMenuItem<int?>(
                              value: gym.id,
                              child: Text(gym.name),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() => _filterGymId = value);
                          _load();
                        },
                      ),
                    ),
                  if (_machines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('登録された器具はありません。')),
                    )
                  else
                    for (final machine in _machines) _buildTile(machine),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        // ジム・種目が0件でも押させる。作る導線はフォーム側のダイアログにある（§7）。
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('器具を登録'),
      ),
    );
  }

  Widget _buildTile(TrainingMachine machine) {
    return ListTile(
      title: Text(machine.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(machine.gymName),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              // 部位は種目から導いた集合。重複は畳んである（§4 L-01）。
              for (final part in machine.bodyParts)
                Chip(
                  label: Text(part.label),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          Text(machine.menus.map((menu) => menu.name).join('・')),
        ],
      ),
      isThreeLine: true,
      onTap: () => _openForm(machine: machine),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(machine),
        tooltip: '削除',
      ),
    );
  }
}
