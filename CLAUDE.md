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
| tests/ | test-dev | backend-reviewer |

- Тип репо: пет
- Гейт: `sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh`
- Подготовка worktree: нет
- Основная ветка: main
- Ветка фичи: sdd/<фича>
- Трекер: github
- Issue на партию: нет
- PR: ведущий
- Атрибуция: да
- Артефакты SDD: коммитить (кроме `.claude/worktrees/`)
- E2E: нет
- Worktree: .claude/worktrees/
- Параллельные партии: нет
- В бриф копировать: «Код», «Коммиты»
