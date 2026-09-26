#!/usr/bin/env python3
"""
Anubis proof-of-work solver.

Solves SHA-256 proof-of-work challenges served by TecharoHQ/anubis
without needing a browser. Handles both challenge formats:

  * modern (>= v1.20-ish): the challenge is embedded in the page as
    <script id="anubis_challenge" type="application/json">, carrying
    randomData / difficulty / id, and the browser is issued a
    "*-anubis-cookie-verification" cookie.
  * legacy: the challenge salt is the value of a "*-anubis-cookie-test-*"
    Set-Cookie header.

Usage:
    # Print the auth cookie string (name=value)
    python3 anubis_solve.py "https://example.com/"

    # Fetch the page content after solving
    python3 anubis_solve.py --fetch "https://example.com/some/page"

    # Specify difficulty manually (default: read from challenge, else 4)
    python3 anubis_solve.py --difficulty 5 "https://example.com/"

    # Custom User-Agent
    python3 anubis_solve.py --user-agent "Mozilla/5.0 ..." "https://example.com/"
"""

import argparse
import hashlib
import json
import re
import sys
import time
from http.cookiejar import CookieJar
from typing import Any, cast
from urllib.parse import urlencode, urlparse
from urllib.request import Request, build_opener, HTTPCookieProcessor


DEFAULT_DIFFICULTY = 4
DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36"
)
ANUBIS_API_PREFIX = "/.within.website/x/cmd/anubis/api/"
BROWSER_HEADERS = {
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}


def mine_nonce(challenge: str, difficulty: int) -> tuple[int, str]:
    """
    Find a nonce such that SHA-256(challenge + str(nonce)) starts with
    `difficulty` leading zero hex characters.

    Returns (nonce, hex_hash).
    """
    prefix = "0" * difficulty
    challenge_bytes = challenge.encode("utf-8")

    for nonce in range(0, 2 ** 32):
        h = hashlib.sha256(challenge_bytes + str(nonce).encode("ascii")).hexdigest()
        if h.startswith(prefix):
            return nonce, h

    raise RuntimeError(f"Failed to find nonce after 2^32 attempts (difficulty={difficulty})")


def _embedded_json(html: str, element_id: str):
    """Read a <script id="..." type="application/json"> payload from the page."""
    m = re.search(
        r'<script[^>]+id="%s"[^>]*>(.*?)</script>' % re.escape(element_id),
        html,
        re.DOTALL,
    )
    if not m:
        return None
    try:
        return json.loads(m.group(1).strip())
    except json.JSONDecodeError:
        return None


def parse_modern_challenge(html: str) -> dict | None:
    """
    Parse the JSON challenge embedded by Anubis >= v1.20-ish.

    Returns {"salt", "difficulty", "id", "base_prefix"} or None.
    """
    payload = _embedded_json(html, "anubis_challenge")
    if not isinstance(payload, dict):
        return None

    challenge = payload.get("challenge") or {}
    rules = payload.get("rules") or {}
    salt = challenge.get("randomData")
    if not salt:
        return None

    base_prefix = _embedded_json(html, "anubis_base_prefix")
    return {
        "salt": salt,
        "difficulty": rules.get("difficulty") or challenge.get("difficulty"),
        "id": challenge.get("id"),
        "base_prefix": base_prefix if isinstance(base_prefix, str) else "",
    }


def parse_legacy_challenge(headers: list[tuple[str, str]], html: str) -> dict | None:
    """
    Parse the legacy challenge: the salt is the value of a
    "*-anubis-cookie-test-*" cookie, difficulty/id scraped from the HTML.
    """
    salt = None
    cookie_name = None
    for name, value in headers:
        if name.lower() != "set-cookie":
            continue
        cookie_part = value.split(";")[0].strip()
        if "anubis-cookie-test" in cookie_part.lower() and "=" in cookie_part:
            cookie_name, _, cookie_value = cookie_part.partition("=")
            if cookie_value:
                salt = cookie_value
                break
    if not salt:
        return None

    difficulty = None
    m = re.search(r'"difficulty"\s*:\s*(\d+)', html) or re.search(
        r'data-difficulty="(\d+)"', html
    )
    if m:
        difficulty = int(m.group(1))

    challenge_id = None
    for pattern in (
        r'data-challenge-id="([^"]+)"',
        r'"challengeId"\s*:\s*"([^"]+)"',
        r'"id"\s*:\s*"([0-9a-f-]{36})"',
    ):
        m = re.search(pattern, html, re.IGNORECASE)
        if m:
            challenge_id = m.group(1)
            break

    return {
        "salt": salt,
        "difficulty": difficulty,
        "id": challenge_id,
        "base_prefix": "",
        "cookie": (cookie_name, salt),
    }


def is_challenge_page(html: str) -> bool:
    return 'id="anubis_challenge"' in html or ".within.website/x/cmd/anubis" in html


def auth_cookie_from_jar(jar: CookieJar) -> str | None:
    """Return "name=value" for the anubis-auth cookie held in the jar."""
    for cookie in jar:
        if "anubis-auth" in cookie.name and cookie.value:
            return f"{cookie.name}={cookie.value}"
    return None


def _get(opener, url: str, user_agent: str):
    req = Request(url, headers={"User-Agent": user_agent, **BROWSER_HEADERS})
    try:
        return opener.open(req)
    except Exception as exc:  # HTTPError is both an exception and a response
        if hasattr(exc, "read") and hasattr(exc, "headers"):
            return exc
        raise


def solve_anubis(
    url: str,
    difficulty: int | None = None,
    user_agent: str = DEFAULT_USER_AGENT,
    fetch_content: bool = False,
    verbose: bool = False,
) -> str:
    """
    Solve an Anubis challenge for the given URL.

    Returns the auth cookie string "name=value" on success ("" when the URL
    was not protected). With fetch_content, the page body is written to
    stdout as bytes.
    """
    parsed = urlparse(url)
    base_url = f"{parsed.scheme}://{parsed.netloc}"

    jar = CookieJar()
    opener = build_opener(HTTPCookieProcessor(jar))

    # --- Step 1: fetch the target and see whether we are challenged ---
    if verbose:
        print(f"[*] Fetching {url} ...", file=sys.stderr)

    resp = _get(opener, url, user_agent)
    resp_headers = list(resp.headers.items())
    raw = resp.read()
    html = raw.decode("utf-8", errors="replace")

    if not is_challenge_page(html):
        if verbose:
            print("[*] No Anubis challenge — serving content directly.", file=sys.stderr)
        if fetch_content:
            sys.stdout.buffer.write(raw)
        return auth_cookie_from_jar(jar) or ""

    challenge = parse_modern_challenge(html)
    if challenge is None:
        challenge = parse_legacy_challenge(resp_headers, html)
    if challenge is None:
        raise RuntimeError(
            "Anubis challenge page detected but no challenge data found "
            "(neither the anubis_challenge JSON nor an anubis-cookie-test cookie). "
            "The challenge format may have changed again."
        )

    salt = challenge["salt"]
    pow_difficulty = difficulty or challenge["difficulty"] or DEFAULT_DIFFICULTY
    if verbose:
        print(f"[*] Challenge salt: {salt[:32]}{'...' if len(salt) > 32 else ''}", file=sys.stderr)
        print(f"[*] Difficulty: {pow_difficulty}", file=sys.stderr)
        if challenge["id"]:
            print(f"[*] Challenge ID: {challenge['id']}", file=sys.stderr)

    # --- Step 2: solve the proof-of-work ---
    start = time.time()
    nonce, response_hash = mine_nonce(salt, pow_difficulty)
    elapsed_ms = int((time.time() - start) * 1000)
    if verbose:
        print(f"[*] nonce={nonce} hash={response_hash} ({elapsed_ms}ms)", file=sys.stderr)

    # --- Step 3: submit the solution ---
    # The modern client redirects to the full URL; the legacy one to the path.
    redir = url if challenge.get("cookie") is None else (
        parsed.path or "/") + (f"?{parsed.query}" if parsed.query else "")
    params = {
        "response": response_hash,
        "nonce": str(nonce),
        "redir": redir,
        "elapsedTime": str(max(elapsed_ms, 1)),
    }
    if challenge["id"]:
        params["id"] = challenge["id"]

    pass_url = (
        base_url + challenge["base_prefix"] + ANUBIS_API_PREFIX + "pass-challenge"
        + "?" + urlencode(params)
    )
    if verbose:
        print(f"[*] Submitting solution to {pass_url}", file=sys.stderr)

    # The verification cookie is replayed from the jar; legacy needs the test cookie.
    headers = {"User-Agent": user_agent, **BROWSER_HEADERS}
    if challenge.get("cookie"):
        headers["Cookie"] = "%s=%s" % challenge["cookie"]
    try:
        pass_resp = opener.open(Request(pass_url, headers=headers))
    except Exception as exc:
        if not (hasattr(exc, "read") and hasattr(exc, "headers")):
            raise
        pass_resp = exc
    pass_body = cast(Any, pass_resp).read()

    auth_cookie = auth_cookie_from_jar(jar)
    if not auth_cookie:
        status = getattr(pass_resp, "status", getattr(pass_resp, "code", "?"))
        raise RuntimeError(
            f"Anubis did not return an auth cookie (pass-challenge HTTP {status}). "
            "The proof-of-work was rejected — the challenge may have expired; retry."
        )
    if verbose:
        print(f"[+] Auth cookie: {auth_cookie[:80]}...", file=sys.stderr)

    # --- Step 4: fetch the real content ---
    if fetch_content:
        # pass-challenge redirects to `redir`, so the body we already have is
        # usually the page; re-fetch only if it still looks like a challenge.
        body = pass_body
        if is_challenge_page(body.decode("utf-8", errors="replace")):
            if verbose:
                print("[*] Re-fetching target with the auth cookie ...", file=sys.stderr)
            body = _get(opener, url, user_agent).read()
            if is_challenge_page(body.decode("utf-8", errors="replace")):
                raise RuntimeError(
                    "Still served a challenge page after solving — the solution was "
                    "accepted but the auth cookie did not stick."
                )
        sys.stdout.buffer.write(body)

    return auth_cookie


def main():
    parser = argparse.ArgumentParser(
        description="Solve Anubis proof-of-work challenges without a browser."
    )
    parser.add_argument("url", help="The URL protected by Anubis")
    parser.add_argument(
        "--fetch", action="store_true",
        help="Fetch and print the page content after solving"
    )
    parser.add_argument(
        "--difficulty", type=int, default=None,
        help=f"PoW difficulty (leading zero hex chars). Read from the challenge, else {DEFAULT_DIFFICULTY}"
    )
    parser.add_argument(
        "--user-agent", default=DEFAULT_USER_AGENT,
        help="User-Agent header to send"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Print progress to stderr"
    )

    args = parser.parse_args()

    try:
        cookie = solve_anubis(
            url=args.url,
            difficulty=args.difficulty,
            user_agent=args.user_agent,
            fetch_content=args.fetch,
            verbose=args.verbose,
        )
        if cookie and not args.fetch:
            print(cookie)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
