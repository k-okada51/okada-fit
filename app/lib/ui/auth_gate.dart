import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import 'app_shell.dart';
import 'sign_in_page.dart';

/// 認証状態で行き先を振り分ける。
///
/// アプリの入口はここ1箇所。`main.dart` はこのウィジェットを置くだけにする。
/// 判定は `onAuthStateChange` の購読で行い、状態を定期確認しない。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // 状態管理ライブラリは未選定のため（FEAT-06 §7）、ここで1つ持って配る。
  final AuthRepository _authRepository = AuthRepository();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authRepository.authStateChanges,
      builder: (context, snapshot) {
        // 最初のイベントが届く前と、通信断でストリームがエラーになった後は
        // `snapshot` に値が無い。そのときは保持済みのセッションを見る。
        // 起動直後にサインイン画面が一瞬見える現象を避けるため。
        final session = snapshot.hasData
            ? snapshot.data!.session
            : _authRepository.currentSession;

        switch (resolveDestination(session)) {
          case AuthDestination.signIn:
            return SignInPage(authRepository: _authRepository);
          case AuthDestination.home:
            // 下部ナビ付きの共通の枠へ渡す（ADR-0024 §1）。
            return AppShell(authRepository: _authRepository);
        }
      },
    );
  }
}
