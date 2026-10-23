> **Historical audit.** This review describes the pre-rebuild page, before the static rewrite and the guided TUI. It is kept for reference; the issues below have been addressed in the current site and installer.

# UI Audit — wireguard.sh

**Audited:** static landing page (`index.html` + `index.css` + `index.js` + `wireguard.sh.txt`).
**Method:** source review plus local render at 1440×900 and 375×812, sampled at 3 s, 13 s and 25 s into the animation. Primary CTA ("copy install command") appears at **~10.8 s**; page finishes typing at **~17.7 s**.

The core concept — a terminal that installs itself — is good. Execution currently hides the only conversion action behind an animation, breaks completely on mobile, and gives a first-time visitor no reason to trust a `curl | bash` command.

---

## Critical

### 1. The page is blank when any CDN is blocked, and there is no static content
- **Pass:** Designer / First-time user
- **Where:** `index.html:26-31`, `index.js:13,98-109`, `index.css:5-13`. Verified by blocking `ajax.googleapis.com`: rendered page is 100% black, no text.
- **Problem:** `index.html` ships an empty `<div id="console">`; every word is injected by jQuery from a remote CDN, then a second remote `.txt`. If jQuery fails (corporate proxy, ad blocker, CDN outage, mainland China), `$` is undefined and the visitor sees a pure black page with no fallback. Even when it works, crawlers and no-JS users see no content. This is a total conversion failure, not a degradation.
- **Fix:** Render the full terminal output as real HTML in `index.html` (server-side/static), with the install commands and links present before JS runs. Use the animation only as progressive enhancement: keep a `#console` with the complete content, and have JS hide/reveal lines. Add `<noscript>` with the two commands and the GitHub/docs links. Never let remote jQuery be a hard dependency — if it fails, the page must remain readable and copyable.

### 2. Mobile layout is unusable — command is clipped off-screen
- **Pass:** Designer
- **Where:** `index.html:2-3` (no viewport meta), `index.css:5-13` (`width:750px`, fixed `margin-top:100px`), `wireguard.sh.txt:13,16`. At 375×812 the `wget`/`curl` commands are cut mid-URL and cannot be read or copied.
- **Problem:** Missing `<meta name="viewport">` plus a hard `750px` width. On a 375px screen the terminal overflows horizontally; the one thing the visitor came to do (copy a command) is literally off-screen. Mobile is likely a majority of traffic for a "paste this on your server" tool.
- **Fix:** Add `<meta name="viewport" content="width=device-width, initial-scale=1">`. Replace `width:750px` with `width:min(750px, 100% - 40px)` (or `max-width:750px; width:100%; padding:0 20px; box-sizing:border-box`). Use `font-size:clamp(12px, 2.8vw, 14px)` and `white-space:pre-wrap; overflow-wrap:anywhere` on command lines so URLs wrap rather than clip. Reduce `margin-top` to ~40px on small screens.

### 3. Value and CTA are delayed 11–18 seconds by a non-skippable animation
- **Pass:** First-time user
- **Where:** `index.js:98-109` (`Typer.speed = 3`, `setInterval('t();', 30)`), `wireguard.sh.txt:1-20`. Command appears at char 1080 (~10.8 s); second command at ~13.7 s; `about` finishes at ~17.7 s.
- **Problem:** A visitor lands on a blank-ish black screen, waits 11 seconds to see the install command and must wait again for the curl alternative. There is no skip control, no progress indicator, and no content visible immediately. Most visitors bounce long before the CTA renders.
- **Fix:** Show the complete terminal instantly, then animate optionally: (a) render the final state immediately and replay typing only if the user opts in; or (b) add a visible "Skip animation" / click-anywhere-to-skip control; or (c) cap total typing at ~1.5 s and type the important lines (headline + both commands) first. Also honor `prefers-reduced-motion: reduce` by rendering instantly.

### 4. The first screen impersonates a login prompt and never states the value proposition
- **Pass:** Designer / First-time user
- **Where:** `wireguard.sh.txt:1-4`; rendered at 3 s shows only `login as: wireguard.sh` / `wireguard.sh@127.0.0.1's password:` / a version line / GitHub URL.
- **Problem:** The first thing a new visitor sees is a password prompt for a machine they don't own, followed by a version number. This is confusing at best and looks like a phishing/`ssh` interstitial at worst. There is no headline saying what the page does, who it is for, or what happens after the command runs. The actual value ("installs WireGuard on CentOS/Debian/Fedora/Ubuntu") only appears at ~7 s.
- **Fix:** Put a real above-the-fold value prop in the static HTML: e.g. `h1` "Install WireGuard in one command." plus one line "Automated WireGuard VPN setup for CentOS, Debian, Fedora and Ubuntu." Keep the fake login as a decorative flourish *after* the headline and commands, or drop it. Remove the fake password line entirely — it adds confusion and zero value.

### 5. Copy targets are non-semantic `<div>`s; keyboard and screen-reader users cannot copy or discover them
- **Pass:** Designer / First-time user
- **Where:** `wireguard.sh.txt:13,16` (`<div data-clipboard-copy ...>`), `index.css:45-56` (tooltip shown on `:hover` only), `index.js:111-117`.
- **Problem:** The primary CTA is a `<div>` with no `role="button"`, `tabindex`, or keyboard handler. It is not focusable, not announced as actionable, and its "Click to Copy" affordance only appears on mouse hover. Screen-reader users hear a raw shell command with no indication it can be copied; keyboard users cannot activate it. On mobile there is no hover, so the affordance never appears at all. Clicking gives no reliably perceivable feedback (`showTooltip` only changes a hover-only CSS tooltip).
- **Fix:** Render each command as a real `<button type="button">` (with monospace styling) containing the command plus a visible "Copy" label/icon. Add `aria-live="polite"` status text that changes to "Copied" for 2 s after success. Style `:focus-visible` with a clear outline. Also include a plain selectable `<code>` line so users can manually select/copy if the Clipboard API is unavailable. Replace the CSS-only tooltip with the visible button label + status region.

### 6. No trust layer for a `curl | bash` command that must run as root
- **Pass:** First-time user
- **Where:** `wireguard.sh.txt:4,11-19`, `index.html:9-21`.
- **Problem:** The page asks users to pipe a remote script directly into `bash` as root, but gives no explanation of what the script changes (interfaces, firewall/NAT, IP forwarding, keys), no prerequisites (root, supported versions, open UDP port), no source link that is actually clickable, no license/author signal, no uninstall path, and no client-install step after the server is configured. Security-conscious users — exactly the audience for a VPN — will leave. The GitHub URL on line 4 is plain text; `replaceUrls()` (`index.js:86-96`) never converts it because it only handles `http://…me` URLs.
- **Fix:** Add a static trust block containing: clickable GitHub source link (and note the script is inspectable), supported distros with versions, "requires root / run on a fresh VPS", what the script does in 3 bullets, the UDP port it opens, and a "next step: install the WireGuard client" link to `https://www.wireguard.com/install/`. Add a short `<details>` "Read the script before running it" link. Make the version/commit visible. Do not fabricate testimonials or star counts.

---

## High impact

### 7. Every animation tick rebuilds the entire DOM and hijacks scrolling
- **Pass:** Designer / First-time user
- **Where:** `index.js:56-60` (`$('#console').html(...)` every 33 ms, then `window.scrollBy(0, 50)`), `index.js:45-50,73-82`.
- **Problem:** The whole terminal innerHTML is reparsed ~30×/second, which destroys hover state, text selection, focus and any copy feedback mid-animation. `window.scrollBy(0,50)` runs on every tick, so the page continuously scrolls itself while the user is trying to read or scroll — especially bad on mobile. The `|` cursor is implemented by string surgery on serialized HTML, so it can corrupt markup when the cut lands inside a tag.
- **Fix:** Append nodes incrementally (`textContent`) instead of re-setting `innerHTML`. Track the cursor as its own element, not a character in the text. Remove `window.scrollBy` entirely; if auto-follow is desired, only scroll when the user is already at the bottom and use `scrollIntoView({block:'nearest'})` on the cursor. Never call `.html()` with animated/partial markup.

### 8. Clicking "Copy" during the animation can silently lose the feedback or the target
- **Pass:** First-time user
- **Where:** `index.js:59`, `wireguard.sh.txt:13,16`, `index.js:111-113`.
- **Problem:** A command element may not exist yet (appears at 10.8 s), and if it does, the next 33 ms tick rewrites `#console`, wiping the updated `data-tooltip="Copied!"` attribute and any hover state. The user clicks, sees nothing, and assumes copy failed — then copies nothing and leaves. The `.shake` animation also fires on hover, implying clickability without confirming the action.
- **Fix:** Render commands as persistent elements outside the typed stream (or stop rewriting the DOM once a command is rendered). Show copy feedback in a persistent element (`aria-live` status), not an attribute that the typer overwrites. Remove the hover `shake` or reserve it for the click confirmation.

### 9. Dependencies are outdated, unused, and unaudited
- **Pass:** Designer
- **Where:** `index.html:22,25,26,29`.
- **Problem:** Loads Primer CSS (entire framework), the Font Awesome kit script, jQuery **1.4.2 (released 2010)** and Clipboard.js 2.0.8 — none pinned with SRI. Primer and Font Awesome appear unused in the markup; Font Awesome's kit also phones home. jQuery 1.4.2 predates years of security fixes (including the `htmlPrefilter` XSS class used by `.html()`). Four third-party origins are a large reliability and privacy surface for a one-page site, and any one of them failing degrades or blanks the page (see #1).
- **Fix:** Remove Primer CSS and Font Awesome entirely. Drop jQuery; rewrite the ~60 lines of typer/clipboard logic in vanilla JS (`fetch`, `textContent`, `navigator.clipboard`). If any CDN remains, self-host it, pin an exact version, and add `integrity` + `crossorigin`. Add `defer` to scripts.

### 10. JS-only content and empty social image kill search/social acquisition
- **Pass:** Designer
- **Where:** `index.html:5-7,14,21,26-31`.
- **Problem:** `og:image` and `twitter:image` are empty strings while `twitter:card` is `summary_large_image`, producing a blank/grey card on every share. The meta description describes WireGuard generically rather than this installer, and the `<title>` and brand casing are inconsistent ("Wireguard" vs "WireGuard"). Because no content is in the HTML, search snippets and non-rendering crawlers get nothing.
- **Fix:** Add a real 1200×630 OG image and fill both image tags with absolute URLs. Write a description focused on the action: "Install a WireGuard VPN server on CentOS, Debian, Fedora or Ubuntu with one command." Standardize on "WireGuard". Ensure the headline, commands and about text exist in static HTML (#1) so the page is indexable.

### 11. Auto-scroll, typing and hover shake ignore reduced-motion and user control
- **Pass:** Designer
- **Where:** `index.js:60,102`, `index.css:151-186` (`.shake`, `@keyframes shake`), `index.css:40-44`.
- **Problem:** Continuous typing, forced scrolling and a shake-on-hover all run regardless of `prefers-reduced-motion`. The shake is a hover effect on the primary CTA, adding motion/noise to the one element that should feel stable.
- **Fix:** Wrap the typing, cursor blink and shake in `@media (prefers-reduced-motion: no-preference)`; render the final state under `reduce`. Remove `.shake` from the copy targets; if confirmation motion is wanted, use a brief 120 ms background flash on click only.

### 12. Desktop composition leaves the page feeling unfinished
- **Pass:** Designer
- **Where:** `index.css:5-13`; 1440×900 render.
- **Problem:** A 750px column floats in the top-left quadrant with 100px top margin and no footer, nav, or closing element. At 1440px roughly 45% of the width and 60% of the height is empty black. It reads as an unfinished demo rather than a product page, and there is no secondary CTA or trust content to fill the space.
- **Fix:** Center the terminal vertically within the viewport (`min-height:100svh; display:grid; place-items:center`) or use a two-column layout on desktop: terminal on the left, a compact "What this does / Source / Docs / Client downloads" panel on the right. End the terminal with a real footer line (license, GitHub, docs links) instead of a bare `exit` and a blinking cursor.

### 13. `<html>` is malformed: no doctype, charset, lang, or semantics
- **Pass:** Designer
- **Where:** `index.html:1-3,28-33`; `wireguard.sh.txt` all divs/spans.
- **Problem:** Missing `<!DOCTYPE html>`, `<meta charset="utf-8">` and `lang="en"` puts the browser in quirks mode and leaves encoding to sniffing — risky for the box-drawing banner in the fetched `.txt` and harmful for assistive tech and SEO. The page has no `h1`, `main`, `footer`, or list structure; everything is anonymous `div`/`span`.
- **Fix:** Add doctype, `lang="en"`, `<meta charset="utf-8">`, a single `h1` (visually-hidden if the terminal headline must stay ASCII), wrap content in `<main>`, and use `<ol>`/`<li>` for the two commands and a `<footer>` for source/docs links.

---

## Nice to have

### 14. Copy command targets itself instead of the command text
- **Pass:** Designer
- **Where:** `wireguard.sh.txt:13,16` (`data-clipboard-target="#wget"` on `#wget` itself).
- **Problem:** Works today because the div contains only the command, but any icon, label or whitespace added later (e.g. a "Copy" hint) will be copied into the clipboard and break the command.
- **Fix:** Wrap the command in `<code id="cmd-wget">…</code>` and point `data-clipboard-target` at that element. Trim whitespace before writing to the clipboard.

### 15. Typography relies on `courier`/`Lucida Console` and tight line height
- **Pass:** Designer
- **Where:** `index.css:6`, `wireguard.sh.txt:5`.
- **Problem:** `courier` renders thin and inconsistent across Linux/macOS; the banner explicitly requests `Lucida Console`, which is absent on macOS/Linux, so the ASCII art changes width and can break alignment. `line-height:14px` at `font-size:14px` is cramped for body copy.
- **Fix:** Use a real monospace stack: `ui-monospace, "SF Mono", "Cascadia Mono", "DejaVu Sans Mono", Menlo, Consolas, monospace`. Set body `line-height:1.5`; keep the banner `line-height:1` deliberately and test it on each OS.

### 16. Tooltip UI has dead code and no focus/keyboard support
- **Pass:** Designer
- **Where:** `index.css:45-150`; `index.js:112`.
- **Problem:** ~100 lines of bespoke tooltip CSS, only revealed on `:hover`, duplicating what a visible button label would do. `clearTooltip` hardcodes "Click to Copy" instead of restoring the prior value. `#op`, `#k`, `@keyframes change`, and `replaceUrls()` are unused.
- **Fix:** Delete the tooltip CSS and `replaceUrls`/the Alt/CapsLock easter-egg branches. Use a visible "Copy" button label plus `:focus-visible`; if a tooltip is kept, show it on `:focus-visible` as well as `:hover`.

### 17. Brand/copy inconsistencies and a lingering cursor
- **Pass:** Designer
- **Where:** `wireguard.sh.txt:2,3,12,20`; `index.html:5-20`.
- **Problem:** "Wireguard" vs "WireGuard"; "Centos" should be "CentOS"; `v1.1` is repeated twice; the page ends on `exit` followed by a blinking cursor, which looks like the session is still busy rather than complete.
- **Fix:** Standardize "WireGuard" and "CentOS". Drop the duplicate version line and show version/commit once in the header or footer. After `exit`, stop the cursor blink (or replace it with a final, non-blinking block cursor).

### 18. No favicon/social metadata polish
- **Pass:** Designer
- **Where:** `index.html:14,21,24`.
- **Problem:** Only an `.ico` is supplied; no `apple-touch-icon`, `theme-color`, or `og:image`, and the OG image is empty (also #10). The black page has no browser chrome hint.
- **Fix:** Add `<meta name="theme-color" content="#000000">`, a 180×180 `apple-touch-icon`, and a PNG OG image; point `og:image`/`twitter:image` at it with absolute URLs and include `og:image:width/height`.

---

## Top 5 critical items

1. **Blank page when a CDN fails** — all content and the install command are JS-injected; blocking jQuery yields a 100% black page, and crawlers/no-JS users see nothing (`index.html:26-31`, `index.js:13`).
2. **Mobile is fundamentally broken** — no viewport meta plus a fixed 750px terminal clips the command off-screen at 375px (`index.html:2-3`, `index.css:8`).
3. **CTA delayed 11–18 seconds** by non-skippable typing, with no static content or skip control (`index.js:98-109`).
4. **First impression is a fake password prompt** with no value proposition, confusing visitors and undermining trust before the product is even seen (`wireguard.sh.txt:1-4`).
5. **The primary action is a non-focusable `<div>`** with a hover-only affordance, so keyboard, screen-reader and mobile users cannot reliably copy the command (`wireguard.sh.txt:13,16`, `index.js:111`).
