'use client';

import { useState, useRef, useEffect } from 'react';
import Link from 'next/link';
import { css } from '@/lib/style';
import { BottomNav } from '@/app/meals/page';

type Phase = 'idle' | 'generating' | 'plan' | 'failed';
const ORDER = ['胸', '肩', '背中', '脚', '腕'];

// SCR-03 トレーニング — 部位選択→器具→AIメニュー生成→実施チェック
// ※ 生成は現状モック（1.8s）。実装では POST /api/menus/generate（AI Gateway）に接続。
export default function TrainingPage() {
  const [dark, setDark] = useState(true);
  const [picked, setPicked] = useState<string[]>(['胸']);
  const [phase, setPhase] = useState<Phase>('idle');
  const [checked, setChecked] = useState<Record<string, boolean>>({});
  const [toast, setToast] = useState<string | null>(null);
  const [gearOverride, setGearOverride] = useState<boolean | null>(null);
  const t = useRef<ReturnType<typeof setTimeout>>(undefined);
  const tt = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => () => { clearTimeout(t.current); clearTimeout(tt.current); }, []);
  const showToast = (text: string) => { setToast(text); clearTimeout(tt.current); tt.current = setTimeout(() => setToast(null), 3200); };

  const c = colors(dark);
  const pickedOrdered = ORDER.filter((p) => picked.includes(p));
  const partsLabel = pickedOrdered.join('・');

  const gearList: { name: string; note: string; part: string }[] = [];
  const planList: { name: string; sets: string; memo: string; key: string }[] = [];
  pickedOrdered.forEach((p) => {
    DATA[p].gear.forEach((g) => gearList.push({ ...g, part: p }));
    const take = pickedOrdered.length > 2 ? 2 : pickedOrdered.length === 2 ? 3 : 4;
    DATA[p].plan.slice(0, take).forEach((x) => planList.push({ ...x, key: p + x.name }));
  });
  const hasGear = gearOverride ?? true;
  const checkedCount = planList.filter((p) => checked[p.key]).length;

  const togglePart = (p: string) => {
    setPicked((cur) => {
      const has = cur.includes(p);
      const next = has ? cur.filter((x) => x !== p) : cur.concat([p]);
      return next.length ? next : cur;
    });
    setPhase('idle');
  };
  const generate = () => {
    setPhase('generating');
    clearTimeout(t.current);
    t.current = setTimeout(() => setPhase('plan'), 1800); // TODO: /api/menus/generate
  };
  const save = () => showToast(checkedCount > 0 ? `${partsLabel}のトレーニングを記録しました` : '実行した種目にチェックしてください');

  return (
    <div style={css(`min-height:100vh; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','Hiragino Kaku Gothic ProN','Noto Sans JP',sans-serif; -webkit-font-smoothing:antialiased; letter-spacing:-0.01em; background:${c.pageBg}; color:${c.textColor}`)}>
      <style>{`@keyframes spin{to{transform:rotate(360deg)}}@keyframes toastin{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:translateY(0)}}`}</style>
      <div style={css(`max-width:430px; margin:0 auto; min-height:100vh; display:flex; flex-direction:column; border-left:1px solid ${c.hairline}; border-right:1px solid ${c.hairline}`)}>
        <header style={css(`position:sticky; top:0; z-index:5; display:flex; align-items:center; justify-content:space-between; height:56px; padding:0 20px; backdrop-filter:blur(14px); background:${c.navBg}; border-bottom:1px solid ${c.hairline}`)}>
          <div style={css('display:flex; align-items:center; gap:11px')}>
            <Link href="/" style={css('font-size:16px; opacity:.7; color:inherit')}>←</Link>
            <span style={css('font-size:16px; font-weight:700')}>筋トレ</span>
          </div>
          <button onClick={() => setDark((d) => !d)} style={css(`width:32px; height:32px; border-radius:9px; border:1px solid ${c.hairline}; background:transparent; color:inherit; font-size:12px; cursor:pointer; display:flex; align-items:center; justify-content:center`)}>{c.schemeIcon}</button>
        </header>

        <main style={css('flex:1; padding:18px 20px 28px; display:flex; flex-direction:column; gap:20px')}>
          {!hasGear ? (
            <div style={css('margin-top:36px; display:flex; flex-direction:column; align-items:center; gap:14px; text-align:center')}>
              <div style={css(`width:64px; height:64px; border-radius:16px; border:1px dashed ${c.hairline}`)} />
              <div style={css('font-size:17px; font-weight:800')}>器具が登録されていません</div>
              <div style={css('font-size:12px; opacity:.75; line-height:1.9; max-width:280px')}>通っているジムのマシンを登録すると、<br />使える器具だけでメニューを提案できます。</div>
              <div style={css('display:flex; flex-direction:column; gap:10px; width:100%; margin-top:6px')}>
                <Link href="/equipment" style={css(`display:flex; align-items:center; justify-content:center; height:50px; border-radius:13px; background:${c.trainCta}; color:${c.ctaFg}; font-size:15px; font-weight:800`)}>器具を登録する</Link>
                <button onClick={() => { setGearOverride(true); showToast('自重メニューで進めます'); }} style={css(`height:46px; border-radius:12px; border:1px solid ${c.hairline}; background:transparent; color:inherit; font-size:14px; font-weight:700; cursor:pointer`)}>自重メニューだけで進める</button>
              </div>
            </div>
          ) : (
            <div style={css('display:flex; flex-direction:column; gap:20px')}>
              {/* 部位選択 */}
              <section style={css('display:flex; flex-direction:column; gap:10px')}>
                <div style={css('display:flex; align-items:center; justify-content:space-between; gap:10px')}>
                  <div style={css('font-size:12px; font-weight:600; opacity:.75')}>鍛えたい部位（複数選択可）</div>
                  <div style={css(`font-size:11px; font-weight:700; color:${c.trainAccent}`)}>{pickedOrdered.length}部位を選択中</div>
                </div>
                <div style={css('display:flex; flex-wrap:wrap; gap:8px')}>
                  {ORDER.map((p) => {
                    const on = picked.includes(p);
                    return (
                      <button key={p} onClick={() => togglePart(p)} style={css(`display:flex; align-items:center; gap:6px; height:38px; padding:0 16px; border-radius:999px; font-size:14px; font-weight:700; cursor:pointer; background:${on ? c.trainFill : 'transparent'}; color:${on ? c.ctaFg : c.textColor}; border:1px solid ${on ? c.trainFill : c.line}`)}>
                        <span style={css(`font-size:12px; font-weight:800; opacity:${on ? 1 : 0}`)}>✓</span>
                        {p}
                      </button>
                    );
                  })}
                </div>
              </section>

              {/* 使える器具 */}
              <section style={css('display:flex; flex-direction:column; gap:9px')}>
                <div style={css('display:flex; align-items:baseline; justify-content:space-between')}>
                  <div style={css('font-size:12px; font-weight:600; opacity:.75')}>使える器具</div>
                  <div style={css('font-size:11px; opacity:.68')}>{partsLabel}に対応 {gearList.length}台</div>
                </div>
                {gearList.map((g, i) => (
                  <div key={i} style={css(`display:flex; align-items:center; gap:12px; padding:13px 14px; border-radius:13px; background:${c.surface}; border:1px solid ${c.hairline}`)}>
                    <div style={css(`width:36px; height:36px; border-radius:10px; background:${c.trainSoft}; color:${c.trainAccent}; flex-shrink:0; display:flex; align-items:center; justify-content:center`)}>
                      <GearIcon name={g.name} />
                    </div>
                    <div style={css('display:flex; flex-direction:column; gap:3px; flex:1; min-width:0')}>
                      <div style={css('font-size:14px; font-weight:700')}>{g.name}</div>
                      <div style={css('font-size:11px; opacity:.72')}>{g.note}</div>
                    </div>
                    <span style={css(`font-size:10px; font-weight:700; padding:3px 8px; border-radius:999px; background:${c.trainSoft}; color:${c.trainAccent}`)}>{g.part}</span>
                  </div>
                ))}
              </section>

              {/* 生成〜プラン */}
              <section style={css('display:flex; flex-direction:column; gap:13px')}>
                {phase === 'idle' && (
                  <button onClick={generate} style={css(`height:52px; border-radius:14px; border:none; background:${c.trainCta}; color:${c.ctaFg}; font-size:16px; font-weight:800; cursor:pointer`)}>メニューを生成</button>
                )}
                {phase === 'generating' && (
                  <div style={css(`display:flex; flex-direction:column; align-items:center; justify-content:center; gap:12px; height:190px; border-radius:16px; background:${c.surface}; border:1px solid ${c.hairline}`)}>
                    <div style={css(`width:36px; height:36px; border-radius:999px; border:4px solid ${c.track}; border-top-color:${c.trainFill}; animation:spin .8s linear infinite`)} />
                    <div style={css('font-size:14px; font-weight:700')}>メニューを生成中...</div>
                    <div style={css('font-size:11px; opacity:.72')}>{partsLabel} ・ 器具{gearList.length}台から選定</div>
                  </div>
                )}
                {phase === 'plan' && (
                  <div style={css('display:flex; flex-direction:column; gap:11px')}>
                    <div style={css('display:flex; align-items:baseline; justify-content:space-between')}>
                      <div style={css('font-size:12px; font-weight:600; opacity:.75')}>{partsLabel}のメニュー</div>
                      <div style={css(`font-size:11px; font-weight:700; color:${c.trainAccent}; font-variant-numeric:tabular-nums`)}>{checkedCount} / {planList.length} 実行済</div>
                    </div>
                    {planList.map((p) => {
                      const on = !!checked[p.key];
                      return (
                        <div key={p.key} onClick={() => setChecked((s) => ({ ...s, [p.key]: !s[p.key] }))} style={css(`display:flex; gap:12px; padding:14px; border-radius:13px; cursor:pointer; background:${on ? (dark ? 'rgba(18,217,160,0.10)' : 'rgba(4,120,87,0.08)') : c.surface}; border:1px solid ${on ? c.trainBorder : c.hairline}`)}>
                          <div style={css(`width:21px; height:21px; border-radius:6px; flex-shrink:0; display:flex; align-items:center; justify-content:center; font-size:12px; font-weight:800; color:${c.ctaFg}; background:${on ? c.trainFill : 'transparent'}; border:2px solid ${on ? c.trainFill : c.line}`)}>{on ? '✓' : ''}</div>
                          <div style={css('display:flex; flex-direction:column; gap:5px; flex:1; min-width:0')}>
                            <div style={css('display:flex; align-items:baseline; justify-content:space-between; gap:8px')}>
                              <div style={css('font-size:14px; font-weight:700')}>{p.name}</div>
                              <div style={css('font-size:12px; font-weight:600; opacity:.6; white-space:nowrap')}>{p.sets}</div>
                            </div>
                            <div style={css('font-size:12px; line-height:1.7; opacity:.75')}>{p.memo}</div>
                          </div>
                        </div>
                      );
                    })}
                    <button onClick={generate} style={css(`height:38px; border-radius:10px; border:none; background:transparent; color:${c.trainAccent}; font-size:13px; font-weight:700; cursor:pointer`)}>別のメニューを生成</button>
                    <button onClick={save} style={css(`height:52px; border-radius:14px; border:none; font-size:16px; font-weight:800; cursor:pointer; color:${checkedCount > 0 ? c.ctaFg : c.muted}; background:${checkedCount > 0 ? c.trainCta : (dark ? 'rgba(255,255,255,0.10)' : '#e2e8f0')}`)}>記録する</button>
                  </div>
                )}
              </section>
            </div>
          )}
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

function GearIcon({ name }: { name: string }) {
  const k = /ダンベル/.test(name) ? 'dumbbell' : /ケーブル/.test(name) ? 'cable' : /バー|懸垂/.test(name) ? 'bar' : 'machine';
  const paths: Record<string, React.ReactNode> = {
    machine: (<><rect x="3.5" y="5" width="8" height="14" rx="1.6" /><path d="M11.5 12h5" /><path d="M16.5 8.5v7" /><path d="M20 10.2v3.6" /></>),
    dumbbell: (<><path d="M3 9.5v5" /><path d="M6.2 7v10" /><path d="M17.8 7v10" /><path d="M21 9.5v5" /><path d="M6.2 12h11.6" /></>),
    cable: (<><path d="M5 4v16" /><path d="M5 5.5h11a3 3 0 0 1 0 6h-4" /><path d="M12 11.5v4" /><rect x="8.5" y="15.5" width="7" height="4" rx="1.2" /></>),
    bar: (<><path d="M3 7h18" /><path d="M7 7v3.5a5 5 0 0 0 10 0V7" /><path d="M12 15.5V20" /></>),
  };
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">{paths[k]}</svg>
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
    track: dark ? 'rgba(255,255,255,0.12)' : '#e9eef4',
    navBg: dark ? 'rgba(13,17,23,0.94)' : 'rgba(248,250,252,0.95)',
    trainFill,
    trainAccent: trainFill,
    ctaFg: onFill,
    trainCta: dark ? 'linear-gradient(180deg,#1ae8ad,#0fb686)' : '#047857',
    trainSoft: dark ? 'rgba(18,217,160,0.12)' : 'rgba(4,120,87,0.10)',
    trainBorder: dark ? 'rgba(18,217,160,0.42)' : 'rgba(4,120,87,0.4)',
    line: dark ? 'rgba(255,255,255,0.12)' : '#cbd5e1',
    muted: dark ? 'rgba(233,237,240,0.45)' : 'rgba(15,23,42,0.45)',
    schemeIcon: dark ? '☀' : '☾',
  };
}

const DATA: Record<string, { gear: { name: string; note: string }[]; plan: { name: string; sets: string; memo: string }[] }> = {
  胸: {
    gear: [
      { name: 'チェストプレスマシン', note: '大胸筋・三角筋前部' },
      { name: 'ペックフライ', note: '大胸筋内側のストレッチ種目' },
      { name: 'インクラインベンチ + ダンベル', note: '上部胸' },
    ],
    plan: [
      { name: 'チェストプレス', sets: '4セット × 8回', memo: '肩を落として胸を張る。肘は45度、下ろす時は3秒かけて。' },
      { name: 'インクラインダンベルプレス', sets: '3セット × 10回', memo: 'ベンチ角度30度。手首を立てて真上に押し切る。' },
      { name: 'ペックフライ', sets: '3セット × 12回', memo: '肘を軽く曲げたまま固定。閉じ切って1秒止める。' },
      { name: 'プッシュアップ（仕上げ）', sets: '2セット × 限界まで', memo: '体幹を一直線に。潰れるまでで終了。' },
    ],
  },
  背中: {
    gear: [
      { name: 'ラットプルダウン', note: '広背筋・大円筋' },
      { name: 'シーテッドロー', note: '僧帽筋中部・広背筋' },
      { name: '懸垂バー', note: '自重で背中全体' },
    ],
    plan: [
      { name: 'ラットプルダウン', sets: '4セット × 10回', memo: '胸を張り、鎖骨に向けて引く。反動は使わない。' },
      { name: 'シーテッドロー', sets: '3セット × 10回', memo: '肩甲骨を寄せてから引く。戻す時に伸ばし切る。' },
      { name: '懸垂（アシストあり）', sets: '3セット × 6回', memo: '限界なら足を台に乗せて補助。降りる動作をゆっくり。' },
    ],
  },
  脚: {
    gear: [
      { name: 'レッグプレス', note: '大腿四頭筋・大臀筋' },
      { name: 'レッグエクステンション', note: '大腿四頭筋の追い込み' },
      { name: 'スミスマシン', note: 'スクワット用' },
    ],
    plan: [
      { name: 'スミスマシンスクワット', sets: '4セット × 8回', memo: '膝がつま先より前に出過ぎない。腿が床と平行まで。' },
      { name: 'レッグプレス', sets: '3セット × 12回', memo: '膝を伸ばし切らずに切り返す。踵で押す意識。' },
      { name: 'レッグエクステンション', sets: '3セット × 15回', memo: '軽い重量で。上で1秒静止して絞る。' },
    ],
  },
  肩: {
    gear: [
      { name: 'ショルダープレスマシン', note: '三角筋前部・中部' },
      { name: 'ダンベル（〜20kg）', note: 'レイズ系' },
    ],
    plan: [
      { name: 'ショルダープレス', sets: '4セット × 10回', memo: '腰を反らさない。頭上で肘を伸ばし切る。' },
      { name: 'サイドレイズ', sets: '3セット × 15回', memo: '軽い重量で肩の高さまで。小指側から上げる。' },
      { name: 'リアレイズ', sets: '3セット × 15回', memo: '前傾姿勢で肩甲骨は寄せない。後部だけで挙げる。' },
    ],
  },
  腕: {
    gear: [
      { name: 'ケーブルマシン', note: 'カール・プレスダウン' },
      { name: 'ダンベル（〜20kg）', note: 'アームカール' },
    ],
    plan: [
      { name: 'ダンベルカール', sets: '3セット × 12回', memo: '肘を体側に固定。降ろす動作を意識してゆっくり。' },
      { name: 'ケーブルプレスダウン', sets: '3セット × 12回', memo: '脇を締めて肘を伸ばし切る。上体は動かさない。' },
      { name: 'ハンマーカール', sets: '2セット × 12回', memo: '縦持ちで前腕も一緒に。仕上げの1種目。' },
    ],
  },
};
