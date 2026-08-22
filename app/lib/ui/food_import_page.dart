import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/food_repository.dart';
import '../domain/csv_import.dart';
import 'error_snack_bar.dart';

/// SCR-05 の「食事マスタ取込」（FEAT-10 §7）。
///
/// CSV を選び、端末内で検証してから RPC `import_foods` へ1往復で送る。
/// **検証に1件でも不備があれば通信しない。** DBは何も変わらない（§2）。
class FoodImportPage extends StatefulWidget {
  const FoodImportPage({super.key, this.repository});

  /// テストから差し替えられるよう開けてある。省略時は共有クライアントを使う。
  final FoodRepository? repository;

  @override
  State<FoodImportPage> createState() => _FoodImportPageState();
}

/// 画面が今どの段にいるか（§7 の状態表）。
enum _Phase {
  /// 初期／ファイル選択済み。操作できる。
  idle,

  /// 端末内でデコード・パース・検証している。
  parsing,

  /// RPC へ送っている。
  sending,
}

class _FoodImportPageState extends State<FoodImportPage> {
  late final FoodRepository _repository = widget.repository ?? FoodRepository();

  _Phase _phase = _Phase.idle;

  /// 選んだファイルの名前。`null` なら未選択。
  String? _fileName;

  /// 選んだファイルのバイト列。検証と送信の両方で使う。
  Uint8List? _bytes;

  /// 選んだファイルのサイズ(byte)。表示用。
  int _fileSize = 0;

  /// 直近の検証結果。エラー一覧の出どころ。
  FoodsCsvResult? _validation;

  /// 直近の取込結果。成功サマリの出どころ。
  ImportFoodsResult? _imported;

  /// 選択〜RPC完了の実測(ms)（§3.2 の `duration_ms`）。
  int _durationMs = 0;

  bool get _isBusy => _phase != _Phase.idle;

  /// CSV を選ぶ。**複数選択は受け付けない**（§3.3・ERR-FOOD-001）。
  Future<void> _pickFile() async {
    if (_isBusy) return;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      // 選ばずに閉じた。**中断は失敗ではない。** 何も出さない。
      if (picked == null) return;

      // 拡張子の判定（ERR-FOOD-008）。`allowedExtensions` の保険である。
      if (!isCsvFileName(picked.name)) {
        if (!mounted) return;
        _showMessage('CSVファイル（.csv）を選んでください。');
        return;
      }

      // **サイズはバイト列を読む前に見る**（§3.1 の2段・ERR-FOOD-003）。
      final size = await picked.length();
      final tooLarge = checkCsvSize(size);
      if (tooLarge != null) {
        if (!mounted) return;
        _showMessage(tooLarge.message);
        return;
      }

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _fileName = picked.name;
        _fileSize = size;
        _bytes = bytes;
        // 別のファイルを選び直したら前の結果は消す。取り違えを防ぐ。
        _validation = null;
        _imported = null;
        _durationMs = 0;
      });
    } catch (error) {
      if (!mounted) return;
      showError(context, error);
    }
  }

  /// 取込を実行する。確認ダイアログを挟む（§7）。
  Future<void> _import() async {
    final bytes = _bytes;
    if (_isBusy || bytes == null) return;

    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取り込みますか'),
        // 件数の内訳はここに出さない。何件スキップされるかは
        // 実行しないと分からないため（§7）。
        content: const Text('同じ名前の食品はスキップされます。すでにある食品は書き換わりません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('実行する'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    final startedAt = DateTime.now();

    // 段1: 端末内の検証。ここで落ちれば通信しない。
    setState(() {
      _phase = _Phase.parsing;
      _validation = null;
      _imported = null;
    });
    final result = prepareFoodsCsv(bytes);
    if (!mounted) return;
    setState(() {
      _validation = result;
      _phase = _Phase.idle;
    });

    if (result.fileError != null) {
      _showMessage(result.fileError!.message);
      return;
    }
    if (!result.isReadyToSend) {
      // ERR-FOOD-002。何行目のどの列がなぜ不正かは画面の一覧に出す。
      _showMessage('取り込めない行があります。まだ何も登録されていません。');
      return;
    }

    // 段2: RPC 1往復。失敗しても自動ROLLBACKで1件も入らない（ERR-FOOD-007）。
    setState(() => _phase = _Phase.sending);
    try {
      final imported = await _repository.importFoods(result.rows);
      if (!mounted) return;
      setState(() {
        _imported = imported;
        _durationMs = DateTime.now().difference(startedAt).inMilliseconds;
      });
      _showMessage(
        '取込 ${imported.insertedCount}件・スキップ ${imported.skippedCount}件',
      );
    } catch (error) {
      if (!mounted) return;
      // 写像は error_mapper（W-05）に任せる。ここで例外を分類しない。
      // 「1件も取り込まれていない」ことは下の注記で常に見えるようにしてある。
      showError(context, error, onRetry: _import);
    } finally {
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('食事マスタの取込')),
      // 処理中は画面全体を触れなくする。二重送信を防ぐ（§7）。
      body: AbsorbPointer(
        absorbing: _isBusy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isBusy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                _phase == _Phase.parsing ? 'CSVを読み込み中' : 'サーバへ反映中',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
            _buildNotice(),
            const SizedBox(height: 16),
            _buildDescription(),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('CSVを選ぶ'),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(_fileName!),
                subtitle: Text('${(_fileSize / 1024).toStringAsFixed(1)} KB'),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton(
              // 未選択のうちは押させない（§7 の状態表）。
              onPressed: _bytes == null || _isBusy ? null : _import,
              child: const Text('取り込む'),
            ),
            const SizedBox(height: 24),
            ..._buildResult(),
          ],
        ),
      ),
    );
  }

  /// 「既存は消えない」ことを先に伝えるバナー（§7）。
  Widget _buildNotice() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_outline),
        SizedBox(width: 8),
        Expanded(child: Text('すでに登録した食品は消えません。同じ名前の行はスキップされます。')),
      ],
    ),
  );

  /// CSV の作り方（§7）。正規化と単位はここで必ず伝える。
  Widget _buildDescription() => const Text(
    '1行目に「name,protein_amount」の見出しを入れてください。\n'
    'タンパク質量は1食分あたりのグラム数です。100gあたりではありません。\n'
    '文字コードは UTF-8 か Shift_JIS。$kMaxCsvDataRows行・1MBまで。\n'
    '食品名は前後の空白を消し、全角英数字を半角に、英字を小文字にして保存します。',
  );

  List<Widget> _buildResult() {
    final validation = _validation;
    final imported = _imported;

    // 成功サマリ（§3.2 の表）。
    if (imported != null && validation != null) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '取込 ${imported.insertedCount}件・スキップ ${imported.skippedCount}件',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('空行 ${validation.skippedEmptyCount}件'),
                Text('文字コード ${validation.encoding?.label ?? '-'}'),
                Text('所要 ${_durationMs}ms'),
              ],
            ),
          ),
        ),
        // 数式扱いされうる名前の警告（§4-4）。取込は止めていない。
        if (validation.warningLines.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${validation.warningLines.length}件の食品名が「=」「+」「@」で始まっています。'
                '表計算ソフトで開くと数式として扱われることがあります。\n'
                '該当行: ${validation.warningLines.join(', ')}',
              ),
            ),
          ),
        ],
      ];
    }

    // 検証エラーの一覧（§7）。DBが未変更であることを必ず添える。
    if (validation != null && validation.errors.isNotEmpty) {
      return [
        Text(
          '取り込めない行が${validation.totalErrorCount}件あります。'
          'まだ何も登録されていません。',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        // 一覧そのものが長くなるため、外の ListView の中に高さを固定して置く。
        ...validation.errors.map(
          (error) => ListTile(
            dense: true,
            leading: const Icon(Icons.error_outline),
            title: Text(error.display),
          ),
        ),
        if (validation.errorsTruncated)
          const ListTile(
            dense: true,
            title: Text('ほかにもエラーがあります。'),
          ),
      ];
    }

    return const [];
  }
}
