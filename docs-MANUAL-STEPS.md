# docs-MANUAL-STEPS.md — the irreducible interactive bits

> **Easiest path: run `make setup`.** It walks you through everything below, validates what it can
> (it tests your Telegram bot token and auto-detects your chat id), generates the secrets it can,
> and brings up the whole local stack. This file documents what genuinely still needs you — the
> steps that require interactive consent or out-of-band registration and can't be automated.

Everything runs on the one Mac mini. There is **no VPS, no WireGuard, and no reverse proxy/TLS** —
those are gone. `make setup` collects these; or do them by hand and put results in `.env`.

## 1. Telegram bot (polling — no webhook)
- In Telegram, message `@BotFather` → `/newbot` → copy the token.
- Get your numeric chat id: message the bot, then open
  `https://api.telegram.org/bot<token>/getUpdates` and read `message.chat.id`
  (`make setup` auto-detects this for you).
- Put both in `.env`: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_CHAT_ID`.
- The workflow reaches Telegram by **polling** (a Schedule trigger calling `getUpdates`), so nothing
  listens on the internet.

## 2. n8n owner account
- After `make mac`, open the n8n UI at `http://127.0.0.1:5678` and create the owner account
  (email + password). This is a one-time interactive step n8n requires; it's localhost-only.

## 3. Gmail OAuth
- Google Cloud Console → create an OAuth 2.0 Client → copy client id + secret into `.env`
  (`GMAIL_OAUTH_CLIENT_ID`, `GMAIL_OAUTH_CLIENT_SECRET`).
- In the n8n editor, add a Gmail OAuth2 credential and click **Connect** to authorize in the
  browser. This consent step is inherently manual.

## 4. Wire the Telegram-polling workflow
- Import is automatic (`make setup` / `make workflows`), but n8n's *Telegram Trigger* node is
  webhook-based — so finish the read/write paths using a **Schedule trigger → Telegram `getUpdates`
  (with offset) → allowlist guard → …** pattern, then activate them in the editor.

---

After these, the stack runs entirely on the mini. **Suna** (web research) is deferred — not yet
wired for the single-box model; see `COMPONENTS.md`/`CHANGELOG.md`.
