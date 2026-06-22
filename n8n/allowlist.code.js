// n8n/allowlist.code.js — the canonical source for the write-path guard.
// This exact logic is embedded in the "Allowlist guard" Code node of
// n8n/workflow.write-path.json (so an import is guarded out of the box). Keep the two in
// sync; `make verify` runs scripts/injection-selftest.sh against THIS file and also checks
// the workflow node still contains the guard.
//
// Placed BEFORE any Telegram-command handling and BEFORE any send node, it enforces two
// boundaries: (1) only YOU can command the bot; (2) mail only to allowlisted recipients.
// Values are injected from n8n environment variables (set from .env at deploy time).

const ALLOWED_CHAT_ID = Number($env.TELEGRAM_ALLOWED_CHAT_ID);
const ALLOWED_RECIPIENTS = ($env.MAIL_ALLOWLIST || "")
  .split(",")
  .map((s) => s.trim().toLowerCase())
  .filter(Boolean);

const item = $input.first().json;

// 1) Command authorization: ignore anything not from your own Telegram chat.
const incomingChatId = item.message?.chat?.id ?? item.chatId;
if (incomingChatId !== undefined && incomingChatId !== ALLOWED_CHAT_ID) {
  throw new Error(`Unauthorized chat ${incomingChatId} — ignoring.`);
}

// 2) Send authorization: block any outbound mail to a non-allowlisted recipient.
if (item.action === "send") {
  const recipient = String(item.to || "").toLowerCase();
  if (!ALLOWED_RECIPIENTS.includes(recipient)) {
    throw new Error(`Recipient "${recipient}" not on allowlist — send blocked.`);
  }
}

// Passed both checks — forward unchanged.
return $input.all();
