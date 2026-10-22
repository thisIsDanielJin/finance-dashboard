# Finanz Dashboard, Improvements Plan

Status key: [ ] todo, [~] in progress, [x] done, [?] needs your decision

Last updated: 2026-10-22

## Locked decisions
- Item 1: KEEP Reports. Fold Analytics-only visuals into Reports, then remove Analytics.
- Item 2: Sidebar "Categorize" links to the guided flow (`/transactions/categorize`).
- Item 3: Fix via Railway Redis + separate Sidekiq worker service (option A). User to run `railway login`.
- Item 4: Keep single income node, but let the user add their own categories (not limited to existing ones).

---

## Context

- App: Rails 8 personal finance dashboard ("Finanz"), fork of we-promise/sure.
- Deploy: Railway, Docker build from `Dockerfile`, deploys from GitHub `main`.
- Background jobs: Sidekiq (`config.active_job.queue_adapter = :sidekiq` in production), needs Redis + a worker process.

---

## Item 1, Merge Analytics and Reports into one page

Goal: one page instead of two overlapping ones.

### Findings
- `Analytics` (`/analytics`, `AnalyticsController`, ECharts, loaded via CDN) has:
  summary stats (income, expenses, net savings, savings rate), donut "where money goes",
  income vs expenses bar, spending trends by category, net worth line, top merchants list,
  and the "Categorize All" button.
- `Reports` (`/reports`, `ReportsController`) is the MORE mature feature:
  user-reorderable + collapsible sections, summary dashboard, budget performance,
  net worth, transactions breakdown, investment performance, investment flows,
  trends insights, period picker, CSV/Google Sheets export, print view.

### Decision needed [?]
Reports is richer than Analytics, so deleting Reports loses real features
(investment performance, investment flows, export, print, budget performance,
drag-reorder). Pick one:
- (A) Keep Reports as the home for all this, fold the few Analytics-only visuals
  (ECharts donut / trends / top merchants) into Reports as new sections, then
  remove the Analytics tab. Recommended.
- (B) Keep Analytics as the base, port the missing Reports features into it, then
  remove Reports. More work, risks regressions.

### Steps (assuming A)
- [ ] Decide A vs B.
- [ ] Inventory Analytics-only pieces worth keeping (top merchants, ECharts donut/trends).
- [ ] Add them as Reports sections (respect the reorder/collapse section system).
- [ ] Move "Categorize All" out (see Item 2, it belongs in the sidebar).
- [ ] Remove Analytics route, controller, views, JS, nav item.
- [ ] Update nav + any links/breadcrumbs. Keep ECharts dependency only if still used.

---

## Item 2, Add a Categorize action to the sidebar

Goal: always-available way to categorize uncategorized transactions.

### Findings
- Two separate mechanisms exist:
  1. Guided flow: `/transactions/categorize` (`Transactions::CategorizesController`),
     interactive, groups uncategorized transactions, lets you assign + optionally
     create a rule. This works independently of background jobs.
  2. Auto "Categorize All": `POST /analytics/categorize_all`, enqueues
     `AutoCategorizeJob` (Bayes then LLM). Depends on Sidekiq (see Item 3).
- Sidebar nav is defined in `app/views/layouts/application.html.erb`.

### Decision needed [?]
Which should the sidebar entry do?
- (A) Link to the guided `/transactions/categorize` page (reliable, no jobs). Recommended as the primary entry.
- (B) Also surface the one-click auto "Categorize All" (only works once Item 3 is fixed).
- Nice-to-have: show an uncategorized-count badge on the nav item
  (`Current.accessible_entries.uncategorized_transactions.count`).

### Steps
- [x] Add a "Categorize" nav item (icon `tags`) to the sidebar, pointing at the guided flow.
- [x] Add i18n label key (`layout.nav.categorize`, en).
- [ ] Add the same i18n key to the other locales (avoid i18n-tasks CI miss).
- [ ] Optional later: uncategorized-count badge on the nav item.

---

## Item 3, Fix "Categorize All" (should be a flagship feature)

### DIAGNOSIS COMPLETE (verified against the live deployment)
Railway infra is actually fine: Postgres + Redis + a `finance-dashboard` web service + a
`worker service` running `bundle exec sidekiq` all exist, env vars (REDIS_URL, DB,
SECRET_KEY_BASE, OPENAI_*) are set on both, and the worker is alive and processing
jobs. So the earlier "no worker" hypothesis was wrong.

Real root cause, confirmed by SSHing into the live worker and running the categorizer:
- Family "Jin": 1,847 transactions, ALL uncategorized (0 categorized), 18 categories.
- With 0 categorized history, the free/instant Bayes learner has no training data, so
  ALL 1,847 transactions fall through to the LLM.
- The LLM call fails: the free-tier Gemini key returns 429 (quota) / 503 (overloaded).
  A probe of 8 calls to `gemini-3.8-flash` returned 0 successes (mix of 429 + 503).
- `gemini-3.8-flash` is the CORRECT current model (Google deprecated 2.5/2.0/1.5).
- The categorizer sent all 1,847 in ONE call and `raise`d on any failure, so a single
  transient 429/503 aborted the whole run and categorized nothing.
- Also: Railway has NOT auto-deployed since 2026-10-15 (PR #1). PR #2 (logo) is not live.

### Fixes
- [x] Code: `Family#auto_categorize_transactions` now batches the LLM work
  (`LLM_CATEGORIZE_BATCH_SIZE = 25`), tolerates per-batch transient failures, keeps
  partial progress, and only re-raises (for a Sidekiq retry) when every batch failed
  and nothing was applied. Original provider error contract preserved. Syntax-checked.
- [?] LLM provider decision (the real unblock): the free Gemini key is exhausted.
  Options: (a) use a paid / higher-quota Gemini key or another provider, or
  (b) rely on Bayes: categorize ~20-50 transactions manually via the guided flow
  (now in the sidebar), which trains Bayes (local, free, reliable) to handle the rest.
  Recommended: do (b) now to get unblocked, add (a) later for cold-start coverage.
- [ ] Deployment: investigate why Railway stopped auto-deploying after Oct 15 and
  trigger a deploy so these fixes + the logo go live.

---

## Item 4, Finanzfluss-style flow diagram for the Ideal Budget

Goal: a Sankey like finanzfluss Flussdiagramm.

### Reference (from the finanzfluss link you shared)
Left = income SOURCES (multiple), each with value + %:
  e.g. Gehalt 2654, Marco Miete 536, SAP Aktien 683.15.
They flow into a central total, which flows out to spending/saving CATEGORIES,
each with value + %, and each category expands into SUB-POSITIONS:
  e.g. Wohnen (Miete, Internet, Rundfunk), Taeglicher Bedarf (Lebensmittel, Drogerie),
  Wealth (ETF, Longterm Stocks, Liquid Cash, Crypto, Gold/Silber), SAP Aktien, Abos,
  Versicherungen, Freizeit. Nodes show absolute euro and percent of income.

### Findings (current implementation)
- `Budget::IdealSplit#sankey(mode)` already builds a node/link Sankey:
  single "income" node -> center -> top-level categories.
- Rendered by `app/views/budgets/_ideal_split_chart.html.erb` via the shared
  `sankey-chart` Stimulus controller (has zoom-out, so some drill-down exists).

### Gap vs finanzfluss
- Needs MULTIPLE income sources on the left, not one "Income" node.
- Needs category -> SUB-CATEGORY (child categories) flows on the right.
- Needs value + percent labels on every node.
- finanzfluss also shows per-category target hints ("est: 600").

### Decision needed [?]
- Where do multiple "income sources" come from? Options: income-type categories,
  per-account income, or a small user-defined list of income sources. Need your call.
- Keep it read-only (derived from actual data) first, or make it an editable planner
  like finanzfluss (type in sources/targets)?

### Steps
- [ ] Decide income-source model + editable vs derived.
- [ ] Extend `Budget::IdealSplit#sankey` to emit income-source nodes and
      category->subcategory links with value + percent.
- [ ] Update the `sankey-chart` controller/labels to match (euro + %).
- [ ] Verify against your real data.

---

## Suggested order
1. Item 3 diagnosis (infra, unblocks the flagship feature and informs Item 2B).
2. Item 2 (quick win, sidebar categorize entry).
3. Item 1 (merge, medium, needs the A/B decision).
4. Item 4 (biggest feature, needs the data-model decisions).

## Open decisions blocking a clean start
- 1: merge direction A or B (recommend A, keep Reports).
- 2: sidebar links to guided flow, auto action, or both.
- 3: fix via Railway worker+Redis (A) or in-process adapter (B); set LLM key.
- 4: income-source model, and editable vs derived.
