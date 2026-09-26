---
name: anubis-bypass
description: Bypass Anubis proof-of-work challenges when fetching web content from sites protected by TecharoHQ/anubis, without needing a browser. Use this skill whenever a web_fetch or curl command returns an Anubis challenge page (look for "anubis" in cookies, HTML mentioning "Checking your browser" or "Making sure you're not a bot", ".within.website" paths, or "techaro" in set-cookie headers). Also use this skill proactively when the user asks to fetch content from sites known to use Anubis (e.g. git.kernel.org, lore.kernel.org, many Gitea/Forgejo instances, FreeCad forums, and other self-hosted open-source project sites). The skill solves the SHA-256 proof-of-work challenge in Python and returns a valid session cookie so subsequent requests go through without a browser.
---

# Anubis Bypass Skill

## Usage

**Always use the bundled Python script** — it handles the full flow and both
challenge formats automatically:

```bash
# Fetch the content directly (writes the page body to stdout)
python3 scripts/anubis_solve.py --fetch "https://example.com/page"

# Or get a reusable auth cookie and drive curl yourself
AUTH=$(python3 scripts/anubis_solve.py "https://example.com/page")
curl -b "$AUTH" -A "Mozilla/5.0 (X11; Linux x86_64)" "https://example.com/other/page"
```

Add `-v` to see the salt, difficulty, nonce, and the pass-challenge URL on
stderr. The script exits non-zero with an explanatory message on failure.

The auth cookie is a JWT scoped to the whole domain and valid for ~7 days,
so solve once and reuse it for every subsequent request to that site.

## How to detect an Anubis challenge

- HTML containing `<script id="anubis_challenge" ...>`, "Making sure you're
  not a bot!", or "Checking your browser".
- References to `/.within.website/x/cmd/anubis/` paths.
- A `set-cookie` clearing `*-anubis-auth=` (empty value), plus a
  `*-anubis-cookie-verification` (modern) or `*-anubis-cookie-test-*`
  (legacy) cookie.
- Note the response status is **200**, not 403 — a naive fetch silently
  returns the challenge HTML instead of the content you asked for.

## Challenge protocol

The script supports both formats and picks whichever the site serves.

### Modern format (Anubis ≥ ~v1.20, confirmed on v1.26.2)

The challenge is embedded in the challenge page as JSON:

```html
<script id="anubis_challenge" type="application/json">
{"rules":{"algorithm":"fast","difficulty":4},
 "challenge":{"id":"01a049a7-...","randomData":"37e97d04...","difficulty":4,...}}
</script>
<script id="anubis_base_prefix" type="application/json">""</script>
```

- **Salt** = `challenge.randomData` (a 64-byte hex string), *not* a cookie value.
- **Difficulty** = `rules.difficulty` (leading zero hex chars; typically 4).
- The server also sets a `*-anubis-cookie-verification` cookie that must be
  replayed on the pass-challenge request — a cookie jar handles this.
- `redir` is the **full URL**, matching what `main.mjs` sends.

### Legacy format

The salt is the value of a `*-anubis-cookie-test-*` `set-cookie` header, and
`redir` is the path only. Difficulty and challenge id are scraped from the HTML.

### The proof-of-work (identical in both formats)

Find an integer nonce such that

```
SHA-256( salt + str(nonce) )
```

has `difficulty` leading zero hex characters. Difficulty 4 takes a few
thousand hashes — well under a second in pure Python.

### Submitting

```
GET <base_prefix>/.within.website/x/cmd/anubis/api/pass-challenge
    ?id=<challenge id>
    &response=<hex SHA-256 hash>
    &nonce=<integer nonce, decimal>
    &redir=<full URL (modern) or path (legacy)>
    &elapsedTime=<milliseconds>
```

On success the server responds 302 to `redir` and sets
`<domain>-anubis-auth=<JWT>; Path=/`.

## Important notes

- The nonce is an integer formatted as a decimal string (Go `%d` format).
- The browser worker splits nonces across threads; a single-threaded scan
  from 0 finds an equally valid solution.
- Send a browser-like `User-Agent` on **every** request, including the ones
  made with the auth cookie — the challenge metadata records the UA.
- Challenges expire (the verification cookie lasts ~30 minutes). If
  pass-challenge is rejected, just re-run the script for a fresh challenge.
- If the format changes again, dump the challenge page and re-read
  `/.within.website/x/cmd/anubis/static/js/main.mjs` and
  `.../worker/sha256-webcrypto.mjs` — those two files define the whole protocol.
