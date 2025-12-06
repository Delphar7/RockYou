# RockYou End‑User Web Docs

This folder contains a small, self-contained end-user documentation page:

- `index.html`
- `style.css`
- `Images/*.svg`

## Preview locally

Open `index.html` directly (no build step), or serve it:

```bash
cd /Users/joe/src/xcode/RockYou/Resources/Web
python3 -m http.server 8000
```

Then visit `http://localhost:8000`.

## Replacing diagrams with real screenshots

Drop screenshots into `Resources/Web/Images/` and update the `<img src="...">` paths in `index.html`.
