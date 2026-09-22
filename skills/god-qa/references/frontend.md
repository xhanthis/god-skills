# Frontend, accessibility, performance, low network (steps 6–9)

Load only when the diff touches UI. Run the app locally with the repo profile's `dev` command; can't start it → these sections are UNVERIFIED.

## 6. Design at four viewports

Use **gstack browse**: follow the SETUP block in `~/.claude/skills/browse/SKILL.md` to get `$B`. Not installed → frontend, a11y, page-perf and low-network UI sections are UNVERIFIED; say so and name the install. Do **not** use `$B responsive` (its sizes are wrong). Set each viewport explicitly:

| Label | `$B viewport` |
|---|---|
| Mobile | `390x844` |
| Tablet | `820x1180` |
| Laptop 14" | `1512x982` |
| Laptop 15" | `1440x900` |

On every page or state the diff touches (loading, empty, error and modal states included), at each viewport:
1. `$B screenshot`, then **Read the PNG and actually look at it**. An unviewed screenshot is not a test.
2. Horizontal overflow: `$B js "document.documentElement.scrollWidth > window.innerWidth"` must be `false`.
3. Clipped or overlapping text, elements cut off, fixed headers or footers covering content, modals taller than the screen, stretched images.
4. Mobile and tablet: tap targets ≥ 44×44px, nav reachable, inputs not hidden behind the keyboard area, no hover-only actions.
5. `$B console` shows no errors; `$B network` shows no failed requests.
6. Run the primary action end to end at Mobile and at Laptop 14".

## 7. Accessibility (Mobile and Laptop 14")

- Inject axe-core: `$B js` appends a `<script>` from `https://cdn.jsdelivr.net/npm/axe-core/axe.min.js`, then `axe.run()` via `$B eval`. Report `serious` and `critical`.
- CSP blocks it → `$B cdp Accessibility.getFullAXTree`; flag buttons, links or inputs with no accessible name.
- Keyboard: `$B press Tab` through the primary flow — focus visible, sane order, action completable without a mouse.
- Contrast: judge from the screenshots.

## 8. Performance and load smoke

- **Page:** `$B perf` at Mobile and Laptop 14"; flag load or LCP over 3s locally.
- **API:** `curl -w '%{time_total}'` on each touched endpoint; flag p95 over 1s.
- **Burst:** `seq 50 | xargs -P 50 -I{} curl -s -o /dev/null -w '%{http_code} %{time_total}\n' …` on each touched **read** endpoint; report error count and p50/p95.
- **Never** burst production and never burst write endpoints. Local or staging only; prod-only reachable → skip and mark UNVERIFIED.

## 9. Low network

- **UI:** the CDP allowlist blocks real throttling, so simulate in-page with `$B eval`: wrap `window.fetch` and `XMLHttpRequest` (a) with a 3s delay, (b) to reject as offline. Then run the primary action: a loading state shows, submit can't double-fire, a readable error appears, retry works, the screen is never blank or stuck.
- **API:** flag list responses over 500KB; `curl --limit-rate 20k --max-time 10` on heavy endpoints and note which won't finish.
- Real throttling (Chrome DevTools "Slow 4G") is a human step in the manual guide.
