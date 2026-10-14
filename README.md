<div align="center">

# 🧠 ai-harness-config

**Личный харнесс для Claude Code: агенты, скиллы и правила, по которым идёт разработка**

<p>
  <img alt="Claude Code" src="https://img.shields.io/badge/Claude_Code-harness-D97757?style=for-the-badge&logo=anthropic&logoColor=white">
  <img alt="Agents" src="https://img.shields.io/badge/agents-12-5A67D8?style=for-the-badge">
  <img alt="Skills" src="https://img.shields.io/badge/skills-10-38A169?style=for-the-badge">
  <img alt="Install" src="https://img.shields.io/badge/install-symlinks-718096?style=for-the-badge&logo=gnubash&logoColor=white">
</p>

<sub>Качество результата важнее экономии токенов · каждая роль — отдельный агент · всё под git</sub>

</div>

---

## ✨ Зачем

`~/.claude` — обычная папка без истории: правка агента или скилла не оставляет следа, откатить её нельзя. Здесь источник правды — этот репозиторий, а `~/.claude` собирается из него симлинками. Любое изменение поведения агента видно в `git diff` и `git log`.

Принципы, по которым репозиторий собран:

- **Качество, а не экономия токенов.** Модель выбирается по типу работы, а не по цене: рассуждения, планы и ревью идут на Opus, код и тесты на Sonnet. Вывод проверок не обрезается через `head`/`tail`: ошибка на 31-й строке остаётся ошибкой.
- **Одна роль — один агент.** Разработчик не ревьюит свой код, ревьюер ничего не правит, планировщик не пишет код.
- **Агент не привязан к проекту.** Метод работы живёт в агенте, конвенции — в `CLAUDE.md` проекта, задача и сводка стека — в брифе от оркестратора. Новый стек (мобилка, десктоп, Rust) добавляется новым агентом, остальные не меняются.
- **Правило без автоматики нарушается.** То, что можно проверить хуком, проверяется хуком: формат коммитов, например.

## 🗺️ Как устроено

```mermaid
flowchart LR
    subgraph repo["ai-harness-config (git)"]
        A["claude/agents/*.md"]
        S["claude/skills/*/"]
        C["claude/CLAUDE.md"]
    end
    I(["./install.sh"])
    subgraph home["~/.claude"]
        A2["agents/ → symlinks"]
        S2["skills/ → symlinks"]
        C2["CLAUDE.md → symlink"]
    end
    A --> I --> A2
    S --> I --> S2
    C --> I --> C2
```

Правишь файл в репозитории — Claude Code видит изменение сразу, перезапуск не нужен: он следит за `~/.claude/agents/` и `~/.claude/skills/`.

### Цикл задачи

```mermaid
flowchart LR
    IS["issue-start<br/><sub>ветка, правила проекта</sub>"] --> PF["plan-feature<br/><sub>спека</sub>"]
    PF --> PL["planner<br/><sub>план по ролям</sub>"]
    PL --> DEV["frontend-dev · node-dev · devops-dev<br/>test-dev · e2e-dev"]
    DEV --> REV["frontend-reviewer · backend-reviewer<br/>security-reviewer"]
    REV -->|находки| DEV
    REV -->|чисто| ID["issue-done<br/><sub>проверки, коммиты, PR</sub>"]
```

После правок по замечаниям второй круг ревью не запускается: проверки и дифф правок смотрит оркестратор (правило из `claude/CLAUDE.md`). Связку «скилл процесса → агент» доделывает [#001](issues/001-own-superpowers.md).

## 🤖 Агенты

| Агент | Модель | Режим | Что делает |
|---|:---:|:---:|---|
| **Планирование** ||||
| `planner` | Opus | 👁️ | План реализации: задачи на один запуск агента, у каждой владелец, файлы и команда-проверка. Потом сам критикует план по чеклисту |
| **Разработка** ||||
| `frontend-dev` | Sonnet | ✍️ | React / Next.js, Vue / Nuxt |
| `node-dev` | Sonnet | ✍️ | Node.js / TypeScript бэкенд: NestJS, Fastify, Prisma, Postgres, Redis, WebSocket |
| `devops-dev` | Sonnet | ✍️ | Один VPS: docker compose, nginx, certbot, ufw, GitHub Actions. Не деплоит и не генерирует секреты |
| **Качество** ||||
| `test-dev` | Sonnet | ✍️ | Unit- и интеграционные тесты. Каждый новый тест проверяет мутацией: портит строку, которую тест охраняет, и ждёт красного |
| `e2e-dev` | Sonnet | ✍️ | Playwright: сначала проходит сценарий в браузере через MCP, потом пишет спеку; стабильность — `--repeat-each=10` |
| `build-fixer` | Sonnet | ✍️ | Чинит tsc / lint / build / `cargo check` минимальным диффом. Каждый `as any` и `@ts-ignore` — в отчёт с причиной |
| `refactor-cleaner` | Sonnet | ✍️ | Удаляет мёртвый код и зависимости пачками по knip, с полным прогоном проверок после каждой пачки |
| **Ревью** ||||
| `frontend-reviewer` | Opus | 👁️ | Ревью фронта и тестов: «какую строку испортить, чтобы тест покраснел?» |
| `backend-reviewer` | Opus | 👁️ | Ревью бэка: доступ к чужим id, идемпотентность, границы транзакций, миграции, контракт |
| `security-reviewer` | Opus | 👁️ | Уязвимости с конкретным путём атаки; вердикт BLOCK / APPROVE WITH CHANGES / APPROVE |
| **Сервис** ||||
| `telegram-manager` | — | ⚙️ | Исполнитель вызовов Telegram MCP для скилла `Telegram` |

<sub>✍️ пишет код · 👁️ только читает: у `planner` и `security-reviewer` это закреплено списком `tools`, у `frontend-reviewer` и `backend-reviewer` пока только промптом ([#005](issues/005-agent-audit.md)) · ⚙️ служебный</sub>

Промпты новых агентов — на английском (дешевле в токенах на рассуждениях), отчёты агенты пишут на русском. Формат промпта: роль в 1–2 строки → Workflow → чеклисты → Hard rules → Output, 70–130 строк. Список тем, которые модель и так знает («React 19, `oklch()`, V8 hidden classes…»), в промпт не попадает: поведение меняют конкретные правила, а не каталог.

## 🧩 Скиллы

| Скилл | Когда срабатывает |
|---|---|
| **Процесс** ||
| `issue-start` | «бери issue 7»: читает issue как спеку, создаёт ветку, грузит правила проекта |
| `plan-feature` | «распиши план по #N»: спека в `.claude/context/specs/` |
| `issue-done` | «issue готов»: критерии приёмки, зелёные проверки, коммиты по скоупам, PR |
| `git-flow` | коммиты `type(scope): subject` с эмодзи; bootstrap ставит хук в любой репозиторий |
| `project-checkpoint` | «сделай чекпоинт»: `STATUS.md` и хэндофф перед `/clear` |
| **Проектирование** ||
| `project-architect` | «хочу сделать X»: идея → проект-документ |
| `domain-modeling` | словарь предметной области и ADR |
| **Текст и дизайн** ||
| `humanize` | любой текст-объяснение про код: убирает воду, требует адрес, число или поведение |
| `ui-ux-pro-max` | дизайн UI по локальной базе стилей, палитр и шрифтов (сторонний скилл) |
| **Интеграции** ||
| `Telegram` | чтение и поиск по чатам через telegram-mcp ([#006](issues/006-telegram.md)) |

## 🔌 Плагины

Ставятся через `claude plugin install`, в репозитории не лежат:

| Плагин | Зачем |
|---|---|
| `superpowers` | процесс brainstorming → plan → SDD. Будет заменён своими скиллами — [#001](issues/001-own-superpowers.md) |
| `playwright` | агент сам проходит сценарии в браузере |
| `frontend-design` | визуальный дизайн |
| `skill-creator` | создание и проверка скиллов |
| `context7` | актуальная документация библиотек; слетает авторизация — [#002](issues/002-context7-auth.md) |
| `typescript-lsp`, `rust-analyzer-lsp` | нестабильны — [#003](issues/003-lsp-flaky.md) |

## 🚀 Установка

```bash
git clone <repo> ~/Projects/ai-harness-config
cd ~/Projects/ai-harness-config
./install.sh --dry-run   # показать, что изменится
./install.sh
```

`install.sh` для каждого агента, скилла и `CLAUDE.md` создаёт симлинк в `~/.claude`. Если на месте симлинка лежит обычный файл или папка, они уезжают в `~/.claude/backups/harness-<дата>/`, не удаляются. Повторный запуск ничего не меняет. Симлинки на файлы, удалённые из репозитория, установщик убирает.

Не трогает: `settings.json`, память агентов (`~/.claude/agent-memory/`), скиллы claude.ai (`~/.claude/skills/synced/`).

## 📝 Коммиты

Формат — `type(scope): subject`, эмодзи по типу добавляет хук `.githooks/commit-msg`. Это POSIX `sh` без зависимостей, тот же файл скилл `git-flow` ставит в любой репозиторий: JS, Rust, конфиги.

```bash
git config core.hooksPath .githooks       # один раз после клона
git config commit.template .gitmessage
```

```text
feat(agents): add security-reviewer   →   ✨ feat(agents): add security-reviewer
```

| ✨ feat | 🐛 fix | ♻️ refactor | ⚡️ perf | ✅ test | 📝 docs | 🎨 style |
|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| **🔧 chore** | **🚀 ci** | **🚚 move** | **🗑️ remove** | **🚧 wip** | **🎉 init** | |

Скоупы этого репозитория (`.gitflow`): `agents` `skills` `rules` `install` `docs` `issues`. Хук отклоняет неизвестный тип, неизвестный или пустой скоуп и заголовок длиннее 72 символов.

## 📁 Структура

```text
ai-harness-config/
├── claude/                 → ставится в ~/.claude
│   ├── CLAUDE.md           глобальные правила: ревью, комментарии в коде, атрибуция
│   ├── agents/             12 агентов
│   └── skills/             10 скиллов (git-flow/templates — шаблоны хука)
├── issues/                 открытые задачи по харнессу
├── .githooks/commit-msg    проверка формата коммита + эмодзи
├── .gitflow                скоупы коммитов
└── install.sh              симлинки в ~/.claude
```

## 🛣️ Дорожная карта

| # | Задача | Статус |
|---|---|---|
| [001](issues/001-own-superpowers.md) | Свой SDD вместо superpowers: каждая роль процесса вызывает нашего агента | ⏸️ следующая |
| [002](issues/002-context7-auth.md) | context7 по API-ключу вместо OAuth | 🔓 |
| [003](issues/003-lsp-flaky.md) | LSP: починить или заменить хуком typecheck | 🔓 |
| [004](issues/004-github-mcp-global.md) | GitHub MCP на уровне пользователя вместо `gh` | 🔓 |
| [005](issues/005-agent-audit.md) | Перевести `frontend-dev`, `node-dev`, `devops-dev` и ревьюеров в формат новых агентов | 🔓 |
| [006](issues/006-telegram.md) | Довести связку Telegram до рабочего состояния или удалить | ⏸️ |
| [007](issues/007-harness-repo.md) | Хуки и `settings.json` в репозитории, тесты харнесса, задел под другие LLM | 🚧 |

## 🤝 Как добавить агента или скилл

1. Агент — `claude/agents/<name>.md`, скилл — `claude/skills/<name>/SKILL.md`.
2. `./install.sh` — появится симлинк.
3. Коммит со скоупом `agents` или `skills`.

Для агента: модель по типу работы (Opus — рассуждения и ревью, Sonnet — код), `tools` без Edit/Write, если агент только читает, первый шаг — `CLAUDE.md` проекта и бриф.

---

<div align="center">
<sub>Собрано вместе с Claude Code · 2026</sub>
</div>
