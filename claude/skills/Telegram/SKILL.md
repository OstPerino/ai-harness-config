---
name: Telegram
description: Read, search and (optionally) reply to Telegram chats from Claude Code via the telegram-mcp user-account server. Use when the user asks to check Telegram, read/summarize a chat, find messages, see recent DMs, or draft/send a Telegram reply. Triggers on "телеграм", "тг", "переписка", "чат с", "напиши в тг", "что нового в".
---

# Telegram

Оркестрация доступа к Telegram через MCP-сервер `telegram` (user-аккаунт,
Telethon/MTProto).

## ЖЕЛЕЗНОЕ ПРАВИЛО

**Никогда не вызывай инструменты `telegram` (MCP) напрямую из основной сессии.**
Любая работа с TG идёт через субагента **`telegram-manager`** (Agent tool).

Зачем: сырые ответы MCP — это тысячи токенов (списки диалогов, истории). Субагент
варится в этом изолированно и возвращает в основной контекст только выжимку
(~50 токенов вместо ~3000). Плюс единая точка применения политик безопасности.

## Индекс чатов

`ChatIndex.md` (рядом с этим файлом) — карта «человеческое имя → chat_id / алиасы
/ топики». Когда пользователь говорит «напиши Андрею» — резолвим через индекс,
а не заставляем вспоминать числовой ID. Если чата нет в индексе — субагент ищет
его (`search_contacts` / `list_chats`) и предлагает дописать в индекс.

## Модель безопасности (3 уровня)

| Уровень       | Инструменты (реальные имена MCP)                          | Поведение                          |
|---------------|-----------------------------------------------------------|------------------------------------|
| **read**      | get_messages, list_messages, search_messages, get_history, get_chats, list_chats, get_chat, list_topics, list_contacts, search_contacts, get_drafts, get_me | auto-allow                         |
| **write**     | save_draft, send_message, reply_to_message                | подтверждение; **по умолчанию save_draft** (юзер отправляет сам) |
| **destructive** | delete_message, delete_chat_history, ban_user, leave_chat, и т.п. | **заблокировано** на этом слое     |

> Главный рычаг — серверный `TELEGRAM_EXPOSED_TOOLS=read-only` в .env: в этом
> режиме write/destructive вообще не существуют для клиента. Этот skill-слой —
> вторая линия, на случай если сервер запущен в режиме `all`.

## Workflows

### RecentChats — «что нового / последние чаты»
→ telegram-manager: `list_chats` (последние N диалогов) → вернуть список
  `[имя, последнее сообщение, время, кол-во непрочитанных]`.

### ReadChat — «прочитай / суммируй чат X»
→ резолв X через ChatIndex → telegram-manager: `get_history`/`get_messages`
  (limit по запросу) → вернуть сжатую сводку или дословные сообщения.

### Search — «найди где обсуждали Y»
→ telegram-manager: `search_messages` (или `search_global_messages` если
  сервер в режиме all) → вернуть совпадения с ссылками (`get_message_link`).

### DraftReply — «набросай ответ» (БЕЗОПАСНЫЙ ДЕФОЛТ)
→ резолв адресата → подтвердить текст с пользователем → telegram-manager:
  `save_draft` → черновик появляется в TG, пользователь жмёт «отправить» сам.

### DirectSend — «отправь прямо сейчас» (ТОЛЬКО по явной просьбе)
→ требует серверный режим `all`. Показать пользователю точный текст и адресата,
  получить явное «отправляй» → telegram-manager: `send_message` /
  `reply_to_message`. Если сервер в read-only — сообщить, что отправка отключена.

### PostToTopic — «запости в топик форума»
→ резолв чата+топика через ChatIndex → показать пользователю чат, топик и
  точный текст, получить явное «отправляй», как в DirectSend → telegram-manager:
  `save_draft`/`send_message` с `reply_to` = topic_id.

Расшифровки голосовых нет: скачивать медиа субагенту запрещено. Попросили —
сказать, что голосовое нужно сохранить вручную и дать путь к файлу; STT по
этому пути запускает основная сессия.

## Как звать субагента

Agent tool, subagent_type соответствующий telegram-manager (положи
`agents/telegram-manager.md`). Передавай ему ТОЛЬКО задачу + нужные id/limit,
проси вернуть структурированную выжимку, а не сырой дамп.
