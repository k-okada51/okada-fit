import 'package:flutter/material.dart';

import '../data/training_repository.dart';
import '../domain/machine.dart';
import '../domain/training_session.dart';
import 'error_snack_bar.dart';

/// 入館記録のボトムシート（FEAT-04 §2.4・§7）。記録できたら `true` を返す。
///
/// **トレーニング記録とは別トランザクションである**（§2.4）。ここが失敗しても
/// 直前のトレーニング記録は巻き戻らない。逆も同じ。相互参照する FK も無い。
///
/// [gyms] は呼び出し元が読んだものを渡す。シートの中で読み直さない。
/// 0件のときは記録できない（`gym_visits.gym_id` は NOT NULL FK・§10 #5）。
Future<bool?> showGymVisitSheet(
  BuildContext context, {
  required TrainingRepository repository,
  required List<Gym> gyms,
  DateTime? today,
}) => showModalBottomSheet<bool>(
  context: context,
  // 時刻の入力で下から要素がせり上がるため、高さを内容に任せる。
  isScrollControlled: true,
  builder: (_) =>
      _GymVisitSheet(repository: repository, gyms: gyms, today: today),
);

class _GymVisitSheet extends StatefulWidget {
  const _GymVisitSheet({
    required this.repository,
    required this.gyms,
    this.today,
  });

  final TrainingRepository repository;
  final List<Gym> gyms;

  /// テストから「今日」を固定するために開けてある。省略時は端末の現在日。
  final DateTime? today;

  @override
  State<_GymVisitSheet> createState() => _GymVisitSheetState();
}

class _GymVisitSheetState extends State<_GymVisitSheet> {
  final _formKey = GlobalKey<FormState>();

  int? _gymId;
  late DateTime _visitDate;

  /// `HH:MM`。**任意項目**なので未入力（null）が正常である。
  String? _visitTime;

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
    _visitDate = _today;
    // ジムが1件しか無いなら選ぶ手間を省く。
    if (widget.gyms.length == 1) _gymId = widget.gyms.first.id;
  }

  Future<void> _pickDate() async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitDate,
      firstDate: DateTime(today.year - 5),
      // **未来日は選ばせない**（§3.3）。ERR-TRAINING-008 へ到達させない。
      lastDate: today,
      helpText: '入館日',
    );
    if (picked == null || !mounted) return;
    setState(() => _visitDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: '入館時刻',
    );
    if (picked == null || !mounted) return;
    // `showTimePicker` は 0〜23時・0〜59分しか返さない。書式を整えるだけでよい。
    setState(() => _visitTime = formatTimeOfDay(picked.hour, picked.minute));
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    setState(() => _submitted = true);
    // 入力の検証エラーは例外にしない。ここで止めて各欄に出す（§6.2）。
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final gymId = _gymId;
    if (gymId == null ||
        validateVisitDate(_visitDate, _today) != null ||
        validateVisitTime(_visitTime) != null) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.repository.addGymVisit(
        gymId: gymId,
        visitDate: _visitDate,
        visitTime: _visitTime,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      // 写像は error_mapper（W-05）に任せる。ここで例外を分類しない。
      showError(context, error, onRetry: _submit);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateError = validateVisitDate(_visitDate, _today);
    final timeError = validateVisitTime(_visitTime);
    final inputError = dateError ?? timeError;

    return Padding(
      // 時刻ピッカーやキーボードに隠れないよう、下端を持ち上げる。
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text('入館を記録', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),

              // ジム0件だと入館記録が一切できない（§10 #5）。
              // ⚠️ **設計との差**: §7 はここにジム登録への導線を出すと定めるが、
              // W-16 では文言だけにする。画面間の導線は後でまとめて足す。
              if (widget.gyms.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '先にジムを登録してください。',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),

              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _gymId,
                decoration: const InputDecoration(labelText: 'ジム'),
                items: [
                  for (final gym in widget.gyms)
                    DropdownMenuItem(value: gym.id, child: Text(gym.name)),
                ],
                onChanged: widget.gyms.isEmpty
                    ? null
                    : (value) => setState(() => _gymId = value),
                // ジム名の検証は W-08 の純関数を使い回す。規則を2本に割らない。
                validator: validateGymSelection,
              ),

              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('入館日'),
                subtitle: Text(formatDateOnly(_visitDate)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _isSaving ? null : _pickDate,
              ),

              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('入館時刻（任意）'),
                // 空欄は正常。`visit_time` は null 許容である（§3.3）。
                subtitle: Text(_visitTime ?? '未入力'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_visitTime != null)
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: '時刻を消す',
                        onPressed: _isSaving
                            ? null
                            : () => setState(() => _visitTime = null),
                      ),
                    const Icon(Icons.schedule_outlined),
                  ],
                ),
                onTap: _isSaving ? null : _pickTime,
              ),

              if (_submitted && inputError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    inputError,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),

              const SizedBox(height: 16),
              FilledButton(
                // ジム未選択・入力不正・保存中は押せない（二重送信防止）。
                onPressed:
                    (widget.gyms.isEmpty ||
                        _gymId == null ||
                        inputError != null ||
                        _isSaving)
                    ? null
                    : _submit,
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('記録する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
