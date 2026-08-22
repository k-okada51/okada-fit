import 'package:flutter/material.dart';

import '../data/auth_repository.dart';

/// サインイン画面。
///
/// 置くのは Google のボタン1つだけ（ADR-0023）。
/// メール＋パスワードもメールリンクも持たない。
class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  /// 二重タップでブラウザが2回開くのを防ぐ。
  bool _isSigningIn = false;

  Future<void> _signIn() async {
    if (_isSigningIn) return;
    setState(() => _isSigningIn = true);
    try {
      await widget.authRepository.signInWithGoogle();
    } catch (error, stackTrace) {
      // 例外の分類と利用者向け文言は W-05（共通エラー処理）の担当。
      // ここでは握り潰さず開発ログに出し、画面には定型文だけを出す。
      debugPrintStack(label: 'signInWithGoogle: $error', stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('サインインできませんでした。時間をおいて試してください。')),
      );
    } finally {
      // 画面が消えた後の setState は例外になる。
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Okada Fit',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 48),
                FilledButton.icon(
                  onPressed: _isSigningIn ? null : _signIn,
                  icon: _isSigningIn
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text('Google でサインイン'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
