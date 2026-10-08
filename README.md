# NSA Cybersecurity Directorate — Recruitment Site

Recruitment website and CSD-01 assessment for the National Security Agency division of a Roblox milsim roleplay group. Not affiliated with the U.S. Government.

| Page | Purpose |
| --- | --- |
| `index.html` | Landing page: mission, divisions, selection pipeline, requirements, FAQ |
| `apply.html` | CSD-01 assessment: 43 randomized items, 50 minute timer, item navigator, flagging, review screen |

## Hosting on GitHub Pages

1. Merge this branch into the repository's default branch.
2. Open **Settings → Pages** in the repository.
3. Under **Build and deployment**, set **Source** to **Deploy from a branch**.
4. Pick the default branch and the `/ (root)` folder, then click **Save**.
5. After a minute the site is live at `https://<username>.github.io/<repository>/`.

GitHub Pages on a free account requires the repository to be public.

## Receiving submissions

Submissions are posted as a Discord-style embed to the URL in `WEBHOOK_URL` at the top of `assets/js/assessment.js`. It is empty by default, so nothing is sent.

Anything in this repository is public once Pages is on. A Discord webhook URL pasted directly into `assessment.js` can be copied by anyone and used to spam or delete the webhook. Put a small relay (for example a Cloudflare Worker) between the site and Discord, and set `WEBHOOK_URL` to the relay's URL instead.

Each submission includes callsign, rank, score, pass/fail, answered count, duration, focus-loss count, end condition, and a per-domain breakdown.

## Editing the assessment

Questions, time limit, and pass mark live in `assets/js/bank.js`. The answer key in that file is encoded against the current option order, so changing a question's options or adding questions requires regenerating the `key` and `salt` values.

The key is obfuscated, not secret: a determined candidate can read it from the browser. Command review of the score, timing, and focus-loss log is the real control.

## Structure

```
index.html
apply.html
assets/
  css/site.css
  js/site.js
  js/bank.js
  js/assessment.js
  img/seal.webp, hero.webp, og.jpg, favicon.png, apple-touch-icon.png
```
