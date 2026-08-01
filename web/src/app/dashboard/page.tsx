'use client';

import { useState, useMemo } from 'react';
import Link from 'next/link';
import { css } from '@/lib/style';
import { BottomNav } from '@/app/meals/page';

// SCR-01 ダッシュボード — カレンダーヒートマップ＋統計＋履歴（分析・振り返り）
export default function DashboardPage() {
  const [dark, setDark] = useState(true);
  const [monthOffset, setMonthOffset] = useState(0);
  const [tip, setTip] = useState<string | null>(null);

  const v = useMemo(() => vals(dark, monthOffset, setTip), [dark, monthOffset]);

  return (
    <div style={css(`min-height:100vh; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','Hiragino Kaku Gothic ProN','Noto Sans JP',sans-serif; -webkit-font-smoothing:antialiased; letter-spacing:-0.01em; background:${v.pageBg}; color:${v.textColor}`)}>
      <div style={css(`max-width:430px; margin:0 auto; min-height:100vh; display:flex; flex-direction:column; border-left:1px solid ${v.hairline}; border-right:1px solid ${v.hairline}`)}>
        <header style={css(`position:sticky; top:0; z-index:5; display:flex; align-items:center; justify-content:space-between; height:56px; padding:0 20px; backdrop-filter:blur(14px); background:${v.navBg}; border-bottom:1px solid ${v.hairline}`)}>
          <div style={css('display:flex; align-items:center; gap:11px')}>
            <Link href="/" style={css('font-size:16px; opacity:.7; color:inherit')}>←</Link>
            <span style={css('font-size:16px; font-weight:700')}>ダッシュボード</span>
          </div>
          <button onClick={() => setDark((d) => !d)} style={css(`width:32px; height:32px; border-radius:9px; border:1px solid ${v.hairline}; background:transparent; color:inherit; font-size:12px; cursor:pointer; display:flex; align-items:center; justify-content:center`)}>{v.schemeIcon}</button>
        </header>

        <main style={css('flex:1; padding:18px 20px 28px; display:flex; flex-direction:column; gap:14px')}>
          {/* カレンダー */}
          <section style={css(`display:flex; flex-direction:column; gap:14px; padding:18px 16px; border-radius:16px; background:${v.surface}; border:1px solid ${v.hairline}`)}>
            <div style={css('display:flex; align-items:center; justify-content:space-between; gap:12px')}>
              <div style={css('font-size:15px; font-weight:800')}>{v.monthTitle}のジム記録</div>
              <div style={css('display:flex; align-items:center; gap:6px')}>
                <button onClick={() => { setMonthOffset((o) => o - 1); setTip(null); }} style={css(`width:30px; height:30px; border-radius:8px; border:1px solid ${v.hairline}; background:transparent; color:inherit; font-size:12px; cursor:pointer`)}>←</button>
                <button onClick={() => { setMonthOffset((o) => Math.min(0, o + 1)); setTip(null); }} style={css(`width:30px; height:30px; border-radius:8px; border:1px solid ${v.hairline}; background:transparent; color:inherit; font-size:12px; cursor:pointer; opacity:${v.nextOpacity}`)}>→</button>
              </div>
            </div>
            <div style={css('display:grid; grid-template-columns:repeat(7,1fr); gap:6px')}>
              {['日', '月', '火', '水', '木', '金', '土'].map((w) => (
                <div key={w} style={css('font-size:10px; opacity:.6; text-align:center; font-weight:700')}>{w}</div>
              ))}
            </div>
            <div style={css('position:relative; display:grid; grid-template-columns:repeat(7,1fr); gap:6px')}>
              {v.cells.map((c, i) => (
                <div
                  key={i}
                  onMouseEnter={c.onEnter ?? undefined}
                  onMouseLeave={() => setTip(null)}
                  style={css(`aspect-ratio:1; border-radius:9px; display:flex; align-items:center; justify-content:center; font-size:12px; font-weight:700; font-variant-numeric:tabular-nums; background:${c.bg}; color:${c.fg}; border:1px solid ${c.border}`)}
                >
                  {c.label}
                </div>
              ))}
              {tip && (
                <div style={css('position:absolute; left:0; right:0; bottom:-6px; display:flex; justify-content:center; pointer-events:none')}>
                  <div style={css('padding:7px 11px; border-radius:8px; background:#0d1117; color:#e9edf0; border:1px solid rgba(255,255,255,0.14); font-size:11px; white-space:nowrap; box-shadow:0 6px 18px rgba(0,0,0,.35)')}>{tip}</div>
                </div>
              )}
            </div>
            <div style={css('display:flex; align-items:center; gap:14px; font-size:10px; opacity:.72')}>
              <span style={css('display:flex; align-items:center; gap:6px')}><span style={css(`width:11px; height:11px; border-radius:3px; background:${v.trainFill}; display:inline-block`)} />ジムに行った</span>
              <span style={css('display:flex; align-items:center; gap:6px')}><span style={css(`width:11px; height:11px; border-radius:3px; background:${v.track}; display:inline-block`)} />行っていない</span>
            </div>
          </section>

          {/* 統計 */}
          <section style={css('display:grid; grid-template-columns:1fr 1fr; gap:10px')}>
            {v.stats.map((s, i) => (
              <div key={i} style={css(`display:flex; flex-direction:column; gap:6px; padding:15px; border-radius:14px; background:${v.surface}; border:1px solid ${v.hairline}`)}>
                <div style={css('font-size:11px; opacity:.72')}>{s.label}</div>
                <div style={css('display:flex; align-items:baseline; gap:3px; font-variant-numeric:tabular-nums')}>
                  <span style={css('font-size:23px; font-weight:800; letter-spacing:-0.03em')}>{s.value}</span>
                  <span style={css('font-size:11px; opacity:.7')}>{s.unit}</span>
                </div>
              </div>
            ))}
          </section>

          {/* 履歴 */}
          <section style={css('display:flex; flex-direction:column; gap:8px')}>
            <div style={css('font-size:12px; font-weight:600; opacity:.72; padding:0 2px')}>記録履歴</div>
            {v.history.map((h, i) => (
              <div key={i} style={css(`display:flex; align-items:center; gap:12px; padding:13px 15px; border-radius:13px; background:${v.surface}; border:1px solid ${v.hairline}`)}>
                <div style={css('font-size:11px; font-weight:700; opacity:.68; width:36px; font-variant-numeric:tabular-nums')}>{h.date}</div>
                <div style={css('flex:1; display:flex; flex-direction:column; gap:2px; min-width:0')}>
                  <div style={css('font-size:13px; font-weight:600; white-space:nowrap; overflow:hidden; text-overflow:ellipsis')}>{h.title}</div>
                  <div style={css('font-size:10px; opacity:.7')}>{h.sub}</div>
                </div>
                <div style={css(`font-size:13px; font-weight:800; color:${h.color}; font-variant-numeric:tabular-nums`)}>{h.value}</div>
              </div>
            ))}
          </section>
        </main>

        <BottomNav active="dashboard" accent={v.accent} navBg={v.navBg} hairline={v.hairline} />
      </div>
    </div>
  );
}

function went(d: Date) {
  const seed = (d.getDate() * 7 + d.getMonth() * 13) % 10;
  return seed < 5 && d.getDay() !== 0;
}

const POOL = [['ベンチプレス', 'ラットプルダウン'], ['スクワット', 'レッグプレス'], ['デッドリフト'], ['懸垂', 'アームカール'], ['ショルダープレス', 'サイドレイズ']];

function vals(dark: boolean, monthOffset: number, setTip: (t: string) => void) {
  const fill = dark ? '#12d9a0' : '#047857';
  const accent = fill;
  const trainFill = dark ? '#0e9e76' : '#047857';
  const onFill = dark ? '#06231a' : '#ffffff';
  const goal = Math.round(60 * 2 * 10) / 10;

  const today = new Date(2026, 6, 31);
  const view = new Date(today.getFullYear(), today.getMonth() + monthOffset, 1);
  const daysInMonth = new Date(view.getFullYear(), view.getMonth() + 1, 0).getDate();
  const idle = dark ? 'rgba(255,255,255,0.07)' : '#f1f5f9';
  const cells: { label: string; bg: string; fg: string; border: string; onEnter: (() => void) | null }[] = [];
  for (let i = 0; i < view.getDay(); i++) cells.push({ label: '', bg: 'transparent', fg: 'transparent', border: 'transparent', onEnter: null });
  let wentCount = 0;
  for (let dnum = 1; dnum <= daysInMonth; dnum++) {
    const d = new Date(view.getFullYear(), view.getMonth(), dnum);
    const future = d > today;
    const on = !future && went(d);
    if (on) wentCount++;
    cells.push({
      label: String(dnum),
      bg: on ? trainFill : idle,
      fg: on ? onFill : dark ? `rgba(233,237,240,${future ? '0.28' : '0.55'})` : `rgba(15,23,42,${future ? '0.32' : '0.7'})`,
      border: on ? trainFill : dark ? 'rgba(255,255,255,0.06)' : '#e2e8f0',
      onEnter: () => setTip(`${view.getMonth() + 1}/${dnum}　${future ? '—' : on ? POOL[dnum % POOL.length].join('・') : '行っていない'}`),
    });
  }
  const avg = Math.round(goal * 0.86);

  return {
    pageBg: dark ? '#0d1117' : '#f1f5f9',
    textColor: dark ? '#e9edf0' : '#0f172a',
    surface: dark ? 'rgba(255,255,255,0.045)' : '#ffffff',
    hairline: dark ? 'rgba(255,255,255,0.10)' : '#e2e8f0',
    track: dark ? 'rgba(255,255,255,0.09)' : '#e9eef4',
    navBg: dark ? 'rgba(13,17,23,0.94)' : 'rgba(248,250,252,0.95)',
    accent,
    fill,
    trainFill,
    schemeIcon: dark ? '☀' : '☾',
    monthTitle: view.getMonth() + 1 + '月',
    nextOpacity: monthOffset >= 0 ? 0.35 : 1,
    cells,
    stats: [
      { label: 'ジムに行った日数', value: wentCount, unit: '日' },
      { label: 'P目標を達成した日', value: 18, unit: '日' },
      { label: '平均タンパク質', value: avg, unit: 'g' },
      { label: '週あたりのジム', value: Math.round((wentCount / (daysInMonth / 7)) * 10) / 10, unit: '回' },
    ],
    history: [
      { date: '7/31', title: '鶏の照り焼き定食', sub: '食事 ・ 682kcal', value: '38g', color: accent },
      { date: '7/31', title: 'プロテイン', sub: '食事 ・ 120kcal', value: '21g', color: accent },
      { date: '7/30', title: '胸・肩', sub: '筋トレ', value: '', color: dark ? '#e9edf0' : '#0f172a' },
      { date: '7/30', title: 'サラダチキン', sub: '食事 ・ 114kcal', value: '25g', color: accent },
    ],
  };
}
