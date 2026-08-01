import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

// サーバー（Route Handlers / Server Components）から使う Supabase クライアント。
// Cookie 経由で Supabase Auth のセッションを引き継ぐ。
export async function createClient() {
  const cookieStore = await cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // Server Component からの呼び出しでは set 不可（middleware で更新する）
          }
        },
      },
    },
  );
}
