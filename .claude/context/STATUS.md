# STATUS — ai-harness-config

_Обновлено 2026-10-19, чекпоинт после харнесса v1._

## TL;DR для следующего агента

Харнесс v1 влит в `main` (PR #2) и установлен в `~/.claude`: настройки из `claude/settings.d/` вливаются `install.sh` по манифесту, guard-хуки и deny/ask работают в живых сессиях, проверка типов после правки, CI на GitHub, почищенные агенты, `/learn`. Аналитика — `/harness-stats` (PR #3), база сохранена 2026-10-19. Владелец ушёл работать в рабочий проект на новом харнессе; через несколько дней — `/harness-stats`, сравнить с базой и разобрать ложные блоки хуков.

## Дальше
- [ ] Через 3–5 рабочих сессий: `/harness-stats` → сравнить с `~/.claude/harness-stats/2026-10-19.json`; ложные блоки guard'ов и typecheck — чинить (через worktree, см. «Грабли»).
- [ ] Ручные проверки в живой сессии: `Write ~/.Claude/Settings.json` и `Read ~/.SSH/<файл>` блокируются (регистр в deny проверяет Claude Code, не мы); `claude mcp list` — имя telegram-сервера (`telegram` или `telegram-mcp`, правила покрывают оба); `/learn` на находке «`cmd | tail` теряет код выхода».
- [ ] #002 context7 и #004 GitHub MCP — ведущий сам: секреты в macOS Keychain через `claude/bin/secret <имя>` (скрипта ещё нет), токены владельца.
- [ ] Бэклог: #011 statusline, перенос проектов (T12), #006 Telegram (вход — `_attic/tg-agent-flow.md`), #007d другие LLM, остатки #005 (копии агентов в других репо, запись в память).
- [ ] Владельцу: запрос в поддержку GitHub «Remove sensitive data» — `refs/pull/1/head` и старый коммит STATUS ещё доступны по SHA; потом удалить локальные `backup/main-before-rewrite` и тег `pre-anonymize`.

## Сделано
- [x] v1 (PR #2): P1 слияние settings + хуки, P2 защита (#008), P3 typecheck (#007b, закрыл #003), P4 CI (#007c), P5 аудит агентов (#005), P6 `/learn` (#010), партия fixes по итоговому ревью. Спека — `docs/specs/2026-10-19-harness-v1.md`.
- [x] `/harness-stats` + `cleanupPeriodDays: 365` (PR #3).
- [x] История `main` переписана и force-push: рабочие идентификаторы и домашний путь убраны; шаблоны для проверки — `.git/info/leak-patterns` (вне git, на новой машине создать заново).
- [x] Установка: старые SessionStart и jira убраны из `~/.claude/settings.json`, `./install.sh` → `settings=updated`; бэкап `~/.claude/backups/harness-20261019-143240/`.

## Ключевые решения и почему
- **Всегда bypass, без `/sandbox` и `blockReadsOutsideWorkingDirectories`** — решение владельца: подтверждения раздражают сильнее риска. Не предлагать снова.
- **`Read(.env.*)` закрывает и `.env.example`** — принято владельцем.
- **Публичный репо: детали защиты не публикуем.** В README «Защита» — только что настроено и что делать; списков обходов нет. `.sdd/` в `.gitignore` (ревью защиты содержат атаки); локальные артефакты v1 — `_attic/sdd/`. PR — squash, ветки с «грязной» историей не пушить.
- **`settings.json` не симлинк, а слияние по манифесту** (`~/.claude/.ai-harness-managed.json`): своё снимается, чужое не трогается, равный элемент владельца считается его.
- **Основной checkout всегда на `main`** — `~/.claude` смотрит в его рабочее дерево. Ветки и мержи — только в `.worktrees/` (`## SDD`: «Ветка фичи в worktree: да»), git в чужом дереве — `git -C <путь>`.
- **Ревьюеры без Edit/Write, ревью возвращают текстом**, файл пишет ведущий; planner — ревьюер слоя `claude/` в `Mode: review`.
- **Промпты агентов — английский, отчёты — русский; `opus` — рассуждения и ревью, `sonnet` — код и тесты**, только алиасы.

## Грабли / что не трогать
- **Guard'ы активны и для агентов в этом репо:** в основном checkout заблокированы `git switch/checkout/pull/merge/reset/stash…`, запись в `claude/hooks/`, `claude/settings.d/`, `~/.claude/settings.json`, проектные `.claude/settings*.json`. `git pull` после мержа PR — владелец руками, сразу `./install.sh`. Хуки правятся в `.worktrees/`.
- **`install.sh` только из основного checkout** (из worktree без `CLAUDE_HOME` откажет). Удалил/переименовал хук и сделал `pull` без `install.sh` — висячий хук с `onFailure: block` заблокирует всё.
- **Определения агентов грузятся при старте сессии**: правка агента в этой же сессии не видна (planner не знал `Mode: review` до новой сессии).
- **Push по https зависает на osxkeychain** → `git -c credential.helper= -c credential.helper='!gh auth git-credential' push …`.
- **Перед push:** `git grep -i -E -f "$(git rev-parse --git-common-dir)/info/leak-patterns"` и `git log -p main..HEAD | grep -c -i -E -f …` — пусто; гейт сам ловит домашние пути.
- **Код выхода через пайп теряется** (`cmd | tail`) — `cmd >out 2>&1; rc=$?`. **zsh не разбивает команду из переменной.** Имена каталогов `~/.claude/projects/-Users-…` начинаются с `-`: для `jq` писать `./-Users-…`.
- **Тесты, зависящие от `/tmp`, ломаются на Linux CI** (там песочница внутри `/tmp`) — виртуальные пути вроде `/guards-tmp`.
- **SDD-файлы — не в `.claude/`** (protected path); этот `STATUS.md` — исключение, на него завязан хук `session-status.sh`.
