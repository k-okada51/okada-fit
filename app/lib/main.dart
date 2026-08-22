import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'data/auth_repository.dart';
import 'ui/auth_gate.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertConfigured();
  Env.assertGoogleConfigured();
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );
  // google_sign_in の初期化は起動時に1回だけ（7.x の決まり）。
  await AuthRepository.initializeGoogleSignIn();

  // 保存済みの表示モードを描く前に読む。読んでから runApp すると、
  // ダークで一瞬描いてライトへ切り替わる「ちらつき」が起きない。
  final themeController = ThemeController();
  await themeController.load();

  runApp(OkadaFitApp(themeController: themeController));
}

class OkadaFitApp extends StatelessWidget {
  const OkadaFitApp({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    // ⚠️ **`ThemeScope` は `MaterialApp` より外に置く。**
    //
    // `home:` の中に置くと、`Navigator.push` で開いた画面から見えない。
    // push された画面は Navigator の直下に生え、`home` の中身より上に来るためで、
    // 設定画面（SCR-05）が `ThemeScope.of` で落ちる。
    // 表示モードを切り替えるのは、まさにその push された画面である。
    return ThemeScope(
      controller: themeController,
      // 表示モードが変わったら MaterialApp から作り直す（ADR-0024 §3）。
      child: ListenableBuilder(
        listenable: themeController,
        builder: (context, _) => MaterialApp(
          title: 'Okada Fit',
          // 配色はデザインの実測値（ADR-0024 §2）。`seedColor` は使わない。
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: themeController.themeMode,
          // 画面の振り分けは AuthGate に任せる。ここでは行き先を決めない。
          home: const AuthGate(),
        ),
      ),
    );
  }
}
