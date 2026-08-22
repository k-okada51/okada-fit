import 'package:flutter/material.dart';

import '../data/food_repository.dart';
import '../domain/food.dart';
import 'error_snack_bar.dart';
import 'food_import_page.dart';

/// SCR-05 の食品マスタ一覧（FEAT-10 §7・2026-08-22 確定）。
///
/// **1件ずつ直せるようにするための画面である。** CSV の取込は追加＋重複スキップで、
/// 既存の値を上書きしない（ADR-0007）。だから再取込では誤りを直せない。
///
/// 件数を先頭に出す。取込前に何件スキップされそうかの見当がつく（§10-7）。
class FoodListPage extends StatefulWidget {
  const FoodListPage({super.key, this.repository});

  /// テストから差し替えられるよう開けてある。省略時は共有クライアントを使う。
  final FoodRepository? repository;

  @override
  State<FoodListPage> createState() => _FoodListPageState();
}

class _FoodListPageState extends State<FoodListPage> {
  late final FoodRepository _repository = widget.repository ?? FoodRepository();

  /// 読み込み済みの一覧。`null` の間は読込中か、読込に失敗している。
  List<Food>? _foods;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final foods = await _repository.fetchFoods();
      if (!mounted) return;
      setState(() => _foods = foods);
    } catch (error) {
      if (!mounted) return;
      // 写像は error_mapper（W-05）に任せる。ここで例外を分類しない。
      showError(context, error, onRetry: _load);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 取込画面へ行き、戻ったら一覧を読み直す。件数が変わっているため。
  Future<void> _openImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FoodImportPage()),
    );
    if (!mounted) return;
    await _load();
  }

  /// 行をタップしたときの編集ダイアログ（§7）。
  Future<void> _edit(Food food) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: food.name);
    final proteinController = TextEditingController(
      text: food.proteinAmount.toStringAsFixed(1),
    );

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('食品を直す'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  maxLength: kMaxFoodNameLength,
                  decoration: const InputDecoration(labelText: '食品名'),
                  // **CSV取込と同じ純関数を通す**（§7）。規則を2本に割らない。
                  validator: validateFoodNameInput,
                ),
                TextFormField(
                  controller: proteinController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'タンパク質量',
                    suffixText: 'g/1食分',
                  ),
                  validator: validateProteinAmountInput,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('やめる'),
            ),
            FilledButton(
              onPressed: () {
                // 入力の検証エラーは例外にしない。ここで止めて各欄に出す。
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (saved != true || !mounted) return;

      try {
        await _repository.updateFood(
          food.id,
          name: nameController.text,
          proteinAmount: proteinController.text,
        );
        if (!mounted) return;
        _showMessage('保存しました');
        await _load();
      } catch (error) {
        if (!mounted) return;
        // 改名先が既存と重なると 23505 が上がる（`uq_foods_name`・ERR-FOOD-006）。
        // 文言は error_mapper が持っている。ここで分類しない。
        showError(context, error);
      }
    } finally {
      nameController.dispose();
      proteinController.dispose();
    }
  }

  /// スワイプ削除の確認（§7）。
  Future<bool> _confirmDelete(Food food) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('削除しますか'),
        // **過去の記録は消えない。** `meal_logs` は栄養値を実体で持ち、
        // `foods` を参照しない（ADR-0013）。ここで安心させておく。
        content: Text('「${food.name}」を一覧から消します。\n記録済みの食事はそのまま残ります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    return agreed == true;
  }

  Future<void> _delete(Food food) async {
    try {
      await _repository.deleteFood(food.id);
      if (!mounted) return;
      _showMessage('削除しました');
    } catch (error) {
      if (!mounted) return;
      showError(context, error);
    }
    // 成否にかかわらず読み直す。楽観的に消した行を実際の状態へ戻すため。
    if (mounted) await _load();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final foods = _foods;

    return Scaffold(
      appBar: AppBar(
        title: const Text('食品マスタ'),
        actions: [
          IconButton(
            onPressed: _openImport,
            icon: const Icon(Icons.upload_file),
            tooltip: 'CSVを取り込む',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : foods == null
          ? _buildLoadFailed()
          : _buildList(foods),
    );
  }

  /// 読込に失敗した状態。一覧を出さない（何を消すのか決まらないため）。
  Widget _buildLoadFailed() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('食品マスタを読み込めませんでした。'),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: _load, child: const Text('再試行')),
      ],
    ),
  );

  Widget _buildList(List<Food> foods) {
    if (foods.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('食品がまだありません。'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _openImport,
              child: const Text('CSVを取り込む'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 件数を先頭に出す（§7）。
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${foods.length}件',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: foods.length,
            itemBuilder: (context, index) {
              final food = foods[index];
              return Dismissible(
                // 並び替えても行を取り違えないよう `id` を鍵にする。
                key: ValueKey(food.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete_outline),
                ),
                confirmDismiss: (_) => _confirmDelete(food),
                onDismissed: (_) => _delete(food),
                child: ListTile(
                  title: Text(food.name),
                  // 単位は1食分あたり（ADR-0012）。100gあたりではない。
                  subtitle: Text(
                    '${food.proteinAmount.toStringAsFixed(1)} g/1食分',
                  ),
                  onTap: () => _edit(food),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
