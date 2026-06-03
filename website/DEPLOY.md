# GitHub Pages deployment

URL: **https://luginf.github.io/writhdeck/**

## Setup (one-time)

In the repo settings: **Settings → Pages → Source → GitHub Actions**

That's it. The workflow `.github/workflows/pages.yml` handles the rest.

## How it works

- Triggers on every push to the `website` branch that touches `website/**`
- Publishes only the contents of `website/` (not the rest of the repo)
- Can also be triggered manually via Actions → "Deploy website to GitHub Pages" → Run workflow

## Update the site

```sh
git checkout website
# edit website/index.html or website/writhdeck.html
git add website/
git commit -m "update website"
git push
# GitHub Actions deploys automatically
```
