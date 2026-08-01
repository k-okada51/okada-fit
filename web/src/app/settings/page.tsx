'use client';

import { useState, useRef, useEffect } from 'react';
import Link from 'next/link';
import { css } from '@/lib/style';
import { BottomNav } from '@/app/meals/page';

// SCR-05 設定 — 体重・目標のステッパー＋タンパク質目標の自動算出＋ダークモード
export default function SettingsPage() {
  const [dark, setDark] = useState(true);
  const [weight, setWeight] = useState('60');
  const [target, setTarget] = useState('3');
  const [toast, setToast] = useState<string | null>(null);
  const tt = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => () => clearTimeout(tt.current), []);
  const showToast = (t: string) => { setToast(t); clearTimeout(tt.current); tt.current = setTimeout(() => setToast(null), 3000); };

  const c = colors(dark);
  const w = parseFloat(weight);
  const goal = isNaN(w) ? 0 : Math.round(w * 2 * 10) / 10;
  const step = (v: string, d: number) => String(Math.max(0, Math.round(((parseFloat(v) || 0) * 10 + d * 10)) / 10));

  return (
    <div style={css(`min-height:100vh; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','Hiragino Kaku Gothic ProN','Noto Sans JP',sans-serif; -webkit-font-smoothing:antialiased; letter-spacing:-0.01em; background:${c.pageBg}; color:${c.textColor}`)}>
      <style>{`@keyframes toastin{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:translateY(0)}}input:focus{outline:2px solid rgba(18,217,160,0.5)}`}</style>
      <div style={css(`max-width:430px; margin:0 auto; min-height:100vh; display:flex; flex-direction:column; border-left:1px solid ${c.hairline}; border-right:1px solid ${c.hairline}`)}>
        <header style={css(`position:sticky; top:0; z-index:5; display:flex; align-items:center; gap:11px; height:56px; padding:0 20px; backdrop-filter:blur(14px); background:${c.navBg}; border-bottom:1px solid ${c.hairline}`)}>
          <Link href="/" style={css('font-size:16px; opacity:.7; color:inherit')}>←</Link>
          <span style={css('font-size:16px; font-weight:700')}>設定</span>
        </header>

        <main style={css('flex:1; padding:18px 20px 28px; display:flex; flex-direction:column; gap:22px')}>
          {/* プロフィール */}
          <section style={css('display:flex; flex-direction:column; gap:12px')}>
            <div style={css('font-size:12px; font-weight:600; opacity:.72')}>プロフィール</div>
            <div style={css(`display:flex; flex-direction:column; gap:14px; padding:17px 16px; border-radius:16px; background:${c.surface}; border:1px solid ${c.hairline}`)}>
              {/* 体重 */}
              <div style={css('display:flex; flex-direction:column; gap:7px')}>
                <label style={css('font-size:12px; font-weight:700')}>体重</label>
                <div style={css('display:flex; align-items:center; gap:8px')}>
                  <button onClick={() => setWeight((v) => step(v, -0.1))} style={stepBtn(c)}>−</button>
                  <div style={css(`flex:1; display:flex; align-items:center; gap:6px; height:46px; padding:0 13px; border-radius:11px; background:${c.inputBg}; border:1px solid ${c.hairline}`)}>
                    <input value={weight} onChange={(e) => setWeight(e.target.value.replace(/[^0-9.]/g, ''))} inputMode="decimal" style={css('flex:1; min-width:0; border:none; background:transparent; color:inherit; font-size:17px; font-weight:700; padding:0; font-variant-numeric:tabular-nums')} />
                    <span style={css('font-size:13px; opacity:.72')}>kg</span>
                  </div>
                  <button onClick={() => setWeight((v) => step(v, 0.1))} style={stepBtn(c)}>＋</button>
                </div>
                <div style={css('font-size:11px; opacity:.68')}>0.1kg単位で調整できます</div>
              </div>

              {/* 目標回数 */}
              <div style={css('display:flex; flex-direction:column; gap:7px')}>
                <label style={css('font-size:12px; font-weight:700')}>目標トレーニング回数（週）</label>
                <div style={css('display:flex; align-items:center; gap:8px')}>
                  <button onClick={() => setTarget((v) => String(Math.max(0, (parseInt(v, 10) || 0) - 1)))} style={stepBtn(c)}>−</button>
                  <div style={css(`flex:1; display:flex; align-items:center; gap:6px; height:46px; padding:0 13px; border-radius:11px; background:${c.inputBg}; border:1px solid ${c.hairline}`)}>
                    <input value={target} onChange={(e) => setTarget(e.target.value.replace(/[^0-9]/g, ''))} inputMode="numeric" style={css('flex:1; min-width:0; border:none; background:transparent; color:inherit; font-size:17px; font-weight:700; padding:0; font-variant-numeric:tabular-nums')} />
                    <span style={css('font-size:13px; opacity:.72')}>回 / 週</span>
                  </div>
                  <button onClick={() => setTarget((v) => String(Math.min(7, (parseInt(v, 10) || 0) + 1)))} style={stepBtn(c)}>＋</button>
                </div>
              </div>

              {/* 自動算出 */}
              <div style={css(`display:flex; flex-direction:column; gap:12px; padding:16px; border-radius:14px; background:${c.ctaSoft}; border:1px solid ${c.accentBorder}`)}>
                <div style={css('display:flex; align-items:center; justify-content:space-between; gap:12px')}>
                  <div style={css('display:flex; flex-direction:column; gap:3px')}>
                    <div style={css(`font-size:12px; font-weight:800; color:${c.accent}`)}>1日の目標タンパク質</div>
                    <div style={css('font-size:11px; opacity:.72')}>体重 × 2g で自動算出</div>
                  </div>
                  <div style={css('display:flex; align-items:baseline; gap:2px; font-variant-numeric:tabular-nums')}>
                    <span style={css(`font-size:30px; font-weight:800; letter-spacing:-0.03em; color:${c.accent}`)}>{goal || '—'}</span>
                    <span style={css(`font-size:14px; font-weight:700; color:${c.accent}; opacity:.75`)}>g</span>
                  </div>
                </div>
                <div style={css(`height:1px; background:${c.accentBorder}`)} />
                <div style={css('display:flex; align-items:center; justify-content:space-between; font-size:11px')}>
                  <span style={css('opacity:.75')}>1食あたりの目安（4食）</span>
                  <span style={css(`font-weight:800; color:${c.accent}; font-variant-numeric:tabular-nums`)}>{goal ? Math.round(goal / 4) : '—'}g</span>
                </div>
              </div>
            </div>
          </section>

          {/* ジム・器具 */}
          <section style={css('display:flex; flex-direction:column; gap:12px')}>
            <div style={css('font-size:12px; font-weight:600; opacity:.72')}>ジム・器具</div>
            <Link href="/equipment" style={css(`display:flex; align-items:center; justify-content:space-between; gap:12px; padding:16px; border-radius:16px; background:${c.surface}; border:1px solid ${c.hairline}; color:inherit`)}>
              <div style={css('display:flex; flex-direction:column; gap:3px')}>
                <div style={css('font-size:14px; font-weight:700')}>器具の登録・管理</div>
                <div style={css('font-size:11px; opacity:.72')}>ジムのマシンを追加・削除する</div>
              </div>
              <span style={css('font-size:16px; opacity:.58')}>›</span>
            </Link>
          </section>

          {/* 表示設定 */}
          <section style={css('display:flex; flex-direction:column; gap:12px')}>
            <div style={css('font-size:12px; font-weight:600; opacity:.72')}>表示設定</div>
            <div style={css(`display:flex; align-items:center; justify-content:space-between; gap:12px; padding:16px; border-radius:16px; background:${c.surface}; border:1px solid ${c.hairline}`)}>
              <div style={css('display:flex; flex-direction:column; gap:3px')}>
                <div style={css('font-size:14px; font-weight:700')}>ダークモード</div>
                <div style={css('font-size:11px; opacity:.72')}>夜のジムでも見やすい配色</div>
              </div>
              <button onClick={() => setDark((d) => !d)} style={css(`width:52px; height:30px; border-radius:999px; border:none; cursor:pointer; padding:3px; display:flex; justify-content:${dark ? 'flex-end' : 'flex-start'}; background:${dark ? c.fill : 'rgba(15,23,42,0.22)'}`)}>
                <span style={css('width:24px; height:24px; border-radius:999px; background:#fff; box-shadow:0 1px 3px rgba(0,0,0,.3); display:block')} />
              </button>
            </div>
          </section>

          <button onClick={() => showToast(`保存しました（目標 ${goal}g / 週${parseInt(target, 10) || 0}回）`)} style={css(`height:52px; border-radius:14px; border:none; background:${c.ctaBg}; color:${c.ctaFg}; font-size:17px; font-weight:800; cursor:pointer`)}>保存する</button>
        </main>

        {toast && (
          <div style={css('position:fixed; left:0; right:0; bottom:80px; display:flex; justify-content:center; pointer-events:none; z-index:20')}>
            <div style={css('display:flex; align-items:center; gap:10px; max-width:398px; padding:13px 16px; border-radius:11px; background:#0d1117; color:#e9edf0; border:1px solid rgba(255,255,255,0.14); box-shadow:0 8px 24px rgba(0,0,0,.4); animation:toastin .22s ease-out')}>
              <span style={css(`width:19px; height:19px; border-radius:999px; background:${c.fill}; color:${c.ctaFg}; font-size:11px; font-weight:800; display:flex; align-items:center; justify-content:center`)}>✓</span>
              <span style={css('font-size:13px; font-weight:700')}>{toast}</span>
            </div>
          </div>
        )}

        <BottomNav active="none" accent={c.accent} navBg={c.navBg} hairline={c.hairline} />
      </div>
    </div>
  );
}

function stepBtn(c: ReturnType<typeof colors>) {
  return css(`width:46px; height:46px; border-radius:11px; border:1px solid ${c.hairline}; background:transparent; color:inherit; font-size:18px; cursor:pointer; flex-shrink:0`);
}

function colors(dark: boolean) {
  const fill = dark ? '#12d9a0' : '#047857';
  const onFill = dark ? '#06231a' : '#ffffff';
  return {
    pageBg: dark ? '#0d1117' : '#f1f5f9',
    textColor: dark ? '#e9edf0' : '#0f172a',
    surface: dark ? 'rgba(255,255,255,0.045)' : '#ffffff',
    hairline: dark ? 'rgba(255,255,255,0.10)' : '#e2e8f0',
    navBg: dark ? 'rgba(13,17,23,0.94)' : 'rgba(248,250,252,0.95)',
    inputBg: dark ? 'rgba(255,255,255,0.05)' : '#ffffff',
    ctaBg: dark ? 'linear-gradient(180deg,#1ae8ad,#0fb686)' : '#047857',
    ctaFg: onFill,
    ctaSoft: dark ? 'rgba(18,217,160,0.09)' : 'rgba(4,120,87,0.08)',
    accentBorder: dark ? 'rgba(18,217,160,0.35)' : 'rgba(4,120,87,0.35)',
    accent: fill,
    fill,
  };
}
