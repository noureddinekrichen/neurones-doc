# Neurons Documentation

## Project

Static documentation website for **Neurons**, Confoline's Application Performance Monitoring (APM) platform. It contains the *Application Monitoring Guide* in English and French: services, traces, business transactions, observability, alerting, administration, deployment, the query API, and a glossary.

- Production URL: `https://docs.confoline.com/neurons/` (English), `https://docs.confoline.com/neurons/fr/` (French)
- Plain HTML, CSS and JavaScript. No build step, no framework, no server-side code, no third-party requests at runtime.
- Every URL in the pages is relative, so the site works under the `/neurons/` base path (and under any other prefix).

```text
neurons-docs/
├── index.html                  English guide (default page)
├── fr/
│   └── index.html              French guide
├── assets/
│   ├── css/main.css            All styles (fonts, layout, responsive rules)
│   ├── js/main.js              Drawer, nav filter, "/" shortcut, active-section tracking, language menu
│   ├── js/lang-redirect.js     English page only: sends visitors who chose French to fr/
│   ├── images/                 Official Neurons icon (SVG), PNG favicons rendered from it, search icon
│   └── fonts/                  Self-hosted IBM Plex Sans/Mono and Plus Jakarta Sans (+ OFL licences)
├── deploy/nginx.conf.example   Example Nginx configuration (reference only)
├── tools/preview.py            Local preview server that mimics the /neurons/ prefix (not deployed)
├── README.md
└── .gitignore
```

### How the pages work

- Each language is a complete static page. The language selector links between them and keeps the current section (e.g. `…/neurons/#retention` ↔ `…/neurons/fr/#retention`).
- The visitor's choice is stored in `localStorage` (`neurons-lang`). When it is `fr`, opening `/neurons/` redirects to `/neurons/fr/`. An explicit `/neurons/fr/` link is never redirected.
- `main.js` doesn't depend on any specific content. It works on any page that uses the same markup: `#sidebar` with `.nav-link`s, `.toc-group[data-toc-part]`, `.doc-part[data-part]` sections, and `h2[id]` headings.

### Adding or changing content

- Edit the text in `index.html` and its counterpart in `fr/index.html`. Keep the section `id`s identical in both languages, because the language switch relies on them.
- For a new section, add the `<h2 id="…">` in both pages, plus a matching link in the sidebar (`.nav-link`) and the right-hand TOC (`.toc-group` of the same part).
- For a new standalone page or module, copy a page as a template, keep the header and sidebar markup, and link to it with a relative path (e.g. `alerting/`). Pages one folder deeper reference assets with `../assets/…`, like `fr/index.html` does.
- Never use root-relative URLs (`/assets/…`). They would resolve outside `/neurons/`.
- The pages contain no inline `<script>` or `style="…"`, which keeps them compatible with the strict Content-Security-Policy in the Nginx example. Keep it that way.

## Local preview

The site must be served over HTTP. Opening the file directly (`file://`) works for reading but isn't representative.

**Recommended: preview under the real base path** (Python 3, standard library only):

```bash
cd neurons-docs
python tools/preview.py          # or: python tools/preview.py 9000
```

Open <http://localhost:8080/neurons/>. Any request outside `/neurons/` returns 404, so a root-relative path that would break in production also breaks here.

**Quick alternative:**

```bash
cd neurons-docs
python -m http.server 8080
```

Open <http://localhost:8080/>. This serves the site at the root, so it does **not** catch base-path mistakes.

To reset the remembered language, run `localStorage.removeItem('neurons-lang')` in the browser console.

## Production deployment

|                       |                                       |
|-----------------------|---------------------------------------|
| Server directory      | `/var/www/neurons-docs`               |
| Public URL            | `https://docs.confoline.com/neurons/` |
| Files to deploy       | `index.html`, `fr/`, `assets/`        |
| Do **not** deploy     | `README.md`, `deploy/`, `tools/`, `.gitignore` |

### 1. Package and upload

```bash
# on your workstation, from neurons-docs/
tar -czf neurons-docs.tar.gz index.html fr assets
scp neurons-docs.tar.gz <user>@<server>:/tmp/
```

### 2. Install on the server

Extract into a fresh directory and swap it in, so files removed from the project don't linger:

```bash
sudo mkdir -p /var/www/neurons-docs.new
sudo tar -xzf /tmp/neurons-docs.tar.gz -C /var/www/neurons-docs.new

# permissions: owned by root, readable by nginx
sudo chown -R root:root /var/www/neurons-docs.new
sudo find /var/www/neurons-docs.new -type d -exec chmod 755 {} +
sudo find /var/www/neurons-docs.new -type f -exec chmod 644 {} +

# swap (keeps the previous version for rollback)
[ -d /var/www/neurons-docs ] && sudo rm -rf /var/www/neurons-docs.prev && sudo mv /var/www/neurons-docs /var/www/neurons-docs.prev
sudo mv /var/www/neurons-docs.new /var/www/neurons-docs

# Rocky Linux runs SELinux in enforcing mode: give the files the web-content label,
# otherwise nginx answers 403 even with correct permissions
sudo restorecon -Rv /var/www/neurons-docs
rm /tmp/neurons-docs.tar.gz
```

Rollback: `sudo rm -rf /var/www/neurons-docs && sudo mv /var/www/neurons-docs.prev /var/www/neurons-docs`.

### 3. Nginx

`deploy/nginx.conf.example` contains a complete `server` block for `docs.confoline.com`. Neurons claims **only** `/neurons/`, so other documentation can live on the same domain. If a server block for the domain already exists, copy only the part between the `NEURONS DOCS` markers into it. It expects a Let's Encrypt certificate in `/etc/letsencrypt/live/docs.confoline.com/`, issued with `certbot certonly --webroot -w /var/www/letsencrypt -d docs.confoline.com`. The HTTP block keeps `/.well-known/acme-challenge/` on plain HTTP so renewals work.

Validate, then reload (a reload doesn't drop connections):

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### 4. Check

```bash
curl -I https://docs.confoline.com/neurons/                      # 200
curl -I https://docs.confoline.com/neurons/fr/                   # 200
curl -I https://docs.confoline.com/neurons/assets/css/main.css   # 200, text/css
curl -I https://docs.confoline.com/neurons                       # 301 -> /neurons/
curl -I https://docs.confoline.com/neurons/README.md             # 404
```

Then open both pages in a browser and check the developer console: there should be no errors and no blocked (CSP) resources.

## Third-party assets

The fonts are self-hosted copies of **IBM Plex Sans**, **IBM Plex Mono** and **Plus Jakarta Sans** (Latin subset, as distributed by Google Fonts). All three are licensed under the SIL Open Font License 1.1, which allows redistribution. The licence texts are in `assets/fonts/OFL-*.txt` and must stay alongside the font files.
