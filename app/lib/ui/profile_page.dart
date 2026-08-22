import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/auth_repository.dart';
import '../data/profile_repository.dart';
import '../domain/nutrition.dart';
import '../domain/profile.dart';
import 'error_snack_bar.dart';
import 'food_list_page.dart';
import 'machine_list_page.dart';
import 'theme/app_theme.dart';
import 'theme/design_tokens.dart';
import 'theme/theme_controller.dart';
import 'widgets/surface_card.dart';

/// SCR-05 設定・プロフィール（FEAT-06）。原本は `SCR-05 設定.dc.html`。
///
/// **この画面が設定の入口である**（ADR-0024 §1）。設定・器具登録・食品マスタは
/// 下部ナビに置かない。SCR-00 の歯車からここへ来て、ここから各画面へ辿る。
///
/// 扱う値は3つ。表示名・目標トレーニング回数（月）・体重(kg)。
/// 保存は明示的なボタン押下でだけ起きる。自動保存にしない（FEAT-06 §7）。
///
/// ## デザインに従わない箇所
///
/// | デザイン | ここでの実装 | 根拠 |
/// |---|---|---|
/// | 目標回数が**週**・上限7 | **月・0〜31・既定12** | ADR-0024 §4 #7・RULE-007 |
/// | 表示名が無い | **入れる** | FEAT-06 が扱う3値の1つ |
/// | 下部ナビがある | **出さない** | 設定はタブではない（ADR-0024 §1）。歯車から push する |
/// | 器具の導線だけ | **食品マスタも置く** | FEAT-10（デザインより後に決まった） |
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.authRepository, this.repository});

  /// サインアウトに使う。**置き場所はこの画面**（SCR-00 から移した）。
  final AuthRepository authRepository;

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

  /// 二重タップ防止。
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    // 体重が変わるたびに目標を出し直す。**通信しない**（FEAT-07 §4.5 案(b)）。
    // デバウンスも要らない。純関数の掛け算1回である。
    _weightController.addListener(_onWeightChanged);
    _load();
  }

  @override
  void dispose() {
    _weightController.removeListener(_onWeightChanged);
    _nameController.dispose();
    _targetController.dispose();
    _weightController.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  void _onWeightChanged() => setState(() {});

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
          weightKg: FieldPatch<double>.of(
            parseWeightKg(_weightController.text),
          ),
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

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);
    try {
      await widget.authRepository.signOut();
      // 画面の切り替えは AuthGate が `onAuthStateChange` を受けて行う。
      // ここで Navigator を触らない。
    } catch (error, stackTrace) {
      debugPrintStack(label: 'signOut: $error', stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('サインアウトできませんでした。時間をおいて試してください。')),
      );
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// キーボードを閉じる。
  ///
  /// **iOS の数値キーボードには改行キーが無い。** `textInputAction` を何にしても
  /// 閉じるキーは出ないため、閉じる手段を画面側で用意する必要がある。
  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  /// キーボードのバーから保存する。先に閉じてから保存する。
  ///
  /// 閉じてからにするのは、検証エラーが出たときに該当欄が見えるようにするため。
  /// キーボードが載ったままだと、エラー文がその裏に隠れる。
  Future<void> _saveFromKeyboardBar() async {
    _dismissKeyboard();
    await _save();
  }

  /// 入力欄を差し替える。**カーソルは末尾に置く。**
  ///
  /// `controller.text = ...` だけだと選択位置が「無し」になり、± を押した後に
  /// キーボードへ戻ったときカーソルが消えて見える。
  void _replace(TextEditingController controller, String next) {
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  /// ± ボタンで体重を動かす。空欄・読めない値のときは呼ばれない（ボタンが非活性）。
  void _stepWeight(double deltaKg) {
    final next = stepWeightText(_weightController.text, deltaKg);
    if (next == null) return;
    _replace(_weightController, next);
  }

  void _stepTarget(int delta) {
    _replace(
      _targetController,
      stepTargetTrainingCountText(_targetController.text, delta),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.pageBg,
      body: Center(
        child: ConstrainedBox(
          // SCR-05 は push で開くため [AppShell] の外にいる。幅の制約を自分で持つ。
          constraints: const BoxConstraints(maxWidth: Dimens.maxContentWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.symmetric(vertical: BorderSide(color: t.hairline)),
            ),
            child: Column(
              children: [
                _buildHeader(t),
                Expanded(
                  // 下端のホームインジケータに文字が潜らないようにする。
                  // 左右は [Dimens.maxContentWidth] の枠が受け持つ。
                  child: SafeArea(
                    top: false,
                    child: _isLoading
                        // 設計（FEAT-06 §7）は shimmer だが、依存を1つ増やすため
                        // インジケータで代用する。見せる情報は同じ「読込中」である。
                        ? const Center(child: CircularProgressIndicator())
                        : _profile == null
                        ? _buildLoadFailed(t)
                        : _buildForm(t),
                  ),
                ),
                // キーボードが出ている間だけ、その上に確定の手段を置く。
                // `Scaffold` が下端を持ち上げるので、ここに置けば鍵盤の直上になる。
                if (MediaQuery.viewInsetsOf(context).bottom > 0)
                  _buildKeyboardBar(t),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ヘッダ。デザインの `height:56px`・`gap:11px`・`←` ＋「設定」。
  ///
  /// `AppBar` を使わない。デザインは `navBg`（地色より濃い半透明）＋下罫線で、
  /// `AppBar` の既定と塗りが違う。SCR-00 のヘッダと高さも揃える。
  Widget _buildHeader(DesignTokens t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.navBg,
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: Dimens.headerHeight,
          child: Row(
            spacing: 3,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, size: 20),
                color: t.textColor.withValues(alpha: 0.7),
                tooltip: '戻る',
                // 既定の48pxだと `←` が左に寄りすぎる。デザインは左余白20px。
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
              ),
              Text(
                '設定',
                style: TextStyle(
                  color: t.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// キーボードの直上に出す確定バー。
  ///
  /// **デザインには無い。** `SCR-05 設定.dc.html` はブラウザのモックで、
  /// iOS の数値キーボードに閉じるキーが無いことを写せていない。
  /// 実機では体重を打った後にキーボードから抜けられなくなる。
  ///
  /// 「保存」は画面下の CTA と同じ [_save] を呼ぶ。**別経路を作らない。**
  Widget _buildKeyboardBar(DesignTokens t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.navBg,
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 8),
            TextButton(
              onPressed: _dismissKeyboard,
              child: Text(
                '閉じる',
                style: TextStyle(
                  color: t.textColor.withValues(alpha: 0.72),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _isSaving ? null : _saveFromKeyboardBar,
              style: FilledButton.styleFrom(
                minimumSize: const Size(72, 34),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Dimens.radiusInput),
                ),
              ),
              child: const Text(
                '保存',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  /// 読込に失敗した状態。入力欄を出さない（何を保存するのか決まらないため）。
  Widget _buildLoadFailed(DesignTokens t) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 16,
      children: [
        Text(
          'プロフィールを読み込めませんでした。',
          style: TextStyle(color: t.textColor, fontSize: 14),
        ),
        OutlinedButton(onPressed: _load, child: const Text('再試行')),
      ],
    ),
  );

  Widget _buildForm(DesignTokens t) {
    return Form(
      key: _formKey,
      // 欄の外をどこでも叩けば閉じる。バーと合わせて逃げ道を2つにする。
      // `translucent` にしないと、カードの無い余白での指が拾えない。
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: ListView(
          // 指で送っても閉じる。
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          // デザインの `main` の `padding:18px 20px 28px`。
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            _Section(
              title: 'プロフィール',
              child: SurfaceCard(
                radius: Dimens.radiusCard,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 17,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 14,
                  children: [
                    _buildNameField(),
                    _buildWeightField(t),
                    _buildTargetField(),
                    _buildProteinPreview(t),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            _Section(
              title: 'ジム・器具',
              child: SettingsRow(
                title: '器具の登録・管理',
                note: 'ジムのマシンを追加・削除する',
                onTap: () => _open(const MachineListPage()),
              ),
            ),
            const SizedBox(height: 22),
            _Section(
              // ⚠️ デザインに無い節である。FEAT-10（食品マスタ）はデザインより
              // 後に決まった（2026-08-22）。ADR-0024 §1 の「食品マスタは歯車 →
              // SCR-05 から辿る」に従い、ここに置く。
              title: '食事',
              child: SettingsRow(
                title: '食品マスタ',
                note: '食品の一覧・編集・CSV取込',
                onTap: () => _open(const FoodListPage()),
              ),
            ),
            const SizedBox(height: 22),
            _Section(title: '表示設定', child: const _ThemeModeRow()),
            const SizedBox(height: 22),
            _buildSaveButton(t),
            const SizedBox(height: 22),
            // 保存ボタンより**下**に置く。デザインには無い節だが、サインアウトを
            // 「保存する」の隣に並べると押し間違いが起きる。
            _Section(
              title: 'アカウント',
              child: SettingsRow(
                title: _isSigningOut ? 'サインアウトしています…' : 'サインアウト',
                note: '次に開いたときログインし直す',
                onTap: _isSigningOut ? null : _signOut,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 表示名。**デザインには無い**が FEAT-06 が扱う3値の1つ。
  ///
  /// ± が付かないので入力欄だけを置く。
  Widget _buildNameField() {
    return _Field(
      label: '表示名',
      child: _FieldInput(
        controller: _nameController,
        maxLength: kMaxNameLength,
        validator: validateName,
      ),
    );
  }

  /// 体重。0.1kg 刻みの ± が付く（デザイン）。
  ///
  /// **空欄のときは ± を非活性にする。** 体重に既定値を置かないと決めている
  /// （FEAT-06 §4.2）。押しただけで利用者が入れていない値が入るのを避ける。
  Widget _buildWeightField(DesignTokens t) {
    final canStep = stepWeightText(_weightController.text, 0) != null;

    return _Field(
      label: '体重',
      hint: canStep
          ? '${kWeightStepKg.toStringAsFixed(1)}kg単位で調整できます'
          // 未設定の誘導（FEAT-06 §7）。設計は MaterialBanner を指定しているが、
          // 役割（未設定であることと、入れれば目標が出ることを伝える）を保った
          // まま、置き場所を欄の直下に移した。設定画面の先頭に警告帯を出すのは
          // デザインの流儀から外れる（ADR-0024「見た目はデザイン・中身は設計」）。
          : '体重を入れると、1日の目標タンパク質が出ます',
      hintColor: canStep ? null : t.warn,
      child: Row(
        // 検証エラーが出ると入力欄だけが縦に伸びる。± を上端に留める。
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          _StepButton(
            symbol: '−',
            tooltip: '0.1kg 減らす',
            onPressed: canStep ? () => _stepWeight(-kWeightStepKg) : null,
          ),
          Expanded(
            child: _FieldInput(
              controller: _weightController,
              focusNode: _weightFocus,
              suffix: 'kg',
              hintText: '未設定',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // 3桁＋小数第1位まで。`numeric(6,1)` の精度に合わせる（ADR-0022）。
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d?)?$')),
              ],
              validator: validateWeightKg,
            ),
          ),
          _StepButton(
            symbol: '＋',
            tooltip: '0.1kg 増やす',
            onPressed: canStep ? () => _stepWeight(kWeightStepKg) : null,
          ),
        ],
      ),
    );
  }

  /// 目標トレーニング回数。
  ///
  /// ⚠️ **デザインは「回/週」・上限7だが、月・0〜31 が正**（ADR-0024 §4 #7）。
  Widget _buildTargetField() {
    return _Field(
      label: '目標トレーニング回数（月）',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          _StepButton(
            symbol: '−',
            tooltip: '1回 減らす',
            onPressed: () => _stepTarget(-1),
          ),
          Expanded(
            child: _FieldInput(
              controller: _targetController,
              suffix: '回 / 月',
              keyboardType: TextInputType.number,
              // 文字種は formatter で縛り、範囲は validator で弾く（FEAT-06 §3.4）。
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: validateTargetTrainingCount,
            ),
          ),
          _StepButton(
            symbol: '＋',
            tooltip: '1回 増やす',
            onPressed: () => _stepTarget(1),
          ),
        ],
      ),
    );
  }

  /// 1日の目標タンパク質（FEAT-07 §7・ADR-0024 §5 A）。
  ///
  /// **通信しない。** 入力中の体重をそのまま純関数に渡す（FEAT-07 §4.5 案(b)）。
  /// 保存前でも値が出る。保存後は同じ関数が DB の値に適用されるため一致する。
  Widget _buildProteinPreview(DesignTokens t) {
    final target = calcTargetProteinG(parseWeightKg(_weightController.text));

    // 未設定・不正値はどちらも「—」。SCR-05 では出し分けない（FEAT-07 §7）。
    // 不正値は validator が先に弾くため、DB の既存データ以外では起きない。
    final (goalText, perMealText) = switch (target) {
      ProteinTargetOk(:final targetG) => (
        _formatG(targetG),
        _formatG(proteinPerMealG(targetG)),
      ),
      _ => ('—', '—'),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.ctaSoft,
        borderRadius: BorderRadius.circular(Dimens.radiusCta),
        border: Border.all(color: t.accentBorder),
      ),
      child: Column(
        spacing: 12,
        children: [
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(
                      '1日の目標タンパク質',
                      style: TextStyle(
                        color: t.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      // 係数はハードコードしない。定数から出す（FEAT-07 §4.1）。
                      '体重 × ${_formatG(proteinGPerKg)}g で自動算出',
                      style: TextStyle(
                        color: t.textColor.withValues(alpha: 0.72),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                spacing: 2,
                children: [
                  Text(
                    goalText,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: -0.9, // 30px × -0.03em
                    ).merge(kTabularFigures).copyWith(color: t.accent),
                  ),
                  Text(
                    'g',
                    style: TextStyle(
                      color: t.accent.withValues(alpha: 0.75),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Divider(height: 1, thickness: 1, color: t.accentBorder),
          Row(
            children: [
              Expanded(
                child: Text(
                  '1食あたりの目安（$kMealsPerDay食）',
                  style: TextStyle(
                    color: t.textColor.withValues(alpha: 0.75),
                    fontSize: 11,
                  ),
                ),
              ),
              Text(
                '${perMealText}g',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ).merge(kTabularFigures).copyWith(color: t.accent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 「保存する」。デザインの `height:52px`・`radius:14`・`ctaBg`。
  ///
  /// ダークの背景はグラデーションで `FilledButton` では出せない。SCR-00 の
  /// CTA と同じく `Ink` を自分で敷く。
  Widget _buildSaveButton(DesignTokens t) {
    return SizedBox(
      height: 52,
      child: Ink(
        decoration: BoxDecoration(
          // 保存中は沈める。押せないことを色でも示す。
          gradient: _isSaving ? null : t.ctaGradient,
          color: _isSaving ? t.hoverSurface : t.ctaColor,
          borderRadius: BorderRadius.circular(Dimens.radiusCta),
        ),
        child: InkWell(
          // 保存中は押せなくする（二重送信防止・FEAT-06 §7）。
          onTap: _isSaving ? null : _save,
          borderRadius: BorderRadius.circular(Dimens.radiusCta),
          child: Center(
            child: _isSaving
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.textColor,
                    ),
                  )
                : Text(
                    '保存する',
                    style: TextStyle(
                      color: t.ctaFg,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 節。見出し（12px/600・不透明度.72）と中身を `gap:12` で積む。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Text(
          title,
          style: TextStyle(
            color: t.textColor.withValues(alpha: 0.72),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        child,
      ],
    );
  }
}

/// 入力欄1つ分。ラベル・中身・補足を `gap:7` で積む（デザイン）。
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.child,
    this.hint,
    this.hintColor,
  });

  final String label;
  final Widget child;

  /// 欄の下の1行。省略できる。
  final String? hint;

  /// [hint] の色。省略すると本文色を薄めたものになる。警告のときだけ渡す。
  final Color? hintColor;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hint = this.hint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 7,
      children: [
        Text(
          label,
          style: TextStyle(
            color: t.textColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        child,
        if (hint != null)
          Text(
            hint,
            style: TextStyle(
              color: hintColor ?? t.textColor.withValues(alpha: 0.68),
              fontSize: 11,
            ),
          ),
      ],
    );
  }
}

/// デザインの入力欄。高さ46・角丸11・`inputBg`・本文17px/700・数字は等幅。
///
/// 枠と塗りは `inputDecorationTheme`（`app_theme.dart`）が持っている。
/// ここでは寸法と書体だけを足す。
class _FieldInput extends StatelessWidget {
  const _FieldInput({
    required this.controller,
    this.focusNode,
    this.suffix,
    this.hintText,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.validator,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;

  /// 単位。デザインの `kg`・`回 / 週`（本アプリは `回 / 月`）。
  final String? suffix;

  final String? hintText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      validator: validator,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ).merge(kTabularFigures).copyWith(color: t.textColor),
      decoration: InputDecoration(
        isDense: true,
        // 上下13＋本文20 でデザインの46pxになる。
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 13,
        ),
        hintText: hintText,
        hintStyle: TextStyle(
          color: t.textColor.withValues(alpha: 0.4),
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        suffixText: suffix,
        suffixStyle: TextStyle(
          color: t.textColor.withValues(alpha: 0.72),
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        // 文字数カウンタは出さない。デザインに無く、欄の下が二段になる。
        counterText: '',
      ),
    );
  }
}

/// ± ボタン。デザインの `46×46`・角丸11・罫線1px・記号18px。
///
/// [onPressed] が `null` のときは薄くして押せなくする。
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.symbol,
    required this.tooltip,
    required this.onPressed,
  });

  final String symbol;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final borderRadius = BorderRadius.circular(Dimens.radiusInput);
    final isEnabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: t.hairline),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: borderRadius,
            child: SizedBox.square(
              dimension: 46,
              child: Center(
                child: Text(
                  symbol,
                  style: TextStyle(
                    color: t.textColor.withValues(alpha: isEnabled ? 1 : 0.3),
                    fontSize: 18,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 表示モードの切替（ADR-0024 §3）。
///
/// **置き場所はここ1か所だけ。** デザインは全画面の右上にボタンを置いているが、
/// それはモックを見比べるためのものと解釈した。各画面の右上を空けられる。
///
/// 切り替えた値は端末に保存される。次回起動でも維持される。
class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final controller = ThemeScope.of(context);
    final isDark = controller.themeMode == ThemeMode.dark;

    void toggle() =>
        controller.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);

    return SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.all(16),
      onTap: toggle,
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  'ダークモード',
                  style: TextStyle(
                    color: t.textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '夜のジムでも見やすい配色',
                  style: TextStyle(
                    color: t.textColor.withValues(alpha: 0.72),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // 読み上げには `Switch` の役割を持たせる。見た目だけ自前で描く。
          Semantics(
            toggled: isDark,
            label: 'ダークモード',
            child: _PillSwitch(value: isDark, onChanged: (_) => toggle()),
          ),
        ],
      ),
    );
  }
}

/// デザインのトグル。`52×30`・角丸999・つまみ24px・白＋影。
///
/// Material の `Switch` を使わない。寸法もつまみの色も別物で、並べると浮く。
class _PillSwitch extends StatelessWidget {
  const _PillSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value ? t.fill : t.switchTrackOff,
          borderRadius: BorderRadius.circular(Dimens.radiusChip),
        ),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(Dimens.radiusChip),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.3),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 表示用のタンパク質量。**整数 g に丸める。**
///
/// `domain/nutrition.dart` は小数第1位まで持つ。表示の丸めは UI 層の担当で
/// あると同ファイルが明記している（FEAT-07 §4.2）。
String _formatG(double value) => value.round().toString();
