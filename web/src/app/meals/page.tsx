'use client';

import { useState, useEffect, useRef } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { css } from '@/lib/style';

type Stage = 'capture' | 'preview' | 'analyzing' | 'result' | 'error' | 'done';

// SCR-04 食事記録 — Claude Design のモックを忠実に移植（撮影→解析→記録の状態機械）
// ※ 解析は現状モック（2.2s）。実装では POST /api/meals/analyze（AI Gateway）に接続する。
export default function MealsPage() {
  const router = useRouter();
  const [dark, setDark] = useState(true);
  const [stage, setStage] = useState<Stage>('capture');
  const [url, setUrl] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
  const toastTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => {
    return () => {
      if (url) URL.revokeObjectURL(url);
      clearTimeout(timer.current);
      clearTimeout(toastTimer.current);
    };
  }, [url]);

  const showToast = (text: string) => {
    setToast(text);
    clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(null), 3200);
  };

  const v = vals(dark, stage);

  const onPick = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    if (!f) return;
    if (url) URL.revokeObjectURL(url);
    setUrl(URL.createObjectURL(f));
    setStage('preview');
  };
  const analyze = () => {
    setStage('analyzing');
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setStage('result'), 2200); // TODO: /api/meals/analyze
  };
  const retake = () => {
    clearTimeout(timer.current);
    if (url) URL.revokeObjectURL(url);
    setUrl(null);
    setStage('capture');
  };
  const save = () => {
    setStage('done');
    showToast('記録しました'); // TODO: POST /api/meals
  };

  const stepIdx = stage === 'capture' ? 0 : stage === 'preview' || stage === 'analyzing' ? 1 : 2;
  const hasShot = ['preview', 'analyzing', 'result', 'error'].includes(stage);

  return (
    <div style={css(`min-height:100vh; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','Hiragino Kaku Gothic ProN','Noto Sans JP',sans-serif; -webkit-font-smoothing:antialiased; letter-spacing:-0.01em; background:${v.pageBg}; color:${v.textColor}`)}>
      <style>{`@keyframes spin{to{transform:rotate(360deg)}}@keyframes toastin{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:translateY(0)}}`}</style>
      <div style={css(`max-width:430px; margin:0 auto; min-height:100vh; display:flex; flex-direction:column; border-left:1px solid ${v.hairline}; border-right:1px solid ${v.hairline}`)}>

        <header style={css(`position:sticky; top:0; z-index:5; display:flex; align-items:center; justify-content:space-between; height:56px; padding:0 20px; backdrop-filter:blur(14px); background:${v.navBg}; border-bottom:1px solid ${v.hairline}`)}>
          <div style={css('display:flex; align-items:center; gap:11px')}>
            <Link href="/" style={css('font-size:16px; opacity:.7; color:inherit')}>←</Link>
            <span style={css('font-size:16px; font-weight:700')}>タンパク質を記録</span>
          </div>
          <button onClick={() => setDark((d) => !d)} style={css(`width:32px; height:32px; border-radius:9px; border:1px solid ${v.hairline}; background:transparent; color:inherit; font-size:12px; cursor:pointer; display:flex; align-items:center; justify-content:center`)}>{v.schemeIcon}</button>
        </header>

        {/* ステップインジケータ */}
        <div style={css(`display:flex; align-items:center; gap:8px; margin:14px 20px 0; padding:11px 14px; border-radius:13px; background:${v.surface}; border:1px solid ${v.hairline}`)}>
          <Step n="1" label="撮影" active dotBg={v.fill} dotFg={v.ctaFg} lbl={v.accent} />
          <div style={css(`flex:1; height:2px; border-radius:2px; background:${stepIdx >= 1 ? v.fill : v.off}`)} />
          <Step n="2" label="AI解析" active={stepIdx >= 1} dotBg={stepIdx >= 1 ? v.fill : v.off} dotFg={stepIdx >= 1 ? v.ctaFg : v.textColor} lbl={stepIdx >= 1 ? v.accent : v.muted} />
          <div style={css(`flex:1; height:2px; border-radius:2px; background:${stepIdx >= 2 ? v.fill : v.off}`)} />
          <Step n="3" label="完了" active={stepIdx >= 2} dotBg={stepIdx >= 2 ? v.fill : v.off} dotFg={stepIdx >= 2 ? v.ctaFg : v.textColor} lbl={stepIdx >= 2 ? v.accent : v.muted} />
        </div>

        <main style={css('flex:1; padding:18px 20px 28px; display:flex; flex-direction:column; gap:18px')}>

          {/* 撮影 */}
          {stage === 'capture' && (
            <div style={css('display:flex; flex-direction:column; gap:16px')}>
              <div style={css(`display:flex; align-items:center; gap:10px; padding:12px 14px; border-radius:12px; background:${v.ctaSoft}; border:1px solid ${v.accentBorder}`)}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={v.accent} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}><path d="M12 3.2 19.5 6v6c0 4.6-3.1 7.7-7.5 8.8C7.6 19.7 4.5 16.6 4.5 12V6z" /></svg>
                <span style={css(`font-size:12px; font-weight:700; line-height:1.6; color:${v.accent}`)}>AIがタンパク質量(P)だけを解析／写真は保存されません</span>
              </div>
              <label style={css(`display:flex; flex-direction:column; align-items:center; justify-content:center; gap:11px; height:216px; border-radius:18px; border:2px dashed ${v.dashBorder}; background:${v.ctaSoft}; cursor:pointer`)}>
                <span style={css(`width:60px; height:60px; border-radius:999px; background:${v.ctaBg}; display:flex; align-items:center; justify-content:center; color:${v.ctaFg}`)}>
                  <svg width="27" height="27" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3.5 8.8h3.2l1.6-2.3h7.4l1.6 2.3h3.2V19.5H3.5z" /><circle cx="12" cy="14" r="3.1" /></svg>
                </span>
                <span style={css('font-size:18px; font-weight:800')}>食事を撮影してタンパク質を計測</span>
                <span style={css('font-size:12px; opacity:.66')}>カメラが起動し自動識別します</span>
                <input type="file" accept="image/*" capture="environment" onChange={onPick} style={{ display: 'none' }} />
              </label>
              <div style={css('display:grid; grid-template-columns:1fr 1fr; gap:10px')}>
                <label style={css(`display:flex; align-items:center; justify-content:center; gap:8px; height:50px; border-radius:13px; border:1px solid ${v.hairline}; background:${v.surface}; font-size:14px; font-weight:700; cursor:pointer`)}>
                  <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="4.5" width="17" height="15" rx="2.5" /><circle cx="8.6" cy="9.6" r="1.5" /><path d="m4.5 17 4.6-4.4 3.4 3 2.8-2.4 4.2 3.8" /></svg>
                  アルバムから
                  <input type="file" accept="image/*" onChange={onPick} style={{ display: 'none' }} />
                </label>
                <button onClick={() => showToast('手入力フォームへ')} style={css(`display:flex; align-items:center; justify-content:center; gap:8px; height:50px; border-radius:13px; border:1px solid ${v.hairline}; background:${v.surface}; color:inherit; font-size:14px; font-weight:700; cursor:pointer`)}>
                  <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="6.5" width="18" height="11" rx="2" /><path d="M7 10v0M11 10v0M15 10v0M8 14h8" /></svg>
                  手入力で記録
                </button>
              </div>
            </div>
          )}

          {/* プレビュー〜結果 */}
          {hasShot && (
            <div style={css('display:flex; flex-direction:column; gap:16px')}>
              <div style={css(`position:relative; border-radius:14px; overflow:hidden; background:${v.track}; aspect-ratio:4/3`)}>
                {url ? (
                  <img src={url} alt="撮影した食事" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
                ) : (
                  <div style={css('position:absolute; inset:0; display:flex; align-items:center; justify-content:center')}>
                    <span style={css('font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:11px; opacity:.7')}>meal photo</span>
                  </div>
                )}
                {stage === 'analyzing' && (
                  <div style={css('position:absolute; inset:0; background:rgba(8,11,15,0.68); backdrop-filter:blur(2px); display:flex; flex-direction:column; align-items:center; justify-content:center; gap:13px; color:#e9edf0')}>
                    <div style={css('width:42px; height:42px; border-radius:999px; border:4px solid rgba(255,255,255,0.2); border-top-color:#12d9a0; animation:spin .8s linear infinite')} />
                    <div style={css('font-size:14px; font-weight:700')}>解析中...</div>
                    <div style={css('font-size:11px; opacity:.7')}>最大20秒ほどかかります</div>
                  </div>
                )}
              </div>

              {stage === 'preview' && (
                <div style={css('display:flex; flex-direction:column; gap:10px')}>
                  <button onClick={analyze} style={css(`height:52px; border-radius:14px; border:none; background:${v.ctaBg}; color:${v.ctaFg}; font-size:17px; font-weight:800; cursor:pointer`)}>解析する</button>
                  <button onClick={retake} style={css(`height:46px; border-radius:12px; border:1px solid ${v.hairline}; background:transparent; color:inherit; font-size:14px; font-weight:700; cursor:pointer`)}>撮り直す</button>
                  <div style={css('font-size:11px; opacity:.7; text-align:center')}>「解析する」を押すまで送信されません</div>
                </div>
              )}

              {stage === 'error' && (
                <div style={css('display:flex; flex-direction:column; gap:14px')}>
                  <div style={css(`display:flex; gap:12px; padding:14px 16px; border-radius:13px; background:${v.warnSoft}; border:1px solid ${v.warnBorder}`)}>
                    <div style={css(`width:19px; height:19px; border-radius:999px; background:${v.warn}; color:#1a1204; font-size:12px; font-weight:800; display:flex; align-items:center; justify-content:center; flex-shrink:0`)}>!</div>
                    <div style={css('display:flex; flex-direction:column; gap:4px')}>
                      <div style={css(`font-size:13px; font-weight:800; color:${v.warn}`)}>解析に失敗しました</div>
                      <div style={css('font-size:12px; line-height:1.7; opacity:.7')}>料理が判別できませんでした。明るい場所で、皿全体が入るように撮り直してください。</div>
                    </div>
                  </div>
                  <button onClick={retake} style={css(`height:52px; border-radius:14px; border:none; background:${v.ctaBg}; color:${v.ctaFg}; font-size:17px; font-weight:800; cursor:pointer`)}>撮り直す</button>
                  <button onClick={() => showToast('手入力フォームへ')} style={css(`height:46px; border-radius:12px; border:1px solid ${v.hairline}; background:transparent; color:inherit; font-size:14px; font-weight:700; cursor:pointer`)}>手入力で記録する</button>
                </div>
              )}

              {stage === 'result' && (
                <div style={css('display:flex; flex-direction:column; gap:15px')}>
                  <div style={css('display:flex; flex-direction:column; gap:5px')}>
                    <div style={css(`font-size:11px; font-weight:700; color:${v.accent}`)}>AIの推定結果</div>
                    <div style={css('display:flex; align-items:baseline; gap:9px; flex-wrap:wrap')}>
                      <div style={css('font-size:21px; font-weight:800; letter-spacing:-0.02em')}>鶏の照り焼き定食</div>
                      <div style={css('font-size:11px; opacity:.7')}>確度 高</div>
                    </div>
                    <div style={css('font-size:12px; opacity:.75')}>ごはん / 鶏の照り焼き / 味噌汁 / ほうれん草のおひたし</div>
                  </div>
                  <div style={css(`display:flex; align-items:center; justify-content:space-between; gap:12px; padding:18px 16px; border-radius:14px; background:${v.ctaSoft}; border:1px solid ${v.accentBorder}`)}>
                    <div style={css(`font-size:12px; font-weight:700; color:${v.accent}`)}>タンパク質</div>
                    <div style={css('display:flex; align-items:baseline; gap:2px; font-variant-numeric:tabular-nums')}>
                      <span style={css(`font-size:34px; font-weight:800; line-height:1; letter-spacing:-0.04em; color:${v.accent}`)}>38.4</span>
                      <span style={css(`font-size:15px; font-weight:700; color:${v.accent}; opacity:.75`)}>g</span>
                    </div>
                  </div>
                  <div style={css(`display:flex; flex-direction:column; border-radius:13px; background:${v.surface}; border:1px solid ${v.hairline}; overflow:hidden`)}>
                    {[{ label: '鶏の照り焼き', p: '29.1 g' }, { label: 'ごはん', p: '3.8 g' }, { label: '味噌汁 / おひたし', p: '5.5 g' }].map((b, i) => (
                      <div key={i} style={css(`display:flex; align-items:center; justify-content:space-between; gap:12px; padding:12px 14px; border-bottom:1px solid ${v.hairline}`)}>
                        <span style={css('font-size:13px')}>{b.label}</span>
                        <span style={css('font-size:13px; font-weight:800; font-variant-numeric:tabular-nums')}>{b.p}</span>
                      </div>
                    ))}
                  </div>
                  <div style={css('font-size:11px; opacity:.7; line-height:1.7')}>数値はタップで修正できます。写真は保存されません。</div>
                  <div style={css('display:flex; flex-direction:column; gap:10px')}>
                    <button onClick={save} style={css(`height:52px; border-radius:14px; border:none; background:${v.ctaBg}; color:${v.ctaFg}; font-size:17px; font-weight:800; cursor:pointer`)}>記録する</button>
                    <button onClick={retake} style={css(`height:46px; border-radius:12px; border:1px solid ${v.hairline}; background:transparent; color:inherit; font-size:14px; font-weight:700; cursor:pointer`)}>撮り直す</button>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* 完了 */}
          {stage === 'done' && (
            <div style={css('margin-top:36px; display:flex; flex-direction:column; align-items:center; gap:14px; text-align:center')}>
              <div style={css(`width:70px; height:70px; border-radius:999px; background:${v.ctaSoft}; border:2px solid ${v.fill}; display:flex; align-items:center; justify-content:center; font-size:30px; color:${v.accent}`)}>✓</div>
              <div style={css('font-size:18px; font-weight:800')}>記録しました</div>
              <div style={css('font-size:13px; opacity:.6; line-height:1.9')}>鶏の照り焼き定食 ・ タンパク質 38.4g<br />今日は <span style={css(`color:${v.accent}; font-weight:800`)}>残り 9.6g</span></div>
              <div style={css('display:flex; flex-direction:column; gap:10px; width:100%; margin-top:6px')}>
                <button onClick={() => router.push('/')} style={css(`height:50px; border-radius:13px; border:none; background:${v.ctaBg}; color:${v.ctaFg}; font-size:16px; font-weight:800; cursor:pointer`)}>ホームに戻る</button>
                <button onClick={retake} style={css(`height:46px; border-radius:12px; border:1px solid ${v.hairline}; background:transparent; color:inherit; font-size:14px; font-weight:700; cursor:pointer`)}>続けて記録する</button>
              </div>
            </div>
          )}
        </main>

        {toast && (
          <div style={css('position:fixed; left:0; right:0; bottom:80px; display:flex; justify-content:center; pointer-events:none; z-index:20')}>
            <div style={css('display:flex; align-items:center; gap:10px; max-width:398px; padding:13px 16px; border-radius:11px; background:#0d1117; color:#e9edf0; border:1px solid rgba(255,255,255,0.14); box-shadow:0 8px 24px rgba(0,0,0,.4); animation:toastin .22s ease-out')}>
              <span style={css(`width:19px; height:19px; border-radius:999px; background:${v.fill}; color:${v.ctaFg}; font-size:11px; font-weight:800; display:flex; align-items:center; justify-content:center`)}>✓</span>
              <span style={css('font-size:13px; font-weight:700')}>{toast}</span>
            </div>
          </div>
        )}

        <BottomNav active="meals" accent={v.accent} navBg={v.navBg} hairline={v.hairline} />
      </div>
    </div>
  );
}

function Step({ n, label, active, dotBg, dotFg, lbl }: { n: string; label: string; active: boolean; dotBg: string; dotFg: string; lbl: string }) {
  return (
    <div style={css('display:flex; align-items:center; gap:7px; flex-shrink:0')}>
      <span style={css(`width:20px; height:20px; border-radius:999px; display:flex; align-items:center; justify-content:center; font-size:11px; font-weight:800; background:${dotBg}; color:${dotFg}`)}>{n}</span>
      <span style={css(`font-size:12px; font-weight:800; color:${lbl}`)}>{label}</span>
    </div>
  );
}

// 4画面共通の下部ナビ
export function BottomNav({ active, accent, navBg, hairline }: { active: string; accent: string; navBg: string; hairline: string }) {
  const items = [
    { key: 'home', href: '/', label: 'ホーム', icon: (<><path d="M3.5 10.5 12 3.5l8.5 7" /><path d="M6 9.8V20h12V9.8" /><path d="M10 20v-5.5h4V20" /></>) },
    { key: 'meals', href: '/meals', label: 'P記録', icon: (<><path d="M3.5 8.8h3.2l1.6-2.3h7.4l1.6 2.3h3.2V19.5H3.5z" /><circle cx="12" cy="14" r="3.1" /></>) },
    { key: 'training', href: '/training', label: '筋トレ', icon: (<><path d="M3 9.5v5" /><path d="M6.2 7v10" /><path d="M17.8 7v10" /><path d="M21 9.5v5" /><path d="M6.2 12h11.6" /></>) },
    { key: 'dashboard', href: '/dashboard', label: 'ダッシュボード', icon: (<><path d="M4 20V12.5" /><path d="M9.3 20V6.5" /><path d="M14.7 20v-4.5" /><path d="M20 20V9" /></>) },
  ];
  return (
    <nav style={css(`position:sticky; bottom:0; display:grid; grid-template-columns:repeat(4,1fr); background:${navBg}; backdrop-filter:blur(14px); border-top:1px solid ${hairline}`)}>
      {items.map((it) => {
        const on = it.key === active;
        return (
          <Link key={it.key} href={it.href} style={css(`display:flex; flex-direction:column; align-items:center; justify-content:center; gap:5px; height:56px; color:${on ? accent : 'inherit'}; opacity:${on ? 1 : 0.7}`)}>
            <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={on ? 2.4 : 1.9} strokeLinecap="round" strokeLinejoin="round">{it.icon}</svg>
            <span style={css('font-size:10px; font-weight:700')}>{it.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}

function vals(dark: boolean, _stage: Stage) {
  const fill = dark ? '#12d9a0' : '#047857';
  const accent = fill;
  const onFill = dark ? '#06231a' : '#ffffff';
  return {
    pageBg: dark ? '#0d1117' : '#f1f5f9',
    textColor: dark ? '#e9edf0' : '#0f172a',
    surface: dark ? 'rgba(255,255,255,0.045)' : '#ffffff',
    hairline: dark ? 'rgba(255,255,255,0.10)' : '#e2e8f0',
    track: dark ? 'rgba(255,255,255,0.09)' : '#e9eef4',
    navBg: dark ? 'rgba(13,17,23,0.94)' : 'rgba(248,250,252,0.95)',
    ctaBg: dark ? 'linear-gradient(180deg,#1ae8ad,#0fb686)' : '#047857',
    ctaFg: onFill,
    ctaSoft: dark ? 'rgba(18,217,160,0.09)' : 'rgba(4,120,87,0.08)',
    accentBorder: dark ? 'rgba(18,217,160,0.4)' : 'rgba(4,120,87,0.4)',
    dashBorder: dark ? 'rgba(18,217,160,0.45)' : 'rgba(4,120,87,0.45)',
    warn: dark ? '#f5a623' : '#b45309',
    warnSoft: dark ? 'rgba(245,166,35,0.10)' : 'rgba(180,83,9,0.10)',
    warnBorder: dark ? 'rgba(245,166,35,0.45)' : 'rgba(180,83,9,0.4)',
    accent,
    fill,
    off: dark ? 'rgba(255,255,255,0.12)' : '#cbd5e1',
    muted: dark ? 'rgba(233,237,240,0.55)' : 'rgba(15,23,42,0.55)',
    schemeIcon: dark ? '☀' : '☾',
  };
}
