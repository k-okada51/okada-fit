import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/profile_repository.dart';
import '../domain/profile.dart';
import 'error_snack_bar.dart';

/// SCR-05 設定・プロフィール（FEAT-06）。
///
/// 扱う値は3つだけ。表示名・目標トレーニング回数（月）・体重(kg)。
/// 保存は明示的なボタン押下でだけ起きる。自動保存にしない（FEAT-06 §7）。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.repository});

  /// テストから差し替えられるよう開けてある。省略時は共有クライアントを使う。
  final ProfileRepository? repository;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileRepository _repository =
      widget.repository ?? ProfileRepository();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  final _weightController = TextEditingController();
  final _weightFocus = FocusNode();

  /// 読み込み済みの行。`null` の間は読込中か、読込に失敗している。
  Profile? _profile;

  bool _isLoading = true;

  /// 保存中。ボタンを無効にして二重送信を防ぐ（FEAT-06 §7）。
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _weightController.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  /// 本人の行を読んでフォームへ流し込む。
  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final profile = await _repository.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _applyToForm(profile);
      });
    } catch (error) {
      if (!mounted) return;
      // 写像は error_mapper（W-05）に任せる。ここで例外を分類しない。
      showError(context, error, onRetry: _load);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 応答の値で入力欄を上書きする。トリムや丸めの結果を画面に反映するため。
  void _applyToForm(Profile profile) {
    _nameController.text = profile.name;
    // DB が null でも 12 が入っている（kDefaultTargetTrainingCount）。
    _targetController.text = profile.targetTrainingCount.toString();
    // 体重の未設定は空欄で見せる。0 と混同させない。
    _weightController.text = profile.weightKg?.toStringAsFixed(1) ?? '';
  }

  Future<void> _save() async {
    if (_isSaving) return;
    // 入力の検証エラーは例外にしない。ここで止めて各欄に出す（FEAT-06 §2）。
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    try {
      final saved = await _repository.updateProfile(
        ProfileUpdate(
          name: FieldPatch<String>.of(_nameController.text),
          targetTrainingCount: FieldPatch<int>.of(
            parseTargetTrainingCount(_targetController.text),
          ),
          // 空欄なら null が入り、体重が未設定に戻る（FEAT-06 §4.3）。
          weightKg: FieldPatch<double>.of(parseWeightKg(_weightController.text)),
        ),
      );
      if (!mounted) return;
      setState(() {
        _profile = saved;
        _applyToForm(saved);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('保存しました')));
    } catch (error) {
      if (!mounted) return;
      // 入力値は消さない。書き直しをやり直させないため（FEAT-06 §7）。
      showError(context, error, onRetry: _save);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定・プロフィール')),
      body: _isLoading
          // 設計（FEAT-06 §7）は shimmer だが、依存を1つ増やすため W-06 では
          // インジケータで代用する。見せる情報は同じ「読込中」である。
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
          ? _buildLoadFailed()
          : _buildForm(),
    );
  }

  /// 読込に失敗した状態。入力欄を出さない（何を保存するのか決まらないため）。
  Widget _buildLoadFailed() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('プロフィールを読み込めませんでした。'),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: _load, child: const Text('再試行')),
      ],
    ),
  );

  Widget _buildForm() {
    final isWeightUnset = _profile?.isWeightUnset ?? false;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 体重が未設定のときだけ出す誘導（FEAT-06 §7）。
          // 体重は FEAT-07（必要タンパク質量）の唯一の入力である。
          if (isWeightUnset)
            MaterialBanner(
              leading: const Icon(Icons.info_outline),
              content: const Text('体重を設定するとタンパク質の目標が計算されます。'),
              actions: [
                TextButton(
                  onPressed: _weightFocus.requestFocus,
                  child: const Text('入力する'),
                ),
              ],
            ),
          TextFormField(
            controller: _nameController,
            maxLength: kMaxNameLength,
            decoration: const InputDecoration(labelText: '表示名'),
            validator: validateName,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _targetController,
            keyboardType: TextInputType.number,
            // 文字種は formatter で縛り、範囲は validator で弾く（FEAT-06 §3.4）。
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '目標トレーニング回数',
              suffixText: '回/月',
            ),
            validator: validateTargetTrainingCount,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _weightController,
            focusNode: _weightFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // 3桁＋小数第1位まで。`numeric(6,1)` の精度に合わせる（ADR-0022）。
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d?)?$')),
            ],
            decoration: const InputDecoration(
              labelText: '体重',
              suffixText: 'kg',
              hintText: '未設定',
            ),
            validator: validateWeightKg,
          ),
          const SizedBox(height: 24),
          FilledButton(
            // 保存中は押せなくする（二重送信防止・FEAT-06 §7）。
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
    );
  }
}
