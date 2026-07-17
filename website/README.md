# velo-site

Marketing landing page for [Velo](https://github.com/realvidhaan/velo) — open-source
macOS voice dictation. Self-contained static site, no build step.

- `index.html` — all sections
- `styles.css` — design tokens, layout, motion
- `script.js` — intro sequence, cursor-follow glow, footer equalizer
- `assets/` — Velo mark + favicon (SVG)

Primary CTA links to the latest release DMG:
`https://github.com/realvidhaan/velo/releases/latest/download/Velo.dmg`

## Run locally

```sh
python3 -m http.server 8080
# open http://localhost:8080
```

## Deploy

Static — deploy the folder to any host. On Vercel: no framework, output = repo root.
