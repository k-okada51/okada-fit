import 'package:flutter/material.dart';

import '../data/machine_repository.dart';
import '../data/training_repository.dart';
import '../domain/machine.dart';
import '../domain/training_session.dart';
import 'body_part_filter_page.dart';
import 'error_snack_bar.dart';
import 'menu_suggestion_page.dart';
import 'training_gym_visit_sheet.dart';

/// SCR-03 トレーニング（FEAT-04）。
///
/// **記録するのは実施の有無だけである**（ADR-0008）。回数・重量の入力欄は無い。
///
/// 操作は3つで、方式が3つとも違う（§1）。
///
/// | 操作 | 遷移 | 方式 |
/// |---|---|---|
/// | セッション＋明細の登録 | T01 | RPC `create_training_session` |
/// | 実行済のトグル | T02 | PostgREST の条件付き update |
/// | 入館記録 | なし | PostgREST の insert |
///
/// ⚠️ **設計との差**: §7 は種目0件のとき SCR-02 の種目登録へ誘導すると定めるが、
/// W-16 では文言だけにする。画面間の導線は後でまとめて足す。
class TrainingRecordPage extends StatefulWidget {
  const TrainingRecordPage({
    super.key,
    this.repository,
    this.machineRepository,
    this.today,
  });

  /// テストから差し替えられるよう開けてある。省略時は共有クライアントを使う。
  final TrainingRepository? repository;

  /// 種目とジムの一覧は W-08 のものを使い回す。同じ SELECT を2か所に書かない。
  final MachineRepository? machineRepository;

  /// テストから「今日」を固定するために開けてある。省略時は端末の現在日。
  final DateTime? today;

  @override
  State<TrainingRecordPage> createState() => _TrainingRecordPageState();
}

class _TrainingRecordPageState extends State<TrainingRecordPage> {
  late final TrainingRepository _repository =
      widget.repository ?? TrainingRepository();
  late final MachineRepository _machineRepository =
      widget.machineRepository ?? MachineRepository();

  List<TrainingMenu> _menus = const [];
  List<Gym> _gyms = const [];

  /// 実施日のセッション。**複数あり得る**（同日の UNIQUE 制約が無い・§10 #2）。
  List<TrainingSession> _sessions = const [];

  /// これから記録する種目。**挿入順が実施順である**（ADR-0021）。
  final _selectedMenuIds = <int>{};

  late DateTime _performedDate;

  /// 通信中の明細 id。同じ行を連打させないためだけに持つ。
  /// **二重反映の担保はここではない。** サーバ側の状態ガードである（§4.2）。
  final _busyDetailIds = <int>{};

  bool _isLoading = true;
  bool _isSaving = false;
  bool _submitted = false;

  /// 端末のローカル日付を基準にする（ADR-0014）。サーバの `CURRENT_DATE` は使わない。
  DateTime get _today {
    final now = widget.today ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    // 既定は当日（§7）。
    _performedDate = _today;
    _load();
  }

  /// 種目・ジム・実施日のセッションを読む。3本の SELECT は並行に投げる。
  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final menusFuture = _machineRepository.fetchMenus();
      final gymsFuture = _machineRepository.fetchGyms();
      final sessionsFuture = _repository.fetchSessions(_performedDate);
      final menus = await menusFuture;
      final gyms = await gymsFuture;
      final sessions = await sessionsFuture;
      if (!mounted) return;
      setState(() {
        _menus = menus;
        _gyms = gyms;
        _sessions = sessions;
        // 消えた種目を選んだままにしない。
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

  /// 実施日を選ぶ。手入力は採らない（§7・書式ゆれを避ける）。
  Future<void> _pickPerformedDate() async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _performedDate,
      firstDate: DateTime(today.year - 5),
      // **未来日は選ばせない**（§3.4）。ERR-TRAINING-001 へ到達させない。
      lastDate: today,
      helpText: '実施日',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _performedDate = DateTime(picked.year, picked.month, picked.day);
      // 日が変われば記録済みの顔ぶれも変わる。選択は持ち越さない。
      _selectedMenuIds.clear();
      _submitted = false;
    });
    await _load();
  }

  /// セッションと明細を登録する（T01）。RPC 1回＝1トランザクション。
  Future<void> _submit() async {
    if (_isSaving) return;
    setState(() => _submitted = true);
    // 入力の検証エラーは例外にしない。ここで止めて画面に出す（§6.2）。
    if (validatePerformedDate(_performedDate, _today) != null) return;
    if (validateSelectedMenus(_selectedMenuIds) != null) return;

    setState(() => _isSaving = true);
    try {
      final created = await _repository.createSession(
        performedDate: _performedDate,
        // 並び順がそのまま実施順（ADR-0021）。列としては持たない。
        // **既定 false で登録する**（§4.1 の T01・ST-01）。
        // 実行済にするのはこの後のチェック操作（T02）である。
        details: [
          for (final menuId in _selectedMenuIds) TrainingDetailInput(menuId),
        ],
      );
      if (!mounted) return;
      setState(() {
        _sessions = [..._sessions, created];
        _selectedMenuIds.clear();
        _submitted = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('記録しました')));
    } catch (error) {
      if (!mounted) return;
      // 全ロールバックされている。入力（選択）はそのまま残す（§2.2）。
      showError(context, error, onRetry: _submit);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 明細を実行済にする（T02・ST-01 → ST-02）。楽観更新する（§7）。
  Future<void> _markDone(
    TrainingSession session,
    TrainingSessionDetail detail,
  ) async {
    if (detail.isDone || _busyDetailIds.contains(detail.id)) return;

    // 先に画面を進める。失敗したら元へ戻す。
    setState(() {
      _busyDetailIds.add(detail.id);
      _sessions = _replaceDetail(session.id, detail.markedDone());
    });

    try {
      final result = await _repository.markDone(
        detailId: detail.id,
        sessionId: session.id,
      );
      if (!mounted) return;
      switch (result) {
        case TrainingToggleResult.transitioned:
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('実行済にしました')));
        case TrainingToggleResult.alreadyDone:
          // **冪等成功。** 既に ST-02 だっただけで、二重反映は起きていない。
          // 画面は既に実行済を出している。何も言わない（§7）。
          break;
        case TrainingToggleResult.notFound:
          // 返却0行かつ存在確認も0行（RLS で不可視を含む）。ERR-TRAINING-004。
          setState(() => _sessions = _replaceDetail(session.id, detail));
          showAppFailure(context, errTrainingNotFound);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _sessions = _replaceDetail(session.id, detail));
      showError(context, error);
    } finally {
      if (mounted) setState(() => _busyDetailIds.remove(detail.id));
    }
  }

  /// 明細を1件差し替えたセッション一覧を作る。楽観更新の前進と巻き戻しに使う。
  List<TrainingSession> _replaceDetail(
    int sessionId,
    TrainingSessionDetail detail,
  ) => [
    for (final session in _sessions)
      session.id == sessionId ? session.withDetail(detail) : session,
  ];

  /// 入館記録のシートを開く（§2.4）。**別トランザクションである。**
  Future<void> _openGymVisitSheet() async {
    final saved = await showGymVisitSheet(
      context,
      repository: _repository,
      gyms: _gyms,
      today: widget.today,
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('入館を記録しました')));
  }

  /// FEAT-02（部位・器具の絞り込み）→ FEAT-03（メニュー提案）へ進む。
  ///
  /// **器具を選ばせてから呼ぶ。** 0件のまま Edge Function を叩くと、
  /// 選ぶものが無いまま課金だけが発生する（FEAT-02 §10 #1）。
  /// 0件のときは前段の確定ボタンが非活性になる。
  Future<void> _openMenuSuggestion() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BodyPartFilterPage(
          selectable: true,
          onSubmit: (bodyPart, machines) {
            if (machines.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MenuSuggestionPage(
                  bodyPart: bodyPart,
                  machines: machines,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('トレーニング'),
        actions: [
          IconButton(
            icon: const Icon(Icons.meeting_room_outlined),
            tooltip: '入館を記録',
            onPressed: _isLoading ? null : _openGymVisitSheet,
          ),
        ],
      ),
      body: _isLoading
          // 設計（§7）は shimmer だが、依存を1つ増やすため W-16 では
          // インジケータで代用する。見せる情報は同じ「読込中」である。
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    // この日に既に登録済みの種目。`uq_tsd_session_menu` に当てないため候補から外す。
    final recorded = recordedMenuIds(_sessions);
    final selectable = _menus
        .where((menu) => !recorded.contains(menu.id))
        .toList();
    final menuError = validateSelectedMenus(_selectedMenuIds);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ListTile(
          leading: const Icon(Icons.event_outlined),
          title: const Text('実施日'),
          subtitle: Text(formatDateOnly(_performedDate)),
          trailing: const Icon(Icons.calendar_today_outlined),
          onTap: _isSaving ? null : _pickPerformedDate,
        ),
        const Divider(height: 1),

        // FEAT-03 への導線。部位と器具を選んでから AI に組ませる。
        // **ここから EXT-01 の課金が始まる**ので、押されたときだけ進む。
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('今日のメニューを組む'),
          subtitle: const Text('部位と器具を選ぶと、登録済みの種目から順番を作ります'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _isSaving ? null : _openMenuSuggestion,
        ),
        const Divider(height: 1),

        if (_menus.isEmpty)
          MaterialBanner(
            leading: const Icon(Icons.info_outline),
            content: const Text('先に種目を登録してください。'),
            actions: [
              TextButton(onPressed: _load, child: const Text('再読み込み')),
            ],
          ),

        // ---- この日の記録（T02 の対象）--------------------------------
        if (_sessions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('この日の記録', style: theme.textTheme.titleSmall),
          ),
          for (final session in _sessions)
            for (final detail in session.details)
              CheckboxListTile(
                value: detail.isDone,
                title: Text(detail.menuName),
                subtitle: Text(detail.isDone ? '実行済' : '未実行'),
                // 通信中の行だけ止める。二重反映の担保はサーバ側（§4.2）。
                onChanged: _busyDetailIds.contains(detail.id)
                    ? null
                    : (checked) => _onToggle(session, detail, checked ?? false),
              ),
        ],

        // ---- 種目を選んで登録（T01 の対象）----------------------------
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('種目を選んで記録する', style: theme.textTheme.titleSmall),
        ),
        if (selectable.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('選べる種目がありません。'),
          )
        else
          for (final menu in selectable)
            CheckboxListTile(
              value: _selectedMenuIds.contains(menu.id),
              title: Text(menu.name),
              subtitle: Text(menu.bodyPart.label),
              // 送信中は選択を触らせない（§7・二重送信防止）。
              onChanged: _isSaving
                  ? null
                  : (checked) => setState(() {
                      if (checked ?? false) {
                        _selectedMenuIds.add(menu.id);
                      } else {
                        _selectedMenuIds.remove(menu.id);
                      }
                    }),
            ),

        // 種目0件は [記録する] を押させない。押す前に理由を出す（ERR-TRAINING-002）。
        if (_submitted && menuError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              menuError,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: (menuError != null || _isSaving) ? null : _submit,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('記録する'),
          ),
        ),
      ],
    );
  }

  /// チェックの向きを見て振り分ける。
  ///
  /// **`true` にするだけである。** ST-02 → ST-01 は許可遷移に無い
  /// （§4.1・§10 #3 が未決）。`Checkbox` は取り消しを期待させる形をしているため、
  /// 黙って無視せず理由を出す（ERR-TRAINING-006）。
  void _onToggle(
    TrainingSession session,
    TrainingSessionDetail detail,
    bool nextIsDone,
  ) {
    if (validateDoneTransition(nextIsDone: nextIsDone) != null) {
      showAppFailure(context, errTrainingReverseTransition);
      return;
    }
    _markDone(session, detail);
  }
}
