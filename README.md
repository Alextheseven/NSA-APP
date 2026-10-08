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

Each completed assessment posts one message to your Discord channel through a webhook:

- **Summary embed:** candidate, rank, submission ref, score, pass/fail, answered and flagged counts, duration, focus-loss count and time away, end condition, per-domain breakdown, and an answer grid in the order the candidate saw the items.
- **Answer sheet (`.txt` attachment):** every item with the candidate's answer, the correct answer when they missed it, time spent on the item, and flags, plus a timestamp for each time they left the window.

### Setup

1. In Discord, open the channel's **Settings → Integrations → Webhooks → New Webhook**, then **Copy Webhook URL**.
2. Open `https://<username>.github.io/<repository>/tools/webhook.html`.
3. Paste the URL, click **Send Test Message**, and check that it shows up in the channel.
4. Click **Encode**, then **Copy Line**.
5. On GitHub, edit `assets/js/config.js` and replace `webhook: "",` with the copied line. Commit.
6. After Pages republishes, the assessment header shows **SECURE LINK**. If it shows **LINK OFFLINE**, the webhook is missing or Discord rejected it, and candidates cannot start.

`config.js` also accepts the raw `https://discord.com/api/webhooks/...` URL, but the encoded form keeps bots that scan GitHub for webhook links from matching it.

### What to know about a webhook on a public site

The webhook has to ship to every candidate's browser to work, so anyone determined can pull it from developer tools. Encoding only stops automated scrapers. Someone with the URL can post fake messages to the channel or delete the webhook.

- Use a dedicated channel that only the webhook posts to and only reviewers can read.
- If the channel gets spammed, delete the webhook in Discord, create a new one, and repeat the setup. Old links stop working immediately.
- Forged submissions are possible. Check the answer sheet, the submission ref, and the timing before acting on a score.
- The answer sheet, including the correct answer for every missed item, is built in the candidate's browser and is visible in their developer tools when it is sent. The answer key already ships in `assets/js/bank.js`, so this does not expose anything new, but a candidate who does a throwaway run can read it more easily. Watch for repeat attempts (the `device attempt` counter) and near-perfect runs with very short item times.

Each attempt is also numbered per device, and a repeated delivery after a network retry shows `delivery attempt N` in the embed footer with the same submission ref.

To keep the webhook out of the browser entirely, put a small relay (for example a Cloudflare Worker) in front of Discord. It holds the real webhook URL, forwards the request body unchanged, and returns Discord's status with CORS headers. Set `webhook` in `config.js` to the relay's `https://` URL. The site sends Discord's multipart format: a `payload_json` field and the answer sheet as `files[0]`.

When the browser can't read Discord's reply, the result screen says **Transmitted (unconfirmed)**. The message was sent, but the page can't tell whether Discord accepted it.

If a submission can't be delivered, the candidate sees **Transmission Failed** with a retry button and is told to send their submission ref to command.

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
  js/config.js        webhook setting
  js/bank.js          questions, time limit, pass mark, answer key
  js/assessment.js
  img/seal.webp, hero.webp, og.jpg, favicon.png, apple-touch-icon.png
tools/
  webhook.html        webhook encoder and test sender
```
