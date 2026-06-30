# Wanted Design System

A faithful, code-first recreation of the **Wanted Design System** — the foundations and UI components behind **Wanted** (원티드), Korea's leading AI-powered career & recruiting platform. Wanted connects job seekers with companies through AI matching, referral rewards (합격축하금), and a professional community. Surfaces include the Wanted jobs app/website plus sub-brands (Wanted Gigs, Wanted Space, Wanted LaaS, Wanted Agent, OneID).

This project is the design system itself: design tokens, typography, color, icons, brand assets, reusable React components, and a full product UI kit — everything needed to design and build on-brand Wanted interfaces.

## Source
- **Figma:** *Wanted Design System (Community)* — the attached `.fig` file is the source of truth. Tokens, the type scale, components and the ~126-glyph icon set were extracted directly from it. (Community file; search "Wanted Design System" on Figma Community.)
- **Fonts:** Pretendard JP (variable) and Wanted Sans Variable — both SIL OFL, **self-hosted** in `assets/fonts/` (no CDN/network needed).

---

## Content fundamentals (voice & tone)

Wanted's product copy is **Korean-first, warm, and direct** — it speaks *to* the user, often by name.

- **Person:** addresses the user directly, frequently with the honorific name pattern "**원티님**" ("Dear 원티"). Speaks as a helpful guide, not a faceless system.
- **Tone:** encouraging and momentum-oriented around career growth — "커리어의 모든 순간", "나에게 딱 맞는 포지션". Confident but never hype-y.
- **Casing & length:** Korean has no case; headlines are short, punchy, often two lines. Labels are terse nouns ("지원 현황", "받은 제안", "북마크").
- **Numbers/value:** concrete and benefit-led — "합격축하금 1,000,000원", "AI 매칭 97%", "마감 D-3".
- **Emoji:** essentially none in core product UI. Meaning is carried by icons and the AI/sparkle motif, not emoji.
- **English:** used for job/tech terms (React, UX/UI, Node.js) and sub-brand names; everything else is Korean.

Examples: "원티님께 딱 맞는 포지션을 찾았어요" · "이력서가 정상적으로 제출되었습니다" · "이 포지션은 마감이 3일 남았어요".

---

## Visual foundations

**Color.** Built on an atomic ramp (per-hue 0–100) surfaced through semantic tokens that flip automatically for light/dark.
- **Primary = Wanted blue** `#3366FF` (normal) → `#005EEB` (strong) → `#0054D1` (heavy). The single dominant brand color; used for CTAs, links, selected states, the AI-match accent.
- **Accents:** violet `#6541F2` (the **AI / matching** motif) and cyan `#00BDDE`. A full accent set (pink, lime, orange, red-orange, light-blue) exists for content tagging.
- **Neutrals are cool greys** (`cool-neutral`, slightly blue-tinted) — not pure greys. Text is near-black `#171717`; surfaces are white / `#F7F7F8`.
- **Status:** positive `#00BF40`, negative `#FF4242`, cautionary `#FF9200`.
- **Text uses opacity-based labels** (label/normal, /neutral 88%, /alternative 61%, /assistive 28%, /disable 16%) so hierarchy holds on any background. Fills and lines are likewise translucent grey (`rgba(112,115,124, …)`).

**Type.** Pretendard JP for all UI; Wanted Sans for the logo/large display. One scale, role-named: Display (56/40) → Title (36/28/24) → Heading (22/20) → Headline (18/17) → Body (16/15) → Label (14/13) → Caption (12/11). Tight negative tracking on large sizes (down to −3.2%), slightly positive on small sizes. Default UI weight is Medium (500); headings SemiBold/Bold.

**Spacing & radius.** 4px base grid (4/8/12/16/20/24/32…). Generous, airy density. Corner radii are soft and fairly large: 8–12 on controls, **16 on cards**, 12–20 on sheets, full-round (pills) on chips/avatars/switches.

**Backgrounds.** Clean and flat — white or `#F7F7F8`, no gradients or textures on content surfaces. Thick 8px grey **section dividers** separate blocks on mobile. Imagery (company/portfolio) sits inside rounded containers; the brand itself stays flat.

**Elevation.** Soft, low-opacity neutral shadows (black/cool-grey at 6–10%), never harsh. Cards combine a hairline border with a faint shadow. Modals dim with `rgba(23,23,25,0.52)`.

**Motion.** Restrained: 150ms ease color/background transitions, a subtle scale-down on press (~0.98), no bounces or decorative loops. Hover = a translucent overlay / fill darken; press = a deeper overlay or the strong/heavy color step.

**Cards.** White surface, 16px radius, 1px `line/alternative` border + `shadow-normal`; interactive cards lift to `shadow-strong` on hover and nudge down 1px on press.

---

## Iconography

- **One cohesive in-house icon family** (~126 glyphs) on a **24×24 grid**, drawn as filled/stroked vector shapes — *not* an off-the-shelf set. Most glyphs ship in **outline + fill pairs** (e.g. `home`/`homeFill`, `bell`/`bellFill`, `bookmark`/`bookmarkFill`); fill = active/selected, outline = default. Some have Thick / Tight / Small variants for tap targets.
- Extracted to `assets/icons/` as **`icon-data.js`** (101 curated glyphs, `{viewBox, body}` markup) + an **`Icon`** React component. Icons paint with `currentColor`, so recolor via CSS `color`. Usage: `<Icon name="search" size={24} />`.
- Brand logos live in `assets/logo/` as single-path `currentColor` SVGs: `wanted-symbol.svg` (the "W/길" mark) and `wanted-wordmark.svg`. Recolor with CSS masks (see the brand card / app AppBar).
- **No emoji** and no unicode-glyph icons in product UI. The **sparkle** glyph + violet is the recurring AI/matching signifier.

---

## Index / manifest

**Foundations (root)**
- `styles.css` — global entry point (imports only). Consumers link this one file.
- `tokens/fonts.css` · `tokens/typography.css` · `tokens/spacing.css` · `tokens/semantic.css`
- `components/fig-tokens.css` — full Figma Variable set (atomic + semantic, light/dark/size modes)
- `components/components.css` — component class styles (states, variants)

**Components** (`components/<group>/` — React `.jsx` + `.d.ts` + `.prompt.md` + a `@dsCard`)
- brand: **Logo** (symbol + wordmark, inline SVG, recolorable)
- action: **Button**, **IconButton**
- data: **Badge**, **Tag**, **Chip**
- display: **Avatar**, **Card**, **Divider**
- forms: **TextField**, **Checkbox**, **Radio**, **Switch**
- feedback: **Alert**, **Tooltip**
- navigation: **Tabs**, **BottomNavigation**
- icons: **Icon** (`assets/icons/`)

**Guidelines** (`guidelines/*.card.html`) — foundation specimen cards: color (primary/neutral/status/text-surface), type (display/body), spacing, radius & elevation, brand logo.

**UI kit** (`ui_kits/wanted-app/`) — interactive Wanted jobs app (login → feed → job detail → MY).

**Other** — `SKILL.md` (Agent Skill manifest), `readme.md` (this file).

The compiler generates `_ds_bundle.js`, `_ds_manifest.json`, `_adherence.oxlintrc.json` automatically — never edit those.

---

## Substitutions & caveats
- **Fonts are self-hosted** in `assets/fonts/` (Pretendard JP variable + Wanted Sans Variable, 92 subset files) — fully offline, SIL OFL.
- The icon set is a **curated 101 of ~126** glyphs (the high-use UI + brand glyphs); more can be materialized on request.
- Company logos in the UI kit are brand-colored initials, not official logo assets.
