import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase クライアントへの参照。
///
/// `Supabase.instance.client` と書くのはこのファイルだけにする。
/// 参照が散ると、初期化前に触ったときの原因追跡が難しくなるため。
///
/// `main()` の `Supabase.initialize()` より前に読むと例外になる。
/// 呼ぶのは `runApp()` 以降に限る。
SupabaseClient get supabase => Supabase.instance.client;
