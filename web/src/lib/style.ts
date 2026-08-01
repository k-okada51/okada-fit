import type { CSSProperties } from 'react';

// Claude Design のインラインCSS文字列を React style オブジェクトに変換するヘルパー。
// デザインを1:1で再現するため、モックのCSS文字列をほぼそのまま利用する。
export function css(str: string): CSSProperties {
  const out: Record<string, string> = {};
  for (const decl of str.split(';')) {
    const idx = decl.indexOf(':');
    if (idx === -1) continue;
    const key = decl.slice(0, idx).trim();
    const val = decl.slice(idx + 1).trim();
    if (!key) continue;
    const camel = key.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    out[camel] = val;
  }
  return out as CSSProperties;
}
