# ai-harness-config

Харнесс Claude Code: агенты, скиллы и правила лежат в `claude/` и ставятся в `~/.claude` симлинками через `install.sh`. Устройство и правила — `README.md`.

## Код

- Скрипты — POSIX `sh` без зависимостей; `install.sh` — bash (`BASH_SOURCE`). Ничего не ставить через пакетные менеджеры.
- Тесты и проверки не трогают настоящий `~/.claude` и рабочее дерево репозитория: только временные каталоги (`mktemp -d`) и `CLAUDE_HOME`.
- Пояснительных комментариев нет: остаются shebang и директивы `shellcheck`.

## Коммиты

- Формат `type(scope): subject`, скоупы — из `.gitflow` (`agents skills rules install docs issues`), заголовок ≤ 72 символов. Эмодзи ставит хук `.githooks/commit-msg`, руками не писать.
- Трейлер `Co-Authored-By: Claude <модель> <noreply@anthropic.com>` в каждом коммите.

## SDD

Процесс — скилл `sdd`. Здесь только отличия этого проекта.

| слой (пути) | исполнитель | ревьюер |
|---|---|---|
| tests/ (без своей партии) | test-dev | backend-reviewer |
| claude/agents/, claude/skills/, claude/CLAUDE.md | harness-dev | planner |
| install.sh, claude/hooks/, claude/settings.d/, claude/bin/, .github/, tests/ своей партии | devops-dev | backend-reviewer; security-reviewer для защиты (#008) |

- Тип репо: пет
- Гейт: `sh tests/gate.sh`
- Подготовка worktree: нет
- Основная ветка: main
- Ветка фичи: sdd/<фича>
- Ветка фичи в worktree: да
- Трекер: github
- Issue на партию: нет
- PR: ведущий
- Атрибуция: да
- Артефакты SDD: спеку коммитить; `.sdd/` (брифы, отчёты, ревью) — не коммитить: в ревью защиты детали атак, репо публичный
- Утверждение брифов: первый — владелец, остальные — ведущий
- E2E: нет
- Worktree: .worktrees/
- Параллельные партии: да
- В бриф копировать: «Код», «Коммиты»
