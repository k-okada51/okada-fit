import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import 'food_list_page.dart';
import 'machine_list_page.dart';
import 'profile_page.dart';

/// ⚠️ **仮のホーム画面。W-17（FEAT-05 ダッシュボード）で本物に置き換える。**
///
/// ここが持つのは「サインインできたこと」と「各画面への入口」だけ。
/// ダッシュボード（SCR-01・FEAT-05）の中身は一切入れない。
///
/// 入口を1か所にまとめている理由。
/// 実装中は機能ごとに画面が増える。ホームに並べておけば、
/// できた順に実機で触れる。本物のホームができたら全部消える。
class HomePlaceholder extends StatefulWidget {
  const HomePlaceholder({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<HomePlaceholder> createState() => _HomePlaceholderState();
}

class _HomePlaceholderState extends State<HomePlaceholder> {
  /// 二重タップ防止。
  bool _isSigningOut = false;

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);
    try {
      await widget.authRepository.signOut();
      // 画面の切り替えは AuthGate が `onAuthStateChange` を受けて行う。
      // ここで Navigator を触らない。
    } catch (error, stackTrace) {
      // 利用者向け文言への写像は W-05（共通エラー処理）の担当。
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.authRepository.displayName ?? '（表示名なし）';

    return Scaffold(
      appBar: AppBar(title: const Text('Okada Fit')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text('サインイン中: $name'),
            subtitle: const Text('仮のホーム画面（W-17 で置き換わる）'),
          ),
          const Divider(),

          // 使う順に並べる。器具を登録しないとトレーニングを記録できない。
          _SectionLabel('準備'),
          ListTile(
            leading: const Icon(Icons.fitness_center),
            title: const Text('器具・種目の登録'),
            subtitle: const Text('FEAT-01 / SCR-02'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(const MachineListPage()),
          ),
          ListTile(
            leading: const Icon(Icons.restaurant_menu),
            title: const Text('食品マスタ'),
            subtitle: const Text('FEAT-10 / 一覧・編集・CSV取込'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(const FoodListPage()),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('設定・プロフィール'),
            subtitle: const Text('FEAT-06 / SCR-05 / 体重・目標回数'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(const ProfilePage()),
          ),

          const Divider(),
          _SectionLabel('未実装'),
          // 実装が済んだらここから上へ移す。
          const ListTile(
            enabled: false,
            leading: Icon(Icons.filter_alt_outlined),
            title: Text('部位で器具を絞り込む'),
            subtitle: Text('FEAT-02 / W-09'),
          ),
          const ListTile(
            enabled: false,
            leading: Icon(Icons.check_circle_outline),
            title: Text('トレーニングを記録する'),
            subtitle: Text('FEAT-04 / W-16'),
          ),
          const ListTile(
            enabled: false,
            leading: Icon(Icons.photo_camera_outlined),
            title: Text('食事を撮影する'),
            subtitle: Text('FEAT-08 / W-12・AI を使う'),
          ),

          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton(
              onPressed: _isSigningOut ? null : _signOut,
              child: const Text('サインアウト'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一覧の区切り。仮のホームでしか使わない。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: Theme.of(context).hintColor),
      ),
    );
  }
}
