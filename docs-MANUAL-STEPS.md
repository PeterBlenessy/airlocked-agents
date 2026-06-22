# docs-MANUAL-STEPS.md — the irreducible 5 (everything else is `make`)

These cannot be made deterministic because they require interactive consent or out-of-band registration. Do them once, paste results into `.env`, then re-run the relevant `make` target.

## 1. Telegram bot token
- In Telegram, message `@BotFather` → `/newbot` → copy the token.
- Get your numeric chat id: message the bot, then open
  `https://api.telegram.org/bot<token>/getUpdates` and read `message.chat.id`.
- Put both in `.env`: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_CHAT_ID`.

## 2. Gmail OAuth
- Google Cloud Console → create an OAuth 2.0 Client (Desktop/Web) → copy client id + secret
  into `.env` (`GMAIL_OAUTH_CLIENT_ID`, `GMAIL_OAUTH_CLIENT_SECRET`).
- After `make vps`, open the n8n editor, add a Gmail OAuth2 credential, and click
  **Connect** to authorize in the browser. This consent step is inherently manual.

## 3. Supabase for Suna (and local-model routing)
- Create a Supabase project (cloud) or self-host it; copy URL + anon + service keys into `.env`.
- Run Suna's setup wizard once on the VPS: `cd /opt/airlocked-agents/suna && python setup.py`,
  then `docker compose up -d`.
- **Route sensitive research to the Mac:** configure Suna's `openai/local` model
  (`SENSITIVE_RESEARCH_MODEL`) to use `LOCAL_MODEL_BASE_URL` (e.g. `http://10.10.0.2:8080/v1`)
  with api key `LOCAL_MODEL_API_KEY` (= `LLAMA_API_KEY`). This reaches the Mac's local model
  over the WireGuard tunnel via the socat proxy, so private prompts never hit a cloud model.
  Requires `make tunnel` up first; verify with
  `curl -H "Authorization: Bearer $LLAMA_API_KEY" $LOCAL_MODEL_BASE_URL/models` from the VPS.

## 4. WireGuard keys
- Generate on both ends: `wg genkey | tee priv | wg pubkey`.
- Put the four keys (`WG_MAC_PRIVATE_KEY`, `WG_MAC_PUBLIC_KEY`, `WG_VPS_PRIVATE_KEY`,
  `WG_VPS_PUBLIC_KEY`) into `.env`, then `make tunnel`.
- **Then harden SSH (recommended):** with the tunnel up and the Mac connected, run
  `make harden` to lock VPS SSH (22) to the tunnel peer, and set `SSH_HARDENED=true` in `.env`.
  Order matters — the first `make vps` runs over public SSH, so harden only *after* the tunnel
  works. From then on, `make vps`/`make verify` reach the box over `VPS_TUNNEL_IP`.

## 5. Reverse proxy + TLS for n8n (one-time)
- Point `N8N_HOST` DNS at the VPS, and put Caddy/Traefik/nginx in front of `127.0.0.1:5678`
  with a Let's Encrypt cert. This is the only public ingress; the firewall allows only 443.

---

After these five, `make mac && make vps && make tunnel && make workflows && make verify`
converges deterministically every time.
