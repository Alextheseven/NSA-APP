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

## Receiving submissions in Discord

Submissions go through a small relay that runs on Cloudflare Workers (free plan). The relay is the only thing that knows the Discord webhook and the answer key. Neither is in this repository or in any visitor's browser.

```
candidate's browser ──► relay (Cloudflare Worker) ──► Discord webhook
                          holds: webhook, answer key, Turnstile secret
```

How the relay protects the webhook:

- **Turnstile bot check:** candidates pass Cloudflare Turnstile before an attempt starts. Scripts can't start sessions in bulk. The relay refuses to run without a Turnstile secret.
- **Signed session:** the relay hands out a signed session token at start. `/submit` only accepts a valid token that is under 65 minutes old, and posts once per session.
- **Allowed origin only:** requests are accepted only from the origin in `ALLOWED_ORIGIN`. Each IP can start at most 8 attempts per 10 minutes.
- **Graded by the relay:** the score is computed from the submitted answers with the secret key. A forged score is impossible, and the correct answers never reach the browser.
- **Relay clock:** start time, receipt time, and duration are measured by the relay, not the candidate's browser.

Each submission posts one message:

- **Summary embed:** candidate, rank, submission ref, score, pass/fail, answered and flagged counts, duration (with a warning if it ran over the limit), focus-loss count and time away, end condition, per-domain breakdown, and an answer grid in the order the candidate saw the items.
- **Answer sheet (`.txt` attachment):** every item with the candidate's answer, the correct answer when they missed it, time on each item, and flags, plus a timestamp for each time they left the window.

### Setup

Allow about 15 minutes. You need a free Cloudflare account.

**1. Discord webhook**

1. In Discord, open the private reviewer channel's **Settings → Integrations → Webhooks**.
2. Delete any webhook that was ever committed to this repository.
3. Create a new webhook and **Copy Webhook URL**. Keep it out of this repository.

**2. Turnstile widget**

1. In the Cloudflare dashboard, open **Turnstile → Add widget**.
2. Add the hostname `alextheseven.github.io`, choose **Managed** mode, and create the widget.
3. Copy the **Site Key** (public) and the **Secret Key** (private).

**3. Relay worker**

1. Open **Workers & Pages → Create → Create Worker**, name it `nsa-relay`, and deploy the starter.
2. Click **Edit code**, replace everything with the contents of `relay/worker.js`, and click **Deploy**.
3. Open the worker's **Settings → Variables and Secrets** and add:

| Name | Type | Value |
| --- | --- | --- |
| `DISCORD_WEBHOOK` | Secret | the new webhook URL |
| `ANSWER_KEY` | Secret | the answer key value (see below) |
| `TURNSTILE_SECRET` | Secret | the Turnstile secret key |
| `ALLOWED_ORIGIN` | Text | `https://alextheseven.github.io` |
| `SITE_URL` | Text | `https://alextheseven.github.io/NSA-APP/` |
| `SESSION_SECRET` | Secret | optional: any long random string. If you skip it, the webhook URL signs sessions instead. |
| `BOT_NAME` | Text | optional: the name shown on messages |

4. Deploy, then copy the worker URL, for example `https://nsa-relay.<your-subdomain>.workers.dev`.

If you use the Wrangler CLI instead, `relay/wrangler.toml` holds the non-secret values. Add the secrets with `wrangler secret put NAME`.

**4. Site config**

Edit `assets/js/config.js` on GitHub:

```js
window.NSA_CONFIG = Object.freeze({
  relay: "https://nsa-relay.<your-subdomain>.workers.dev",
  turnstileSiteKey: "<Turnstile site key>"
});
```

Both values are public by design. After Pages republishes, hard-refresh `apply.html` (Ctrl+Shift+R). The header should show **SECURE LINK**. Run one test attempt with a throwaway callsign and confirm the message arrives.

If the header shows **LINK OFFLINE**, the notice says why:

- **No relay configured:** `relay` is empty in `config.js`.
- **Relay unreachable:** the URL is wrong, or `ALLOWED_ORIGIN` doesn't match the site.
- **`webhook`:** `DISCORD_WEBHOOK` is missing or isn't a Discord webhook URL.
- **`webhook_dead`:** Discord says the webhook was deleted. Create a new one and update the secret. This check refreshes every few minutes.
- **`turnstile` / `turnstile_secret`:** `TURNSTILE_SECRET` is missing or wrong. The name must match exactly.
- **Turnstile site key missing / misconfigured:** `turnstileSiteKey` is empty in `config.js`, or the widget isn't set up for `alextheseven.github.io`.
- **`answer_key`:** `ANSWER_KEY` is missing or doesn't match the current questions (see below).
- **`bank` / `site_url`:** the relay can't load `assets/data/bank.json` from `SITE_URL`.
- **"The assessment was just updated":** the questions changed moments ago. Wait a minute and hard-refresh.

### Answer key

`ANSWER_KEY` looks like `5d052ba48a80:0213...`:

- **Before the colon:** a fingerprint of the current `assets/data/bank.json` questions.
- **After the colon:** one digit (0 to 3) per question, giving the position of the correct option in that question's `a` list.

The fingerprint ties the key to the exact question set. If anyone edits, adds, or reorders questions or options, the relay notices the mismatch and goes offline. It won't grade against the wrong answers. Sessions started on an older question set are rejected with "assessment changed", not misgraded.

To build or update the key:

1. Publish the question changes.
2. Open `https://alextheseven.github.io/NSA-APP/tools/answer-key.html`.
3. Paste the current key and click **Load Existing Key** to pre-fill the answers.
4. Fix the answers, click **Build Key**, and paste the result into the `ANSWER_KEY` secret.

The page runs entirely in your browser and contains no answers itself. Never commit the key to this repository.

Earlier versions of this repository shipped the answer key to the browser. Those versions are still in git history, so treat the current questions as seen. Rotating in new questions over time fixes that.

### Limits

- Item timing and focus-loss data come from the candidate's browser, so a technical candidate can fake them. Score, duration, and session are enforced by the relay.
- Duplicate protection and the per-IP limit (8 starts per 10 minutes per IPv4 address or IPv6 /64) live in worker memory, so they are best effort. Retries of the same session show the same submission ref.
- If Discord is down when a candidate submits, the result screen offers a retry. The relay keeps the original receipt time, so a late retry isn't marked over the time limit.

## Structure

```
index.html
apply.html
assets/
  css/site.css
  js/site.js
  js/config.js        relay URL and Turnstile site key (public)
  js/assessment.js
  data/bank.json      questions, time limit, pass mark (no answers)
  img/seal.webp, hero.webp, og.jpg, favicon.png, apple-touch-icon.png
relay/
  worker.js           Cloudflare Worker: Turnstile, sessions, grading, Discord delivery
  wrangler.toml       optional Wrangler CLI config
tools/
  answer-key.html     builds the ANSWER_KEY value from the published questions
```
