## Scope check & honesty up front

This request is large: a full **drag/resize/configurable widget dashboard** (KPI / Bar / Pie / Line / Table / Matrix), **global Year/Quarter/Month filters**, **per-user persisted layouts**, **chart responsiveness fixes**, **password show/hide**, **force-password-reset fix**, and a **"stuck at Signing in" auth fix** with cookie/storage cleanup and 5s fallback.

Doing all of this in one pass risks exactly what frustrated you last time: lots of code touched, hard to verify, and easy for one piece to break another. I'm splitting it into **3 small phases**. Each phase is independently testable. You approve phase 1; I do only that; you verify; then we move on. This minimizes wasted credits.

---

### Phase 1 — Auth & UX fixes (smallest, highest value)
File: `public/flowdesk.html` only. No DB changes.

1. **"Stuck at Signing in" fix**
   - Add a 5s watchdog around `signInWithPassword`. If it doesn't resolve, run `clearAuthStorage()`, reset the button, show toast "Sign-in timed out — please retry."
   - On every login attempt, call `clearAuthStorage()` + `sb.auth.signOut({ scope: 'local' })` *before* sign-in to guarantee fresh tokens (no stale-token reuse).
   - On `onAuthStateChange` `SIGNED_OUT` or expired session: wipe storage + cookies (already wired) and force redirect to login.
2. **Show/Hide password** (eye icon) on: login password, force-reset new password, force-reset confirm password, admin Add/Edit User password field. Pure inline SVG, no library.
3. **Force password reset on next login — fix**
   - Verify the modal opens *before* the app shell renders (move `openForcedPasswordReset()` check to run inside `bootstrapAuth` after profile load, blocking nav).
   - On submit, `sb.auth.updateUser({ password })` then `update profiles set force_password_reset=false`. Confirm both succeed before closing modal.
   - Re-test the admin checkbox actually writes `force_password_reset=true` via the `admin-users` edge function (it already does — verifying flow).

### Phase 2 — Dashboard responsiveness fix (no new features yet)
File: `public/flowdesk.html` only.

1. Wrap each `<canvas>` in a fixed-aspect container (`position:relative; aspect-ratio: 16/9; min-height:220px`).
2. Pass `responsive:true, maintainAspectRatio:true` to Chart.js (currently uses defaults — that's why charts grow on zoom-out).
3. Add CSS `min-width`/`min-height` to KPI tiles; switch `.grid-4` to `repeat(auto-fit, minmax(220px, 1fr))`.
4. Responsive breakpoints already exist for sidebar at ≤768px; add `@media(max-width:1024px){ .grid-2 { grid-template-columns: 1fr; } }` and ensure `.main` has correct left margin so sidebar never overlaps tiles.

### Phase 3 — Edit Dashboard mode (the big one)
Only after Phase 1 & 2 are confirmed working. File: `public/flowdesk.html` + 1 migration.

**DB migration (1 new table):**
```
dashboard_layouts (
  user_id uuid PK references auth.users on delete cascade,
  layout  jsonb not null default '[]'::jsonb,
  filters jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now()
)
```
RLS: user can read/write only their own row; admins can read all.

**UI (admin-only):**
- "Edit Dashboard" toggle button in dashboard header (shown only if `currentUser.role==='admin'`).
- When ON: each widget gets a drag handle + resize corner; floating "+ Add Widget" button bottom-right; "Save", "Reset Layout", "Cancel" buttons in header.
- Grid: 12-column CSS grid, each widget stores `{i, x, y, w, h, type, config}`. Use **Gridstack.js** via CDN (lightweight, no build step) — best fit for static HTML.

**Widget types:**
| Type | Config inputs |
|---|---|
| KPI Tile | metric (Count / Sum / Distinct Count) + field (Status, Priority, Assignee, Workstream, Type, Labels) |
| Bar / Pie / Line | X-axis field, Y-axis aggregation (Count / Sum), groupBy (optional) |
| Table | columns (multi-select from issue fields) |
| Matrix (pivot) | row group, column group, value aggregation |

**Global filters (top of dashboard, always visible):**
- Year / Quarter / Month dropdowns derived from `issues.start_date`. Filters apply to every widget render.
- Persisted in `dashboard_layouts.filters` per user.

**Save / Reset:**
- "Save Layout" upserts the row.
- "Reset Layout" deletes the row → falls back to a sensible default layout (the current dashboard).

---

## Technical notes

- All widget queries run client-side over `DB.issues` already in memory — no new edge functions needed.
- Chart.js stays (no new chart lib).
- Gridstack only loaded when admin enters Edit Mode (`<script>` injected on demand) — zero cost for non-admins.
- No changes to `src/integrations/supabase/client.ts` or `types.ts`.

## Verification checklist (you run after each phase)

**Phase 1**
- [ ] Sign in → loads ≤5s, never stuck.
- [ ] Sign out → sign in again with no manual cookie clearing.
- [ ] Eye icon toggles password visibility on all 4 fields.
- [ ] Admin ticks "force reset" on a user → that user's next login shows reset modal *before* dashboard, can't bypass.

**Phase 2**
- [ ] Browser zoom in/out → charts stay inside their cards, never balloon.
- [ ] Resize window 1920 → 1024 → 768 → 414: no overlap, no horizontal scroll, sidebar behaves.

**Phase 3**
- [ ] Admin sees "Edit Dashboard" button; non-admin doesn't.
- [ ] Drag/resize a widget, save, reload → layout persists.
- [ ] Add KPI "Count of Status = Open" → number matches Issues page.
- [ ] Add Bar chart "Issues by Workstream" → matches.
- [ ] Year filter = 2026 → all widgets recompute.
- [ ] Reset Layout → defaults restored.

---

## What I need from you

Reply with one of:
- **"Go phase 1"** — I do only auth + password UX + force-reset fix.
- **"Go phase 1 + 2"** — auth fixes + dashboard responsiveness.
- **"Go all phases"** — full build (more credits, longer to verify).
- Or edits to the plan.

Default recommendation: **do phase 1 first**, since the auth bug is blocking you from even using the app properly. Phase 3 isn't useful if you can't reliably log in.