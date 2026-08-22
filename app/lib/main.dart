import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'data/auth_repository.dart';
import 'ui/auth_gate.dart';

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
  runApp(const OkadaFitApp());
}

class OkadaFitApp extends StatelessWidget {
  const OkadaFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Okada Fit',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      // 画面の振り分けは AuthGate に任せる。ここでは行き先を決めない。
      home: const AuthGate(),
    );
  }
}
