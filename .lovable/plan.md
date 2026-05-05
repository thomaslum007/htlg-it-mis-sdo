# Fix Dashboard Light-Mode Theming + Single-Row Period Filter

All work is in `public/flowdesk.html`. Light-mode already exists (`body.theme-light` overrides CSS variables), but several dashboard rules use **hardcoded dark hex fallbacks** (e.g. `var(--card,#161620)`, `var(--bg2,#1a1a24)`) and Chart.js options use **hardcoded grey/white** colors. Because the variables `--card` and `--bg2` are never defined anywhere, the fallbacks always win — that's why these areas stay dark in light mode.

## Root cause summary

| Element | Current source of dark color |
|---|---|
| Period filter `<select>`s | `.dash-toolbar select` uses `var(--bg2,#1a1a24)` — `--bg2` is undefined → always `#1a1a24` |
| KPI / chart widget tiles | `.gridstack-host .grid-stack-item-content` uses `var(--card,#161620)` — `--card` undefined |
| Add Widget modal card, inputs, label colors, suggest box | Same — `var(--card,#161620)`, `var(--bg2,#1a1a24)` fallbacks |
| Chart legends / ticks / gridlines | Hardcoded `#9090a8` and `rgba(255,255,255,0.05)` in Chart.js options |
| Period filter wrapping to 3 rows | `.dash-toolbar { flex-wrap: wrap }` + selects with no `min-width` cap → at narrow viewports the action buttons push selects to new rows |

## Changes

### 1. CSS: replace hardcoded fallbacks with real theme variables (lines ~131–164)

Swap every `var(--card,#161620)` → `var(--surface)`, `var(--bg2,#1a1a24)` → `var(--surface2)`, `var(--border,#2a2a38)` → `var(--border)`, `var(--text2,#9090a8)` → `var(--text2)`, `var(--text,#e6e6f0)` → `var(--text)`, `var(--surface2,#22222e)` → `var(--surface3)`. Affects:

- `.dash-toolbar select`
- `.gridstack-host .grid-stack-item-content`
- `.widget-title`, `.widget-actions button`, `.widget-kpi .lbl`
- `.widget-table th`, `.widget-table th/td` border
- `.modal-backdrop .modal-card`
- `.modal-card label`, `.modal-card select`, `.modal-card input`
- `.ww-suggest`, `.ww-suggest-item`

Also update the inline `<label style="...color:var(--text2,#9090a8)">Period</label>` on line 556 to drop the hardcoded fallback.

### 2. CSS: single-row Period filter (line 132 + 134)

Change `.dash-toolbar` from `flex-wrap: wrap` to `flex-wrap: nowrap; overflow-x: auto;` so the Period label, three selects, spacer, and edit buttons stay on one row. Give `.dash-toolbar select` a `min-width: 110px` and `flex-shrink: 0` so they don't get squashed but don't expand to full width either.

### 3. Chart.js theme-aware colors (lines ~2124, 2138, 1904–1905)

Add a small helper near the chart code:
```js
function chartTheme() {
  const light = document.body.classList.contains('theme-light');
  return {
    tick:  light ? '#4a4a60' : '#9090a8',
    grid:  light ? 'rgba(0,0,0,0.06)' : 'rgba(255,255,255,0.05)',
    legend:light ? '#1a1a25' : '#e8e8f0',
  };
}
```
Use `chartTheme()` inside `renderStatusChart`, `renderPriorityChart`, and the custom-widget chart block (line 1900) for `legend.labels.color`, `scales.x/y.ticks.color`, and `scales.y.grid.color`.

### 4. Re-render charts on theme toggle

`toggleTheme()` (line ~3235) already has a comment "Re-render charts so legend colors update" but doesn't actually re-render. Add a call to `renderDashboard()` (or `renderStatusChart(); renderPriorityChart();` plus custom widget refresh) when the dashboard page is active, so charts pick up the new theme immediately.

### 5. Audit pass

Search for any remaining `#0f`, `#16`, `#1a`, `#22`, `#2a` literals inside dashboard-related rules and inline styles, replace with the appropriate `var(--surface…/--text…/--border)` token. Verify no other component uses undefined `--card` or `--bg2`.

## Verification (after build)

1. Toggle to light mode on the Dashboard tab — Period selects, KPI tiles, both default charts, and custom widgets all read with light backgrounds and dark text.
2. Click Edit Dashboard → Add Widget — modal, inputs, labels, suggestion chips are all legible in light mode.
3. Period filter (label + 3 selects + edit buttons) sits on one row at the current viewport (798px CSS width).
4. Toggle back to dark mode — everything still looks correct.

No database, auth, or backend changes required.