'use client';

import { useState, useRef, useEffect } from 'react';
import Link from 'next/link';
import { css } from '@/lib/style';
import { BottomNav } from '@/app/meals/page';

type Item = { name: string; gym: string; parts: string[]; exercise: string };
const PARTS = ['胸', '背中', '脚', '肩', '腕'];
const DEFAULT_ITEMS: Item[] = [
  { name: 'ラットプルダウン', gym: 'エニタイム 桜木町', parts: ['背中'], exercise: 'ワイドグリップ・プルダウン' },
  { name: 'チェストプレスマシン', gym: 'エニタイム 桜木町', parts: ['胸', '肩'], exercise: '' },
  { name: 'レッグプレス', gym: '市民体育館ジム', parts: ['脚'], exercise: '' },
];

// SCR-02 器具登録 — フォーム＋バリデーション＋一覧
export default function EquipmentPage() {
  const [dark, setDark] = useState(true);
  const [name, setName] = useState('');
  const [gym, setGym] = useState('');
  const [parts, setParts] = useState<string[]>([]);
  const [exercise, setExercise] = useState('');
  const [addingGym, setAddingGym] = useState(false);
  const [newGym, setNewGym] = useState('');
  const [errors, setErrors] = useState<{ name?: boolean; gym?: boolean; parts?: boolean }>({});
  const [gyms, setGyms] = useState(['エニタイム 桜木町', '市民体育館ジム']);
  const [items, setItems] = useState<Item[]>(DEFAULT_ITEMS);
  const [toast, setToast] = useState<string | null>(null);
  const tt = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => () => clearTimeout(tt.current), []);
  const showToast = (text: string) => { setToast(text); clearTimeout(tt.current); tt.current = setTimeout(() => setToast(null), 3000); };

  const c = colors(dark);

  const submit = () => {
    const e2 = { name: !name.trim(), gym: !gym, parts: parts.length === 0 };
    if (e2.name || e2.gym || e2.parts) { setErrors(e2); return; }
    setItems((cur) => [{ name: name.trim(), gym, parts: [...parts], exercise: exercise.trim() }, ...cur]);
    setName(''); setParts([]); setExercise(''); setErrors({});
    showToast(`「${name.trim()}」を登録しました`); // TODO: POST /api/machines
  };

  return (
    <div style={css(`min-height:100vh; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','Hiragino Kaku Gothic ProN','Noto Sans JP',sans-serif; -webkit-font-smoothing:antialiased; letter-spacing:-0.01em; background:${c.pageBg}; color:${c.textColor}`)}>
      <style>{`@keyframes toastin{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:translateY(0)}}input:focus,select:focus{outline:2px solid rgba(18,217,160,0.5)}`}</style>
      <div style={css(`max-width:430px; margin:0 auto; min-height:100vh; display:flex; flex-direction:column; border-left:1px solid ${c.hairline}; border-right:1px solid ${c.hairline}`)}>
        <header style={css(`position:sticky; top:0; z-index:5; display:flex; align-items:center; justify-content:space-between; height:56px; padding:0 20px; backdrop-filter:blur(14px); background:${c.navBg}; border-bottom:1px solid ${c.hairline}`)}>
          <div style={css('display:flex; align-items:center; gap:11px')}>
            <Link href="/settings" style={css('font-size:16px; opacity:.7; color:inherit')}>←</Link>
            <span style={css('font-size:16px; font-weight:700')}>器具登録</span>
          </div>
          <button onClick={() => setDark((d) => !d)} style={css(`width:32px; height:32px; border-radius:9px; border:1px solid ${c.hairline}; background:transparent; color:inherit; font-size:12px; cursor:pointer; display:flex; align-items:center; justify-content:center`)}>{c.schemeIcon}</button>
        </header>

        <main style={css('flex:1; padding:18px 20px 28px; display:flex; flex-direction:column; gap:24px')}>
          {/* フォーム */}
          <section style={css(`display:flex; flex-direction:column; gap:15px; padding:17px 16px; border-radius:16px; background:${c.surface}; border:1px solid ${c.hairline}`)}>
            <div style={css('font-size:13px; font-weight:800')}>器具を追加</div>

            <div style={css('display:flex; flex-direction:column; gap:6px')}>
              <label style={css('font-size:12px; font-weight:700')}>マシン名 <span style={css(`color:${c.warn}`)}>*</span></label>
              <input value={name} onChange={(e) => { setName(e.target.value); setErrors((x) => ({ ...x, name: false })); }} placeholder="例: ラットプルダウン" style={css(`height:46px; padding:0 13px; border-radius:11px; font-size:15px; background:${c.inputBg}; color:inherit; border:1px solid ${errors.name ? c.warn : c.line}`)} />
              {errors.name && <div style={css(`font-size:11px; color:${c.warn}; font-weight:700`)}>マシン名を入力してください</div>}
            </div>

            <div style={css('display:flex; flex-direction:column; gap:6px')}>
              <label style={css('font-size:12px; font-weight:700')}>ジム <span style={css(`color:${c.warn}`)}>*</span></label>
              <select value={gym} onChange={(e) => { const val = e.target.value; if (val === '__new') { setAddingGym(true); setGym(''); } else { setGym(val); setAddingGym(false); setErrors((x) => ({ ...x, gym: false })); } }} style={css(`height:46px; padding:0 11px; border-radius:11px; font-size:15px; background:${c.inputBg}; color:inherit; border:1px solid ${errors.gym ? c.warn : c.line}`)}>
                <option value="">選択してください</option>
                {gyms.map((g) => (<option key={g} value={g}>{g}</option>))}
                <option value="__new">＋ 新しいジムを追加</option>
              </select>
              {errors.gym && <div style={css(`font-size:11px; color:${c.warn}; font-weight:700`)}>ジムを選択してください</div>}
            </div>

            {addingGym && (
              <div style={css('display:flex; gap:8px')}>
                <input value={newGym} onChange={(e) => setNewGym(e.target.value)} placeholder="新しいジム名" style={css(`flex:1; height:46px; padding:0 13px; border-radius:11px; font-size:15px; background:${c.inputBg}; color:inherit; border:1px solid ${c.hairline}`)} />
                <button onClick={() => { const g = newGym.trim(); if (!g) return; setGyms((cur) => [...cur, g]); setGym(g); setNewGym(''); setAddingGym(false); setErrors((x) => ({ ...x, gym: false })); showToast(`ジム「${g}」を追加しました`); }} style={css(`height:46px; padding:0 17px; border-radius:11px; border:none; background:${c.trainCta}; color:${c.ctaFg}; font-size:14px; font-weight:800; cursor:pointer`)}>追加</button>
              </div>
            )}

            <div style={css('display:flex; flex-direction:column; gap:8px')}>
              <label style={css('font-size:12px; font-weight:700')}>対応部位 <span style={css(`color:${c.warn}`)}>*</span><span style={css('opacity:.7; font-weight:500')}>（複数選択可）</span></label>
              <div style={css('display:flex; flex-wrap:wrap; gap:8px')}>
                {PARTS.map((p) => {
                  const on = parts.includes(p);
                  return (
                    <button key={p} onClick={() => { setParts((cur) => (cur.includes(p) ? cur.filter((x) => x !== p) : [...cur, p])); setErrors((x) => ({ ...x, parts: false })); }} style={css(`height:36px; padding:0 16px; border-radius:999px; font-size:13px; font-weight:700; cursor:pointer; background:${on ? c.trainFill : 'transparent'}; color:${on ? c.ctaFg : c.textColor}; border:1px solid ${on ? c.trainFill : c.line}`)}>{p}</button>
                  );
                })}
              </div>
              {errors.parts && <div style={css(`font-size:11px; color:${c.warn}; font-weight:700`)}>部位を1つ以上選択してください</div>}
            </div>

            <div style={css('display:flex; flex-direction:column; gap:6px')}>
              <label style={css('font-size:12px; font-weight:700')}>対応する種目名 <span style={css('opacity:.7; font-weight:500')}>（任意）</span></label>
              <input value={exercise} onChange={(e) => setExercise(e.target.value)} placeholder="例: ワイドグリップ・プルダウン" style={css(`height:46px; padding:0 13px; border-radius:11px; font-size:15px; background:${c.inputBg}; color:inherit; border:1px solid ${c.hairline}`)} />
            </div>

            <button onClick={submit} style={css(`height:52px; border-radius:14px; border:none; background:${c.trainCta}; color:${c.ctaFg}; font-size:16px; font-weight:800; cursor:pointer`)}>登録する</button>
          </section>

          {/* 一覧 */}
          <section style={css('display:flex; flex-direction:column; gap:11px')}>
            <div style={css('display:flex; align-items:baseline; justify-content:space-between')}>
              <div style={css('font-size:12px; font-weight:600; opacity:.75')}>登録済みの器具</div>
              <div style={css('font-size:11px; opacity:.68; font-variant-numeric:tabular-nums')}>{items.length}台</div>
            </div>
            {items.length === 0 ? (
              <div style={css(`display:flex; flex-direction:column; align-items:center; gap:10px; padding:38px 20px; border-radius:16px; border:1px dashed ${c.hairline}; text-align:center`)}>
                <div style={css(`width:42px; height:42px; border-radius:12px; background:${c.track}`)} />
                <div style={css('font-size:14px; font-weight:800')}>まだ器具が登録されていません</div>
                <div style={css('font-size:12px; opacity:.72; line-height:1.8')}>上のフォームから、ジムにあるマシンを<br />1台ずつ登録してください。</div>
              </div>
            ) : (
              items.map((it, i) => (
                <div key={i} style={css(`display:flex; align-items:flex-start; gap:12px; padding:14px; border-radius:14px; background:${c.surface}; border:1px solid ${c.hairline}`)}>
                  <div style={css('display:flex; flex-direction:column; gap:6px; flex:1; min-width:0')}>
                    <div style={css('font-size:14px; font-weight:700')}>{it.name}</div>
                    <div style={css('font-size:11px; opacity:.72')}>{it.gym}{it.exercise ? '　・　' + it.exercise : ''}</div>
                    <div style={css('display:flex; flex-wrap:wrap; gap:6px')}>
                      {it.parts.map((p) => (<span key={p} style={css(`padding:3px 9px; border-radius:999px; font-size:11px; font-weight:700; color:${c.trainAccent}; background:${c.trainSoft}; border:1px solid ${c.trainBorder}`)}>{p}</span>))}
                    </div>
                  </div>
                  <button onClick={() => { setItems((cur) => cur.filter((_, j) => j !== i)); showToast(`「${it.name}」を削除しました`); }} style={css(`width:32px; height:32px; border-radius:9px; border:1px solid ${c.warnBorder}; background:transparent; color:${c.warn}; font-size:13px; line-height:1; cursor:pointer; flex-shrink:0`)}>✕</button>
                </div>
              ))
            )}
          </section>
        </main>

        {toast && (
          <div style={css('position:fixed; left:0; right:0; bottom:80px; display:flex; justify-content:center; pointer-events:none; z-index:20')}>
            <div style={css('display:flex; align-items:center; gap:10px; max-width:398px; padding:13px 16px; border-radius:11px; background:#0d1117; color:#e9edf0; border:1px solid rgba(255,255,255,0.14); box-shadow:0 8px 24px rgba(0,0,0,.4); animation:toastin .22s ease-out')}>
              <span style={css(`width:19px; height:19px; border-radius:999px; background:${c.trainFill}; color:${c.ctaFg}; font-size:11px; font-weight:800; display:flex; align-items:center; justify-content:center`)}>✓</span>
              <span style={css('font-size:13px; font-weight:700')}>{toast}</span>
            </div>
          </div>
        )}

        <BottomNav active="training" accent={c.trainAccent} navBg={c.navBg} hairline={c.hairline} />
      </div>
    </div>
  );
}

function colors(dark: boolean) {
  const trainFill = dark ? '#12d9a0' : '#047857';
  const onFill = dark ? '#06231a' : '#ffffff';
  return {
    pageBg: dark ? '#0d1117' : '#f1f5f9',
    textColor: dark ? '#e9edf0' : '#0f172a',
    surface: dark ? 'rgba(255,255,255,0.045)' : '#ffffff',
    hairline: dark ? 'rgba(255,255,255,0.10)' : '#e2e8f0',
    track: dark ? 'rgba(255,255,255,0.10)' : '#e9eef4',
    navBg: dark ? 'rgba(13,17,23,0.94)' : 'rgba(248,250,252,0.95)',
    inputBg: dark ? 'rgba(255,255,255,0.05)' : '#ffffff',
    trainFill,
    trainAccent: trainFill,
    ctaFg: onFill,
    trainCta: dark ? 'linear-gradient(180deg,#1ae8ad,#0fb686)' : '#047857',
    trainSoft: dark ? 'rgba(18,217,160,0.12)' : 'rgba(4,120,87,0.10)',
    trainBorder: dark ? 'rgba(18,217,160,0.4)' : 'rgba(4,120,87,0.4)',
    warn: dark ? '#f5a623' : '#b45309',
    warnBorder: dark ? 'rgba(245,166,35,0.4)' : 'rgba(180,83,9,0.4)',
    line: dark ? 'rgba(255,255,255,0.12)' : '#cbd5e1',
    schemeIcon: dark ? '☀' : '☾',
  };
}
