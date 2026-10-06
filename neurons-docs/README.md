# Neurons Documentation

## Project

Documentation website for **Neurons**, Confoline's Application Performance Monitoring (APM) platform: the *Application Monitoring Guide*, in English and French.

- Production: `https://docs.confoline.com/neurons/` (English) and `https://docs.confoline.com/neurons/fr/` (French)
- Content is written in **Markdown**. [Hugo](https://gohugo.io) turns it into a plain static site (HTML/CSS/JS) that Nginx serves. There's no server-side code and nothing is loaded from third-party sites.
- The sidebar, the "On this page" table of contents, the language switcher and the page metadata are **generated** from the content. You never edit them by hand.

```text
neurons-docs/
├── content/
│   ├── en/
│   │   ├── _index.md                  page title, description, intro text
│   │   └── guide/                     the guide, one file per part (order = weight)
│   │       ├── 01-introduction.md
│   │       ├── 02-application-monitoring.md
│   │       ├── 03-observability.md
│   │       ├── 04-alerting.md
│   │       ├── 05-administration.md
│   │       └── 06-reference.md
│   └── fr/                            same files, in French
├── i18n/en.toml, i18n/fr.toml         interface text (search placeholder, labels…)
├── layouts/                           page templates (design); edit only to change the layout
├── assets/css/main.css, assets/js/    styles and behaviour (fingerprinted at build time)
├── static/assets/fonts, images/       fonts (+ licences), logo, favicons, copied as-is
├── hugo.toml                          site settings (base URL, languages)
├── deploy/
│   ├── nginx.conf.example             Nginx configuration
│   ├── install-hugo.sh                installs the pinned Hugo version on the server
│   └── update.sh                      pull + build + publish, on the server
└── tools/preview.py                   preview the production build under /neurons/
```

## Writing content

All documentation text lives in `content/<language>/guide/*.md`. Edit the English file and its French counterpart.

### Sections

Each `##` heading is a section. It appears automatically in the sidebar and in the table of contents. Give every section an **ID** in braces, and use the **same ID in both languages**. The language switch uses it to keep the reader on the same section, and it's the anchor in URLs (`…/neurons/#retention`).

```markdown
## Data Retention {#retention}

Text in **Markdown**…

### A sub-heading (not listed in the sidebar)
```

The sidebar uses the heading text by default. To show a shorter label, add it to the part's front matter (the block between `---` at the top of the file):

```yaml
labels:
  retention: Data retention          # sidebar + table of contents
tocLabels:
  otel: OTel instrumentation         # table of contents only (optional)
```

### Front matter of a part

```yaml
---
title: Administration & Operations   # label shown above the part's content
navTitle: Administration             # group title in the sidebar (optional, defaults to title)
part: part4                          # unique key for the part (same in both languages)
weight: 5                            # position in the guide
---
```

To add a new part, create `07-something.md` in **both** `content/en/guide/` and `content/fr/guide/` with a new `part` key and `weight: 7`. Nothing else needs to change.

### Formatting cheat sheet

| You want | Write |
|---|---|
| Bold, italic, inline code | `**bold**`, `*italic*`, `` `X-Neurones-Token` `` |
| Bullet list | `- item` |
| Numbered steps (purple circles) | a `1. 2. 3.` list followed by `{.steps}` on the next line |
| Blue tip box | `{{< callout >}}Text{{< /callout >}}` |
| Orange warning box | `{{< callout type="warn" >}}Text{{< /callout >}}` |
| Monospace name (no grey box) | `{{< mono "deploy-neurons-apm.sh" >}}` |
| Small grey note paragraph | the paragraph followed by `{.ref-note}` on the next line |
| Table | a normal Markdown table, optionally followed by settings on the next line (below) |

Table settings, written on the line right after the table:

```markdown
| Category | Default | Range |
|---|---|---|
| Logs | 30 d | 1–90 d |
{mono="2,3" firstcol="26"}
```

- `mono="2,3"` shows columns 2 and 3 in monospace.
- `firstcol="26"` (or `"30"`) sets the first column's width in percent.

Tables scroll sideways on small screens automatically.

### Getting Started pages (separate pages)

The sidebar's **Getting Started** group lists standalone pages such as `content/en/application-onboarding/php.md`, published at `…/neurons/application-onboarding/php/`. A page joins the group through its front matter:

```yaml
---
title: PHP Application Onboarding        # page title (h1)
linkTitle: PHP                           # label in the sidebar
menus:
  onboarding:
    parent: opentelemetry                # category id (defined in hugo.toml, per language)
    weight: 10                           # order within the category
---
```

Create the same file (same path) in `content/fr/` for the French version. Its `## Heading {#id}` sections appear in the page's right-hand table of contents. Categories are `[[languages.<lang>.menus.onboarding]]` entries in `hugo.toml` (one per language) and can be nested with `parent`: today *Application Onboarding* contains *OpenTelemetry* (PHP, Java, .NET, Node.js, Python) and the *Browser RUM* page. Each level is indented one step in the sidebar. `noindex: true` keeps a page out of search engines; remove it once the page has real content.

### Interface text

Texts that aren't documentation (search placeholder, "On this page", footer…) are in `i18n/en.toml` and `i18n/fr.toml`. The page title, description and intro sentence are in `content/<language>/_index.md`.

## Local preview

Install Hugo once. Version **0.158 or newer** is required; the project is tested with 0.167.0, the version the server uses.

```powershell
winget install Hugo.Hugo        # Windows. macOS: brew install hugo
```

Then, from `neurons-docs/`:

```bash
hugo server
```

Open <http://localhost:1313/neurons/>. The page reloads automatically every time you save a file.

To check the exact production build under the `/neurons/` prefix:

```bash
hugo --minify            # writes the site to public/ (not committed)
python tools/preview.py  # http://localhost:8080/neurons/, 404 for anything outside /neurons/
```

To reset the remembered language in the browser, run `localStorage.removeItem('neurons-lang')` in the console.

## Production deployment

| | |
|---|---|
| Git clone on the server | `/var/www/neurones-doc` (the Hugo project is its `neurons-docs/` folder) |
| Directory served by Nginx | `/var/www/neurons-docs` (build output only) |
| Public URL | `https://docs.confoline.com/neurons/` |

### Publishing an update

1. On your computer, edit the Markdown, check it with `hugo server`, then `git commit` and `git push`.
2. On the server, as root:

   ```bash
   /var/www/neurones-doc/neurons-docs/deploy/update.sh
   ```

   The script pulls the repository, builds into a temporary folder, and only replaces the live site if the build succeeds. It also sets permissions and the SELinux labels. You don't need to reload Nginx.

### First-time setup on a new server

```bash
dnf install -y git rsync nginx
git clone https://github.com/noureddinekrichen/neurones-doc.git /var/www/neurones-doc
bash /var/www/neurones-doc/neurons-docs/deploy/install-hugo.sh      # pinned version, checksum-verified
bash /var/www/neurones-doc/neurons-docs/deploy/update.sh
```

Then set up Nginx and the certificate as described below. To upgrade Hugo later, change `HUGO_VERSION` in `deploy/install-hugo.sh` and run it again.

### Nginx

`deploy/nginx.conf.example` contains a complete `server` block for `docs.confoline.com`. Neurons claims **only** `/neurons/`, so other documentation can live on the same domain. If a server block for the domain already exists, copy only the part between the `NEURONS DOCS` markers into it.

The example expects a Let's Encrypt certificate in `/etc/letsencrypt/live/docs.confoline.com/`. Get it with:

```bash
certbot certonly --webroot -w /var/www/letsencrypt -d docs.confoline.com
```

The HTTP block keeps `/.well-known/acme-challenge/` on plain HTTP, so renewals work.

Caching: HTML is always revalidated. CSS/JS file names contain a content hash (added by the build), so they're cached for a year and still update immediately when they change. Fonts and images are cached for a day.

```bash
/bin/cp -f /var/www/neurones-doc/neurons-docs/deploy/nginx.conf.example /etc/nginx/conf.d/docs.confoline.com.conf
nginx -t && systemctl reload nginx
```

### Checks

```bash
curl -I https://docs.confoline.com/neurons/        # 200
curl -I https://docs.confoline.com/neurons/fr/     # 200
curl -I http://docs.confoline.com/neurons/         # 301 -> https
curl -I https://docs.confoline.com/neurons         # 301 -> /neurons/
```

## Third-party assets

The fonts are self-hosted copies of **IBM Plex Sans**, **IBM Plex Mono** and **Plus Jakarta Sans** (Latin subset, as distributed by Google Fonts). All three are licensed under the SIL Open Font License 1.1, which allows redistribution. The licence texts are in `static/assets/fonts/OFL-*.txt` and must stay alongside the font files.
