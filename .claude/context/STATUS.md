# STATUS — ai-harness-config

## Актуальное состояние — 2026-11-09

Рабочий checkout — отдельный clone `ai-harness-cloud`, ветка
`feat/codex-adapter`. Основной checkout остаётся на main и обслуживает живые
Claude symlinks. Старый `.worktrees/codex-adapter` с этим clone не смешивать.
Режим соло выбран. Изменения подготовлены к публикации в draft PR по явному
поручению владельца; актуальные коммиты и публикацию смотреть в Git/GitHub.

### Реализовано

- Влит origin/main с PR #4; mobile-dev и маршрутизация мобильных задач
  перенесены в общие исходники и оба адаптера.

- Shared core и отдельные адаптеры Claude/Codex, renderer, transactional
  installer с release snapshots и backups. 14 ролей, 17 скиллов, 3 hook definitions.
- Исправлены ложные блокировки read-only диагностики и конфликт installer
  с нативными TOML-таблицами доверия. Изменения собственных настроек всё ещё
  обнаруживаются; чужие таблицы сохраняются вне managed markers.
- Правило полной остановки задачи после блока заменено продолжением независимой
  разрешённой работы и исправлением guard по поручению владельца.
- frontend-design и UI UX Pro Max входят в Codex release с лицензиями,
  upstream SHA и описанием локальных адаптаций. Поиск и сохранение дизайн-системы
  проверены после установки независимо от source checkout.
- Подключены локальные MCP: Jira (63 tools), hours (10), Context7 (2),
  Playwright (25). Credentials и пользовательские configs в git не входят.
  Подробные результаты и ограничения — `docs/codex-integrations.md`.
- Jira: поиск задач и чтение; hours: whoami, проекты, записи текущего дня;
  Context7: документация Vue 3; Playwright: локальная страница, клик, DOM,
  screenshot, console/network. Внешние записи ради smoke не выполнялись.

### Проверки и эксплуатация

- Один независимый проход ревью каждого нового объёма завершён, замечания
  исправлены с регрессионными проверками. Повторный проход не требуется.
- Последняя полная проверка перед публикацией: sh/dash gate, render check,
  CLI smoke с 14 ролями и 17 скиллами. Проверки выполнять в temp home.
- Установка проводится только через `./install.sh --target codex`; release ID
  и исходный checkout хранятся в пользовательском harness manifest.
- Конфигурация Claude сохранена; перенос Codex не меняет её.
- **PreToolUse намеренно выключен владельцем.** Не включать его автоматически.
  Наличие hook tests не означает работающую защиту в текущем диалоге.
- Playwright использует отдельный локальный runtime и isolated Chrome.
  На другой машине Node.js, Chrome, пакет и MCP credentials настраиваются
  отдельно. Полного автоматического переноса интеграций между машинами нет.

### Что осталось

- Telegram отложен по решению владельца.
- Запись Jira/hours, memory/AGENTS рабочих проектов, реальные harness-stats,
  compact/resume и установка на другой машине остаются отдельными проверками.
- CLI battery statusline — отдельная задача, не часть текущей адаптации.

План: `docs/plans/2026-11-06-codex-adapter.md`.
Спека: `docs/specs/2026-11-06-codex-adapter.md`.
Предыдущие согласованные решения: `docs/handoffs/2026-11-06-conversation-summary.md`.
