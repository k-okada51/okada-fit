import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/error_mapper.dart';
import '../data/meal_analyze_repository.dart';
import '../data/meal_log_repository.dart';
import '../domain/meal_image.dart';
import '../domain/meal_nutrition.dart';
import 'error_snack_bar.dart';
import 'theme/app_theme.dart';
import 'theme/design_tokens.dart';
import 'widgets/surface_card.dart';

/// SCR-04 食事記録（FEAT-08）。下部ナビの「P記録」。
///
/// ## 進み方は一本道（§7）
///
/// ```text
/// 撮影 → プレビュー → ［解析する］ → 結果 → ［記録する］
///                          ↑                    ↓
///                      ［撮り直す］ ←───────────┘
/// ```
///
/// **解析後の操作は［記録する］と［撮り直す］の2つだけ**（ADR-0015）。
/// 手入力の経路は持たない。利用者はタンパク質量を知らない。それを知るために
/// 写真を撮る。よって手入力は代替手段にならず、**AI が失敗した食事は
/// 記録できない**。要件（NFR-AVAIL-05）との齟齬は設計側で申し送り済み。
///
/// **自動送信・自動保存はしない**（ADR-0003）。端末外へ出るのは
/// ［解析する］を押した1回だけである。
class MealCapturePage extends StatefulWidget {
  const MealCapturePage({
    super.key,
    this.analyzeRepository,
    this.logRepository,
    this.imagePicker,
    this.now,
  });

  /// テストから差し替えられるよう開けてある。
  final MealAnalyzeRepository? analyzeRepository;
  final MealLogRepository? logRepository;
  final ImagePicker? imagePicker;

  /// 「いま」。省略時は端末時刻（ADR-0014）。
  final DateTime Function()? now;

  @override
  State<MealCapturePage> createState() => _MealCapturePageState();
}

class _MealCapturePageState extends State<MealCapturePage> {
  late final _analyze = widget.analyzeRepository ?? MealAnalyzeRepository();
  late final _logs = widget.logRepository ?? MealLogRepository();
  late final _picker = widget.imagePicker ?? ImagePicker();

  /// 撮った写真。**メモリ上だけ**。どこにも書かない（ADR-0003）。
  Uint8List? _bytes;
  String? _mimeType;

  /// 解析結果。端末のウィジェット状態だけで持つ（§7）。
  MealNutrition? _result;

  /// 入力系のエラー。SnackBar ではなく結果領域に出す（§7）。
  ImageInputError? _inputError;

  /// AI系のエラー文言。結果領域に出す。SnackBar も別途出す（§7）。
  String? _analyzeError;

  bool _isAnalyzing = false;
  bool _isSaving = false;
  bool _isLoadingLogs = true;

  List<MealLogEntry> _today = const [];

  DateTime get _nowValue => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  Future<void> _loadToday() async {
    setState(() => _isLoadingLogs = true);
    try {
      final rows = await _logs.fetchByDate(_nowValue);
      if (!mounted) return;
      setState(() => _today = rows);
    } catch (error) {
      if (!mounted) return;
      showError(context, error, onRetry: _loadToday);
    } finally {
      if (mounted) setState(() => _isLoadingLogs = false);
    }
  }

  /// 撮影または選択。**縮小は `image_picker` に任せる**（ADR-0003）。
  ///
  /// `maxWidth`/`maxHeight` にどちらも 1024 を渡すと、縦横比を保ったまま
  /// 長辺が 1024 に収まる。プラットフォーム側で縮小されるので速い。
  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: kMaxImageEdgePx.toDouble(),
        maxHeight: kMaxImageEdgePx.toDouble(),
        // 実測 300KB 前後に収めるための圧縮率。1MB の上限に対し十分な余裕がある。
        imageQuality: 85,
      );
      // 利用者が閉じただけ。**失敗ではない**ので何も出さない。
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final mimeType = file.mimeType ?? mimeTypeFromPath(file.path);

      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _mimeType = mimeType;
        _result = null;
        _analyzeError = null;
        // 送る前にここで弾く。通信も課金も起きない（§3.4）。
        _inputError = mimeType == null
            ? const ImageInputError('ERR-MEAL-002', 'JPEG・PNG・WebP の写真を選んでください。')
            : validateImageInput(bytes, mimeType);
      });
    } catch (error) {
      if (!mounted) return;
      showError(context, error);
    }
  }

  void _reset() {
    setState(() {
      _bytes = null;
      _mimeType = null;
      _result = null;
      _inputError = null;
      _analyzeError = null;
    });
  }

  /// ［解析する］。**ここで初めて端末外へ出る。**
  Future<void> _runAnalyze() async {
    final bytes = _bytes;
    final mimeType = _mimeType;
    if (bytes == null || mimeType == null || _inputError != null) return;
    if (_isAnalyzing) return;

    setState(() {
      _isAnalyzing = true;
      _analyzeError = null;
    });
    try {
      final result = await _analyze.analyze(bytes, mimeType);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      final failure = mapError(error);
      // 結果領域と SnackBar の両方に出す（§7）。
      // **自動で再送しない。** 再試行は利用者が押したときだけ（二重課金の抑止）。
      setState(() => _analyzeError = failure.message);
      showAppFailure(context, failure);
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  /// ［記録する］。楽観的更新はしない（§7）。
  Future<void> _save() async {
    final result = _result;
    if (result == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await _logs.insert(result, eatenAt: _nowValue);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('記録しました')));
      _reset();
      await _loadToday();
    } catch (error) {
      if (!mounted) return;
      showError(context, error, onRetry: _save);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      children: [
        _Header(title: '食事を記録する'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              if (_bytes == null) _buildEmpty(t) else _buildPreview(t),
              const SizedBox(height: 18),
              if (_inputError != null) _buildMessageCard(t, _inputError!.message, t.warn),
              if (_analyzeError != null) _buildMessageCard(t, _analyzeError!, t.warn),
              if (_result != null) ...[
                _buildResult(t, _result!),
                const SizedBox(height: 18),
              ],
              _buildTodayList(t),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(DesignTokens t) {
    return SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            '食事の写真から推定します',
            style: TextStyle(
              color: t.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '撮った写真は解析のために1回送るだけで、端末にもサーバにも残しません。',
            style: TextStyle(
              color: t.textColor.withValues(alpha: 0.72),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          _Cta(label: '写真を撮る', onPressed: () => _pick(ImageSource.camera)),
          OutlinedButton(
            onPressed: () => _pick(ImageSource.gallery),
            child: const Text('ライブラリから選ぶ'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(DesignTokens t) {
    final canAnalyze = _inputError == null && !_isAnalyzing;

    return SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Dimens.radiusCta),
            // ファイルパスではなくバイト列から描く。端末に書き出していないため。
            child: Image.memory(_bytes!, fit: BoxFit.cover, height: 220),
          ),
          if (_isAnalyzing)
            Column(
              spacing: 8,
              children: [
                const Center(child: CircularProgressIndicator()),
                Text(
                  '解析しています。20秒ほどかかることがあります。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textColor.withValues(alpha: 0.72),
                    fontSize: 11,
                  ),
                ),
              ],
            )
          else ...[
            if (_result == null)
              _Cta(label: '解析する', onPressed: canAnalyze ? _runAnalyze : null),
            OutlinedButton(onPressed: _reset, child: const Text('撮り直す')),
          ],
        ],
      ),
    );
  }

  Widget _buildResult(DesignTokens t, MealNutrition n) {
    return SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Text(
            n.foodName.isEmpty ? '推定結果' : n.foodName,
            style: TextStyle(
              color: t.textColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (n.dishNames.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in n.dishNames)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: t.ctaSoft,
                      borderRadius: BorderRadius.circular(Dimens.radiusChip),
                      border: Border.all(color: t.accentBorder),
                    ),
                    child: Text(
                      name,
                      style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          // **表示するだけ。入力欄にしない**（ADR-0015）。値は修正できない。
          _NutritionRow(label: 'タンパク質', value: n.proteinG, unit: 'g', emphasized: true),
          _NutritionRow(label: 'カロリー', value: n.caloriesKcal, unit: 'kcal'),
          _NutritionRow(label: '糖質', value: n.sugarG, unit: 'g'),
          _NutritionRow(
            label: '脂質',
            value: n.fatG,
            unit: 'g',
            // 脂質だけに注記を出す（§4）。外食の MAPE は 32.7% で既知の弱点。
            note: '揚げ物・炒め物では実際より少なく出る傾向があります',
          ),
          if (isAtwaterInconsistent(n))
            _buildMessageCard(t, '数値の整合が取れていない可能性があります。ご確認ください。', t.warn),
          const SizedBox(height: 2),
          _Cta(label: '記録する', onPressed: _isSaving ? null : _save, busy: _isSaving),
        ],
      ),
    );
  }

  Widget _buildMessageCard(DesignTokens t, String message, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Dimens.radiusCta),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(message, style: TextStyle(color: t.textColor, fontSize: 12)),
    );
  }

  Widget _buildTodayList(DesignTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Text(
          '今日の記録',
          style: TextStyle(
            color: t.textColor.withValues(alpha: 0.72),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_isLoadingLogs)
          const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
        else if (_today.isEmpty)
          Text(
            'まだ記録がありません。',
            style: TextStyle(color: t.textColor.withValues(alpha: 0.5), fontSize: 12),
          )
        else
          for (final entry in _today)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                radius: Dimens.radiusCta,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      entry.eatenTime ?? '--:--',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)
                          .merge(kTabularFigures)
                          .copyWith(color: t.textColor.withValues(alpha: 0.6)),
                    ),
                    const Spacer(),
                    Text(
                      'P ${entry.proteinG.round()}g',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)
                          .merge(kTabularFigures)
                          .copyWith(color: t.accent),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${entry.caloriesKcal.round()}kcal',
                      style: const TextStyle(fontSize: 12)
                          .merge(kTabularFigures)
                          .copyWith(color: t.textColor.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// 栄養1項目の行。**表示専用**（ADR-0015）。
class _NutritionRow extends StatelessWidget {
  const _NutritionRow({
    required this.label,
    required this.value,
    required this.unit,
    this.emphasized = false,
    this.note,
  });

  final String label;
  final double value;
  final String unit;

  /// タンパク質だけ強調する。本機能の主目的である。
  final bool emphasized;

  /// 値の下に出す小さな注記。
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final note = this.note;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 3,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: t.textColor.withValues(alpha: 0.75),
                  fontSize: emphasized ? 13 : 12,
                  fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            Text(
              _format(value),
              style: TextStyle(
                fontSize: emphasized ? 24 : 15,
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
                height: 1,
              ).merge(kTabularFigures).copyWith(
                color: emphasized ? t.accent : t.textColor,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: TextStyle(
                color: t.textColor.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (note != null)
          Text(
            note,
            style: TextStyle(
              color: t.textColor.withValues(alpha: 0.55),
              fontSize: 10,
            ),
          ),
      ],
    );
  }

  /// 小数第1位まで。0 のときは `0` と出す。
  String _format(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }
}

/// デザインの CTA。SCR-00 の `HomeRecordCta` と同じ塗り方。
class _Cta extends StatelessWidget {
  const _Cta({required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onPressed != null;

    return SizedBox(
      height: 52,
      child: Ink(
        decoration: BoxDecoration(
          gradient: enabled ? t.ctaGradient : null,
          color: enabled ? t.ctaColor : t.hoverSurface,
          borderRadius: BorderRadius.circular(Dimens.radiusCta),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Dimens.radiusCta),
          child: Center(
            child: busy
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: t.textColor),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: enabled ? t.ctaFg : t.textColor.withValues(alpha: 0.4),
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

/// タブ内の見出し。高さは SCR-00 のヘッダに揃える。
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SizedBox(
      height: Dimens.headerHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: TextStyle(
              color: t.textColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
