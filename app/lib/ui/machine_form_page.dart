import 'package:flutter/material.dart';

import '../data/machine_repository.dart';
import '../domain/machine.dart';
import 'error_snack_bar.dart';

/// SCR-02 器具登録のフォーム（FEAT-01）。
///
/// 1台の器具に**種目を1件以上**紐づける。器具は部位列を持たず、部位は種目から
/// 導く（§4 L-01）。だから種目0件の器具は作らせない。
///
/// **登録順序の依存を画面に出さない**（2026-08-22 確定・§7）。
/// ジムも種目も、この画面を離れずにダイアログで作れる。
///
/// ⚠️ **設計との差**: FEAT-01 §7.3 は「SCR-02 は一覧と登録を同一画面で行う」と
/// するが、W-08 では一覧（`machine_list_page.dart`）と登録を別画面にした。
/// モバイル1カラムで、選択済みの種目チップと一覧を同時に置くと縦に伸びるため。
/// 導線は一覧の［器具を登録］からの push で、遷移は1階層に収まる。
class MachineFormPage extends StatefulWidget {
  const MachineFormPage({super.key, this.machine, this.repository});

  /// 編集する器具。`null` なら新規登録。
  final TrainingMachine? machine;

  /// テストから差し替えられるよう開けてある。省略時は共有クライアントを使う。
  final MachineRepository? repository;

  @override
  State<MachineFormPage> createState() => _MachineFormPageState();
}

class _MachineFormPageState extends State<MachineFormPage> {
  late final MachineRepository _repository =
      widget.repository ?? MachineRepository();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  /// 選択肢。初期表示で先読みする（§5.1）。
  List<Gym> _gyms = const [];
  List<TrainingMenu> _menus = const [];

  /// 選んだジム。`null` は未選択（ERR-MACHINE-002）。
  int? _selectedGymId;

  /// 選んだ種目。**`Set<int>` で持つ**（§7.3）。
  ///
  /// 重複（ERR-MACHINE-016）は UI からは構造的に起きない。
  final Set<int> _selectedMenuIds = <int>{};

  /// 種目リストの絞り込みに使う部位。`null` は絞らない。
  ///
  /// **部位を切り替えても種目の選択は保持する**（§7.3）。ケーブルマシンのように
  /// 部位をまたいで種目を選ぶ操作を1画面で終わらせるため。
  BodyPart? _bodyPartFilter;

  bool _isLoading = true;
  bool _isSaving = false;

  /// 送信を1度でも試したか。試す前から赤字を出さない。
  bool _submitted = false;

  bool get _isEditing => widget.machine != null;

  @override
  void initState() {
    super.initState();
    final machine = widget.machine;
    if (machine != null) {
      _nameController.text = machine.name;
      _selectedGymId = machine.gymId;
      _selectedMenuIds.addAll(machine.menus.map((menu) => menu.id));
    }
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// ジムと種目を先読みする。2本の SELECT は並行に投げる（§2 の par）。
  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final gymsFuture = _repository.fetchGyms();
      final menusFuture = _repository.fetchMenus();
      final gyms = await gymsFuture;
      final menus = await menusFuture;
      if (!mounted) return;
      setState(() {
        _gyms = gyms;
        _menus = menus;
        // 消えたジムを選んだままにしない（`initialValue` の前提を壊す）。
        if (!gyms.any((gym) => gym.id == _selectedGymId)) {
          _selectedGymId = gyms.length == 1 ? gyms.first.id : null;
        }
        // 消えた種目の選択も落とす。RPC に渡すと `23503` になる。
        final alive = menus.map((menu) => menu.id).toSet();
        _selectedMenuIds.removeWhere((id) => !alive.contains(id));
      });
    } catch (error) {
      if (!mounted) return;
      // 写像は error_mapper（W-05）に任せる。ここで例外を分類しない。
      showError(context, error, onRetry: _load);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// ジムをダイアログで作り、そのまま選択状態にする（§7）。
  Future<void> _createGym() async {
    final gym = await showGymCreateDialog(context, _repository);
    if (gym == null || !mounted) return;
    setState(() {
      _gyms = [..._gyms, gym];
      _selectedGymId = gym.id;
    });
  }

  /// 種目をダイアログで作り、そのまま選択状態にする（§7）。
  ///
  /// ⚠️ **受容したリスク**（§10 #1）: これは器具登録とは別の呼び出しである。
  /// 種目を作った直後に器具登録が失敗すると**種目だけが残る**。
  /// 実害は小さい。残った種目は次回そのまま選べる。
  Future<void> _createMenu() async {
    final menu = await showMenuCreateDialog(context, _repository);
    if (menu == null || !mounted) return;
    setState(() {
      _menus = [..._menus, menu];
      _selectedMenuIds.add(menu.id);
      // 作った種目が絞り込みで隠れないようにする。
      if (_bodyPartFilter != null && _bodyPartFilter != menu.bodyPart) {
        _bodyPartFilter = null;
      }
    });
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    setState(() => _submitted = true);
    // 入力の検証エラーは例外にしない。ここで止めて各欄に出す（§3.5）。
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final gymId = _selectedGymId;
    // ボタンは非活性だが、規則の判定は純関数に一本化しておく。
    if (gymId == null || validateMenuSelection(_selectedMenuIds) != null) return;

    setState(() => _isSaving = true);
    try {
      final machine = widget.machine;
      if (machine == null) {
        await _repository.createMachine(
          gymId: gymId,
          name: _nameController.text,
          menuIds: _selectedMenuIds,
        );
      } else {
        final updated = await _repository.updateMachine(
          machineId: machine.id,
          gymId: gymId,
          name: _nameController.text,
          menuIds: _selectedMenuIds,
        );
        if (updated == null) {
          if (!mounted) return;
          // **戻り値が `null`＝対象が無い**（ERR-MACHINE-006）。例外ではない。
          showAppFailure(context, errMachineNotFound);
          return;
        }
      }
      if (!mounted) return;
      // 一覧へ戻り、呼び出し元に読み直させる。
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showError(context, error, onRetry: _submit);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '器具を編集' : '器具を登録')),
      body: _isLoading
          // 設計（§7.1）は shimmer だが、依存を1つ増やすため W-08 では
          // インジケータで代用する。見せる情報は同じ「読込中」である。
          ? const Center(child: CircularProgressIndicator())
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    // ジムか種目が0件なら登録できない（§4 L-04）。
    final canRegister = canRegisterMachine(_gyms.length, _menus.length);
    final menuError = validateMenuSelection(_selectedMenuIds);
    final visibleMenus = _bodyPartFilter == null
        ? _menus
        : _menus.where((menu) => menu.bodyPart == _bodyPartFilter).toList();

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_gyms.isEmpty)
            MaterialBanner(
              leading: const Icon(Icons.info_outline),
              content: const Text('まずジムを登録してください。'),
              actions: [
                TextButton(onPressed: _createGym, child: const Text('ジムを登録')),
              ],
            ),
          if (_menus.isEmpty)
            MaterialBanner(
              leading: const Icon(Icons.info_outline),
              content: const Text('まず種目を登録してください。'),
              actions: [
                TextButton(onPressed: _createMenu, child: const Text('種目を作成')),
              ],
            ),

          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedGymId,
                  decoration: const InputDecoration(labelText: 'ジム'),
                  items: [
                    for (final gym in _gyms)
                      DropdownMenuItem(value: gym.id, child: Text(gym.name)),
                  ],
                  onChanged: canRegister
                      ? (value) => setState(() => _selectedGymId = value)
                      : null,
                  validator: validateGymSelection,
                ),
              ),
              const SizedBox(width: 8),
              // 画面を離れずにジムを作る（§7）。
              TextButton.icon(
                onPressed: _createGym,
                icon: const Icon(Icons.add),
                label: const Text('新しいジム'),
              ),
            ],
          ),

          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            enabled: canRegister,
            maxLength: kMaxMachineNameLength,
            decoration: const InputDecoration(labelText: '器具名'),
            validator: validateMachineName,
          ),

          const SizedBox(height: 8),
          Text('種目（1件以上）', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          // 部位は**種目リストの絞り込み用**である（§7.3）。器具の部位ではない。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<BodyPart>(
              segments: [
                for (final part in BodyPart.values)
                  ButtonSegment(value: part, label: Text(part.label)),
              ],
              selected: _bodyPartFilter == null
                  ? const <BodyPart>{}
                  : {_bodyPartFilter!},
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(
                () => _bodyPartFilter = selection.isEmpty
                    ? null
                    : selection.first,
              ),
            ),
          ),

          const SizedBox(height: 8),
          if (visibleMenus.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('この部位の種目がありません。'),
            )
          else
            for (final menu in visibleMenus)
              CheckboxListTile(
                value: _selectedMenuIds.contains(menu.id),
                title: Text(menu.name),
                subtitle: Text(menu.bodyPart.label),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _selectedMenuIds.add(menu.id);
                  } else {
                    _selectedMenuIds.remove(menu.id);
                  }
                }),
              ),

          // 画面を離れずに種目を作る（§7）。やり方メモも同じダイアログで入れる。
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _createMenu,
              icon: const Icon(Icons.add),
              label: const Text('新しい種目'),
            ),
          ),

          // 選択済みは絞り込みの外に常時出す（§7.2）。部位を切り替えても消えない。
          if (_selectedMenuIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final menu in _menus.where(
                  (menu) => _selectedMenuIds.contains(menu.id),
                ))
                  InputChip(
                    label: Text('${menu.name}（${menu.bodyPart.label}）'),
                    onDeleted: () =>
                        setState(() => _selectedMenuIds.remove(menu.id)),
                  ),
              ],
            ),
          ],

          // 種目0件は [登録] を押させない。押す前に理由を出す（ERR-MACHINE-003）。
          if (_submitted && menuError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                menuError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),

          const SizedBox(height: 24),
          FilledButton(
            // ジム未選択・種目0件・保存中は押せない（§7・二重送信防止）。
            onPressed: (!canRegister || _isSaving || _selectedGymId == null ||
                    menuError != null)
                ? null
                : _submit,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditing ? '更新' : '登録'),
          ),
        ],
      ),
    );
  }
}

/// ジム作成ダイアログ（C-10・§7）。作成できたら [Gym] を返す。
///
/// **器具登録の RPC には含めない。** 別の呼び出しである。
Future<Gym?> showGymCreateDialog(
  BuildContext context,
  MachineRepository repository,
) => showDialog<Gym>(
  context: context,
  builder: (_) => _GymCreateDialog(repository: repository),
);

/// 種目作成ダイアログ（C-06・§7）。作成できたら [TrainingMenu] を返す。
///
/// ⚠️ **受容したリスク**（§10 #1）: 器具登録とは別トランザクションである。
/// 種目を作った直後に器具登録が失敗すると**種目だけが残る**。
/// 実害は小さい。残った種目は次回そのまま選べる。孤児にはならない。
Future<TrainingMenu?> showMenuCreateDialog(
  BuildContext context,
  MachineRepository repository,
) => showDialog<TrainingMenu>(
  context: context,
  builder: (_) => _MenuCreateDialog(repository: repository),
);

class _GymCreateDialog extends StatefulWidget {
  const _GymCreateDialog({required this.repository});

  final MachineRepository repository;

  @override
  State<_GymCreateDialog> createState() => _GymCreateDialogState();
}

class _GymCreateDialogState extends State<_GymCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    try {
      final gym = await widget.repository.createGym(_nameController.text);
      if (!mounted) return;
      Navigator.of(context).pop(gym);
    } catch (error) {
      if (!mounted) return;
      showError(context, error, onRetry: _save);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新しいジム'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          maxLength: kMaxGymNameLength,
          decoration: const InputDecoration(labelText: 'ジム名'),
          validator: validateGymName,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: const Text('作成'),
        ),
      ],
    );
  }
}

class _MenuCreateDialog extends StatefulWidget {
  const _MenuCreateDialog({required this.repository});

  final MachineRepository repository;

  @override
  State<_MenuCreateDialog> createState() => _MenuCreateDialogState();
}

class _MenuCreateDialogState extends State<_MenuCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _howToController = TextEditingController();

  /// 部位（RULE-003）。5値しか選べない。`null` は未選択。
  BodyPart? _bodyPart;

  bool _isSaving = false;
  bool _submitted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _howToController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _submitted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final bodyPart = _bodyPart;
    // 部位は `SegmentedButton` で5値しか選べないが、判定は純関数に置く。
    if (bodyPart == null || validateBodyPart(bodyPart.label) != null) return;

    setState(() => _isSaving = true);
    try {
      final menu = await widget.repository.createMenu(
        name: _nameController.text,
        bodyPart: bodyPart,
        // 空欄のまま作れる（ADR-0021）。FEAT-03 の説明が空欄になるのは許容する。
        howTo: _howToController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(menu);
    } catch (error) {
      if (!mounted) return;
      showError(context, error, onRetry: _save);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bodyPartError = _submitted ? validateBodyPart(_bodyPart?.label) : null;

    return AlertDialog(
      title: const Text('新しい種目'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                maxLength: kMaxMenuNameLength,
                decoration: const InputDecoration(labelText: '種目名'),
                validator: validateMenuName,
              ),
              const SizedBox(height: 8),
              const Text('部位'),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<BodyPart>(
                  segments: [
                    for (final part in BodyPart.values)
                      ButtonSegment(value: part, label: Text(part.label)),
                  ],
                  selected: _bodyPart == null
                      ? const <BodyPart>{}
                      : {_bodyPart!},
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => setState(
                    () => _bodyPart = selection.isEmpty
                        ? null
                        : selection.first,
                  ),
                ),
              ),
              if (bodyPartError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    bodyPartError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _howToController,
                maxLines: 4,
                maxLength: kMaxHowToLength,
                decoration: const InputDecoration(
                  labelText: 'やり方（任意）',
                  hintText: '空のままでも登録できます',
                ),
                validator: validateHowTo,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: const Text('作成'),
        ),
      ],
    );
  }
}
