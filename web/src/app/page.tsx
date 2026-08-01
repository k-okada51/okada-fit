'use client';

import { useState, useMemo } from 'react';
import Link from 'next/link';
import { css } from '@/lib/style';

// SCR-00 トップ — Claude Design のモックを忠実に移植（アクセント teal / モバイル430px）
export default function TopPage() {
  const [dark, setDark] = useState(true);

  // --- デモ用の入力値（実装では Supabase から取得） ---
  const weightKg = 60;
  const meals = { breakfast: 22, lunch: 38, dinner: 0, snack: 21 };

  const v = useMemo(() => computeVals(dark, weightKg, meals), [dark]);

  return (
    <div
      style={css(
        `min-height:100vh; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','Hiragino Kaku Gothic ProN','Noto Sans JP',sans-serif; -webkit-font-smoothing:antialiased; letter-spacing:-0.01em; background:${v.pageBg}; color:${v.textColor}`
      )}
    >
      <div
        style={css(
          `max-width:430px; margin:0 auto; min-height:100vh; display:flex; flex-direction:column; border-left:1px solid ${v.hairline}; border-right:1px solid ${v.hairline}`
        )}
      >
        {/* header */}
        <header style={css('display:flex; align-items:center; justify-content:space-between; padding:22px 20px 0')}>
          <div style={css('font-size:13px; font-weight:600; opacity:.6')}>{v.todayLabel}</div>
          <div style={css('display:flex; gap:8px')}>
            <button
              onClick={() => setDark((d) => !d)}
              style={css(
                `width:32px; height:32px; border-radius:9px; border:1px solid ${v.hairline}; background:transparent; color:inherit; font-size:12px; cursor:pointer; display:flex; align-items:center; justify-content:center`
              )}
            >
              {v.schemeIcon}
            </button>
            <Link
              href="/settings"
              style={css(
                `width:32px; height:32px; border-radius:9px; border:1px solid ${v.hairline}; color:inherit; font-size:13px; display:flex; align-items:center; justify-content:center`
              )}
            >
              ⚙
            </Link>
          </div>
        </header>

        <main style={css('flex:1; padding:18px 20px 28px; display:flex; flex-direction:column; gap:18px')}>
          {/* タンパク質ゲージ */}
          <section
            style={css(
              `display:flex; align-items:center; gap:20px; padding:20px 18px; border-radius:16px; background:${v.surface}; border:1px solid ${v.hairline}`
            )}
          >
            <div style={css('position:relative; width:104px; height:104px; flex-shrink:0')}>
              <svg width="104" height="104" viewBox="0 0 104 104" style={{ display: 'block' }}>
                <g transform="rotate(-90 52 52)">
                  <circle cx="52" cy="52" r="44" fill="none" stroke={v.ringTrack} strokeWidth="12" />
                  <circle
                    cx="52"
                    cy="52"
                    r="44"
                    fill="none"
                    stroke={v.fill}
                    strokeWidth="12"
                    strokeLinecap="round"
                    strokeDasharray={v.ringDash}
                  />
                </g>
              </svg>
              <div style={css('position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center')}>
                <div style={css('display:flex; align-items:baseline; font-variant-numeric:tabular-nums')}>
                  <span style={css('font-size:26px; font-weight:800; line-height:1; letter-spacing:-0.04em')}>{v.intake}</span>
                  <span style={css('font-size:13px; font-weight:700; opacity:.75')}>g</span>
                </div>
                <div style={css('font-size:12px; font-weight:700; opacity:.72; font-variant-numeric:tabular-nums')}>{v.pctLabel}</div>
              </div>
            </div>

            <div style={css('display:flex; flex-direction:column; gap:7px; flex:1; min-width:0')}>
              <div style={css('font-size:12px; font-weight:600; opacity:.75')}>今日のタンパク質</div>
              <div style={css('display:flex; align-items:baseline; gap:2px; font-variant-numeric:tabular-nums')}>
                <span style={css('font-size:32px; font-weight:800; line-height:1; letter-spacing:-0.04em')}>{v.intake}</span>
                <span style={css('font-size:15px; font-weight:600; opacity:.7')}>/ {v.goal}g</span>
              </div>
              <div style={css(`font-size:14px; font-weight:700; color:${v.accent}; font-variant-numeric:tabular-nums`)}>{v.remainText}</div>
            </div>
          </section>

          {/* 1食ペース */}
          <section
            style={css(
              `display:flex; flex-direction:column; gap:11px; padding:16px 16px 14px; border-radius:16px; background:${v.surface}; border:1px solid ${v.hairline}`
            )}
          >
            <div style={css('display:flex; align-items:baseline; justify-content:space-between')}>
              <div style={css('font-size:11px; font-weight:600; opacity:.72; font-variant-numeric:tabular-nums')}>1食ペース目安（各{v.perMeal}g）</div>
              <div style={css(`font-size:11px; font-weight:700; color:${v.accent}; font-variant-numeric:tabular-nums`)}>{v.paceLabel}</div>
            </div>
            <div style={css('display:grid; grid-template-columns:repeat(4,1fr); gap:8px')}>
              {v.chunks.map((c, i) => (
                <div key={i} style={css(`height:5px; border-radius:999px; background:${v.chunkTrack}; overflow:hidden`)}>
                  <div style={css(`height:100%; border-radius:999px; background:${c.barColor}; width:${c.width}`)} />
                </div>
              ))}
            </div>
            <div style={css('display:grid; grid-template-columns:repeat(4,1fr); gap:8px')}>
              {v.chunks.map((c, i) => (
                <div key={i} style={css('display:flex; flex-direction:column; align-items:center; gap:3px')}>
                  <span style={css(`font-size:11px; font-weight:700; color:${c.slotColor}`)}>{c.slot}</span>
                  <span style={css(`font-size:12px; font-weight:700; color:${c.valueColor}; font-variant-numeric:tabular-nums`)}>{c.value}</span>
                </div>
              ))}
            </div>
          </section>

          {/* 不足分の食材候補 */}
          <section style={css('display:flex; flex-direction:column; gap:10px')}>
            <div style={css('font-size:12px; font-weight:600; opacity:.75; font-variant-numeric:tabular-nums')}>{v.suggestTitle}</div>
            <div style={css('display:flex; flex-direction:column; gap:8px')}>
              {v.suggestions.map((s, i) => (
                <div
                  key={i}
                  style={css(
                    `display:flex; align-items:center; justify-content:space-between; gap:12px; padding:14px 16px; border-radius:14px; background:${v.surface}; border:1px solid ${v.hairline}`
                  )}
                >
                  <div style={css('display:flex; flex-direction:column; gap:3px; min-width:0')}>
                    <div style={css('font-size:14px; font-weight:700')}>{s.name}</div>
                    <div style={css('font-size:11px; opacity:.7')}>{s.amount}</div>
                  </div>
                  <div style={css(`font-size:15px; font-weight:800; color:${v.accent}; font-variant-numeric:tabular-nums; white-space:nowrap`)}>{s.protein}g</div>
                </div>
              ))}
            </div>
          </section>

          {/* 今週のトレーニング */}
          <section
            style={css(
              `display:flex; flex-direction:column; gap:11px; padding:16px; border-radius:16px; background:${v.surface}; border:1px solid ${v.hairline}`
            )}
          >
            <div style={css('display:flex; align-items:center; justify-content:space-between')}>
              <div style={css('font-size:12px; font-weight:600; opacity:.75')}>今週のトレーニング</div>
              <div style={css(`font-size:12px; font-weight:700; color:${v.accent}; font-variant-numeric:tabular-nums`)}>{v.trainDone} / {v.trainGoal} 回</div>
            </div>
            <div style={css('display:grid; grid-template-columns:repeat(7,1fr); gap:6px')}>
              {v.trainWeek.map((d, i) => (
                <div key={i} style={css('display:flex; flex-direction:column; align-items:center; gap:6px')}>
                  <div style={css(`width:100%; height:28px; border-radius:8px; background:${d.bg}; border:1px solid ${d.border}`)} />
                  <span style={css(`font-size:10px; font-weight:600; opacity:${d.opacity}`)}>{d.label}</span>
                </div>
              ))}
            </div>
            <Link
              href="/training"
              style={css(
                `display:flex; align-items:center; justify-content:center; height:44px; border-radius:11px; border:1px solid ${v.trainBorder}; color:${v.accent}; font-size:14px; font-weight:700`
              )}
            >
              トレを記録
            </Link>
          </section>

          {/* ダッシュボードへ */}
          <Link
            href="/dashboard"
            style={css(
              `display:flex; align-items:center; justify-content:space-between; padding:16px 18px; border-radius:14px; background:${v.surface}; border:1px solid ${v.hairline}; color:inherit`
            )}
          >
            <div style={css('display:flex; flex-direction:column; gap:3px')}>
              <span style={css('font-size:14px; font-weight:700')}>記録を振り返る</span>
              <span style={css('font-size:11px; opacity:.72')}>ジムに行った日のカレンダー・集計・履歴</span>
            </div>
            <span style={css('font-size:16px; opacity:.55')}>→</span>
          </Link>
        </main>

        {/* 下部ナビ＋CTA */}
        <div style={css(`position:sticky; bottom:0; display:flex; flex-direction:column; background:${v.navBg}; backdrop-filter:blur(14px); border-top:1px solid ${v.hairline}`)}>
          <div style={css('padding:12px 20px 6px')}>
            <Link
              href="/meals"
              style={css(
                `display:flex; align-items:center; justify-content:center; gap:9px; height:54px; border-radius:14px; background:${v.ctaBg}; color:${v.ctaFg}; font-size:17px; font-weight:800`
              )}
            >
              <span style={css('font-size:19px; line-height:1')}>＋</span>
              <span>タンパク質を記録する</span>
            </Link>
          </div>
          <nav style={css('display:grid; grid-template-columns:repeat(4,1fr)')}>
            <NavItem href="/" label="ホーム" color={v.accent} active icon="home" />
            <NavItem href="/meals" label="P記録" icon="meal" />
            <NavItem href="/training" label="筋トレ" icon="dumbbell" />
            <NavItem href="/dashboard" label="ダッシュボード" icon="chart" />
          </nav>
        </div>
      </div>
    </div>
  );
}

function NavItem({ href, label, color, active, icon }: { href: string; label: string; color?: string; active?: boolean; icon: string }) {
  const paths: Record<string, React.ReactNode> = {
    home: (<><path d="M3.5 10.5 12 3.5l8.5 7" /><path d="M6 9.8V20h12V9.8" /><path d="M10 20v-5.5h4V20" /></>),
    meal: (<><path d="M3.5 8.8h3.2l1.6-2.3h7.4l1.6 2.3h3.2V19.5H3.5z" /><circle cx="12" cy="14" r="3.1" /></>),
    dumbbell: (<><path d="M3 9.5v5" /><path d="M6.2 7v10" /><path d="M17.8 7v10" /><path d="M21 9.5v5" /><path d="M6.2 12h11.6" /></>),
    chart: (<><path d="M4 20V12.5" /><path d="M9.3 20V6.5" /><path d="M14.7 20v-4.5" /><path d="M20 20V9" /></>),
  };
  return (
    <Link
      href={href}
      style={css(
        `display:flex; flex-direction:column; align-items:center; justify-content:center; gap:5px; height:56px; color:${active ? color : 'inherit'}; opacity:${active ? 1 : 0.7}`
      )}
    >
      <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={active ? 2.4 : 1.9} strokeLinecap="round" strokeLinejoin="round">
        {paths[icon]}
      </svg>
      <span style={css('font-size:10px; font-weight:700')}>{label}</span>
    </Link>
  );
}

// Claude Design の renderVals() を移植
function computeVals(dark: boolean, weightKg: number, mealsIn: { breakfast: number; lunch: number; dinner: number; snack: number }) {
  const today = new Date(2026, 6, 31);
  const goal = Math.round(weightKg * 2 * 10) / 10;
  const slots = [
    { slot: '朝', g: mealsIn.breakfast },
    { slot: '昼', g: mealsIn.lunch },
    { slot: '夜', g: mealsIn.dinner },
    { slot: '間食', g: mealsIn.snack },
  ];
  const perMeal = Math.round(goal / slots.length);
  const intake = Math.round(slots.reduce((s, m) => s + m.g, 0) * 10) / 10;
  const remaining = Math.max(0, Math.round((goal - intake) * 10) / 10);
  const pct = Math.min(1, intake / goal);
  const done = remaining === 0;
  const loggedCount = slots.filter((m) => m.g > 0).length;

  const fill = dark ? '#12d9a0' : '#047857';
  const accent = dark ? '#12d9a0' : '#047857';
  const warn = dark ? '#f5a623' : '#b45309';
  const onFill = dark ? '#06231a' : '#ffffff';
  const C = 2 * Math.PI * 44;

  const trainGoal = 3;
  const trainDoneDays = [1, 3];
  const dow = today.getDay();
  const trainWeek = [];
  for (let i = 0; i < 7; i++) {
    const isDone = trainDoneDays.indexOf(i) >= 0;
    const isToday = i === dow;
    trainWeek.push({
      label: '日月火水木金土'[i],
      bg: isDone ? fill : dark ? 'rgba(255,255,255,0.05)' : 'rgba(15,23,42,0.06)',
      border: isToday ? (dark ? 'rgba(18,217,160,0.55)' : 'rgba(4,120,87,0.55)') : dark ? 'rgba(255,255,255,0.08)' : '#e2e8f0',
      opacity: isToday ? 1 : 0.7,
    });
  }

  return {
    pageBg: dark ? '#0d1117' : '#f1f5f9',
    textColor: dark ? '#e9edf0' : '#0f172a',
    surface: dark ? 'rgba(255,255,255,0.045)' : '#ffffff',
    hairline: dark ? 'rgba(255,255,255,0.10)' : '#e2e8f0',
    navBg: dark ? 'rgba(13,17,23,0.94)' : 'rgba(248,250,252,0.95)',
    ringTrack: dark ? 'rgba(255,255,255,0.08)' : 'rgba(15,23,42,0.09)',
    chunkTrack: dark ? 'rgba(255,255,255,0.09)' : 'rgba(15,23,42,0.09)',
    accent,
    fill,
    ctaFg: onFill,
    ringDash: C * pct + ' ' + C,
    ctaBg: dark ? 'linear-gradient(180deg,#1ae8ad,#0fb686)' : '#047857',
    trainBorder: dark ? 'rgba(18,217,160,0.4)' : 'rgba(4,120,87,0.4)',
    schemeIcon: dark ? '☀' : '☾',
    todayLabel: `${today.getMonth() + 1}月${today.getDate()}日（${'日月火水木金土'[today.getDay()]}）`,
    intake,
    goal,
    perMeal,
    pctLabel: Math.round(pct * 100) + '%',
    remainText: done ? '目標達成' : `残り ${remaining}g`,
    paceLabel: `${loggedCount}/${slots.length}食 進行中`,
    suggestTitle: done ? `次の1食の目安 ${perMeal}g を摂るなら` : `残り${remaining}gを摂るのに必要な食材`,
    suggestions: [
      { name: '鶏むね肉（皮なし）', per: 23, unit: '100g' },
      { name: 'ゆで卵', per: 6.5, unit: '1個' },
      { name: 'プロテイン', per: 21, unit: '1杯' },
    ].map((f) => {
      const need = remaining > 0 ? remaining : perMeal;
      const n = Math.max(1, Math.round(need / f.per));
      return { name: f.name, amount: `${f.unit} × ${n}`, protein: Math.round(f.per * n) };
    }),
    chunks: slots.map((m) => {
      const missing = m.g === 0;
      const full = m.g >= perMeal;
      return {
        slot: m.slot,
        width: Math.round(Math.min(1, m.g / perMeal) * 100) + '%',
        barColor: missing ? 'transparent' : fill,
        value: missing ? '未' : m.g + 'g',
        slotColor: missing ? warn : dark ? 'rgba(233,237,240,0.75)' : '#475569',
        valueColor: missing ? warn : full ? accent : dark ? '#e9edf0' : '#151a1e',
      };
    }),
    trainDone: trainDoneDays.length,
    trainGoal,
    trainWeek,
  };
}
