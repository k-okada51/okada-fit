import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import 'profile_page.dart';

/// ⚠️ **仮のホーム画面。W-06 以降で本物に置き換える。**
///
/// ここが持つのは「サインインできたことの確認」だけ。
/// 表示名を出し、サインアウトできれば役目は終わり。
/// ダッシュボード（SCR-01・FEAT-05）の中身は一切入れない。
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

  @override
  Widget build(BuildContext context) {
    final name = widget.authRepository.displayName ?? '（表示名なし）';

    return Scaffold(
      appBar: AppBar(title: const Text('Okada Fit')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('サインイン中: $name'),
            const SizedBox(height: 24),
            // SCR-05（FEAT-06）への入口。本物のホームができるまでの仮置き。
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
              ),
              child: const Text('設定・プロフィール'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isSigningOut ? null : _signOut,
              child: const Text('サインアウト'),
            ),
          ],
        ),
      ),
    );
  }
}
