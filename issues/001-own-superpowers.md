# #001 — Свой superpowers: процесс SDD работает через наших агентов

**Статус:** отложено (сначала агенты)
**Создано:** 2026-10-12

## Проблема

Плагин superpowers (v6.4.1) задаёт процесс: brainstorming → writing-plans → subagent-driven-development → review → finishing. Когда процессу нужен исполнитель, он запускает безымянный `general-purpose` сабагент, а не наших агентов (`frontend-dev`, `node-dev`, `devops-dev`, `frontend-reviewer`, `backend-reviewer`). Например, `requesting-code-review/SKILL.md:34`: «Dispatch a `general-purpose` subagent».

Итог: в ревью не попадает память ревьюеров (`agent-memory/frontend-reviewer` — 8 накопленных уроков), реализатор не знает правил стека, модель выбирается неявно. Правило «работаем по нашему SDD» приходится каждый раз проговаривать руками, и модель его периодически игнорирует.

## Решение (вариант A)

Забираем нужные скиллы superpowers в репозиторий харнесса и переписываем: каждая роль в процессе явно указывает на нашего агента. После этого плагин superpowers отключаем.

## Объём

Скиллы плагина и что с ними делаем:

| Скилл | Решение |
|---|---|
| brainstorming | берём, сокращаем под наш процесс (issue → spec) |
| writing-plans | берём, план ссылается на роли агентов |
| subagent-driven-development | берём, **ядро**: роль → агент |
| executing-plans | решаем при переносе: нужен ли инлайн-режим |
| requesting-code-review / receiving-code-review | берём, ревьюер = `*-reviewer`, повторное ревью не делаем (глобальный CLAUDE.md) |
| test-driven-development | берём |
| verification-before-completion | берём, сливаем с verification-loop из ECC (без обрезки вывода `head`/`tail`) |
| systematic-debugging | берём как есть |
| dispatching-parallel-agents | берём, `general-purpose` → наши агенты |
| finishing-a-development-branch | сверить с `issue-done`, не дублировать |
| using-git-worktrees | берём как есть |
| writing-skills | не нужен, есть skill-creator |
| using-superpowers, diagnosing-superpowers | заменяем своим входным скиллом / не нужен |

Стыковка с текущими скиллами: `issue-start` → `plan-feature` → (SDD) → `issue-done`. Процесс должен быть один, без двух параллельных цепочек.

## Что берём из everything-claude-code

- HANDOFF-документ между агентами (Context / Findings / Files / Open Questions / Recommendations) и вердикт SHIP / NEEDS WORK / BLOCKED (`commands/orchestrate.md`).
- Поэтапная проверка build → types → lint → tests → secrets grep → diff review с отчётом READY / NOT READY (`skills/verification-loop`), но с полным выводом.

## Задел под другие LLM

Superpowers сам поставляется с `AGENTS.md`, `GEMINI.md`, `gemini-extension.json`. Посмотреть, как они раскладывают один набор скиллов на несколько инструментов, и взять схему для нашего репозитория.

## Критерии готовности

- [ ] Скиллы лежат в репозитории харнесса и ставятся установщиком в `~/.claude/skills/`.
- [ ] Ни один скилл процесса не запускает `general-purpose` для реализации или ревью: только агентов из таблицы ролей.
- [ ] Таблица «роль → агент» задана в одном месте; проекты переопределяют её в своём `CLAUDE.md` (как сейчас в telegram-from-scratch).
- [ ] Плагин superpowers отключён, полный цикл issue → spec → SDD → ревью → PR прогнан на реальной задаче.
