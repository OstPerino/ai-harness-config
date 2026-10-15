# #001 — Свой superpowers: процесс SDD работает через наших агентов

**Статус:** реализовано в ветке `feat/001-sdd-skills`, ждёт сухого и боевого прогона
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

## Реализация (2026-10-15)

Спека — [`docs/specs/2026-10-15-sdd-skills-design.md`](../docs/specs/2026-10-15-sdd-skills-design.md), план — [`docs/plans/2026-10-15-sdd-skills.md`](../docs/plans/2026-10-15-sdd-skills.md).

Отличие от исходного плана задачи: переносится не superpowers, а SDD-процесс владельца из `sdd/README.md` проектов. Из superpowers взяты только debugging / TDD / verification, без изменения текста.

- [x] Скиллы лежат в репозитории харнесса и ставятся установщиком: `spec`, `sdd` (+ 7 шаблонов), `systematic-debugging`, `test-driven-development`, `verification-before-completion`.
- [x] Ни один скилл процесса не запускает `general-purpose` — проверяет `tests/lint-harness.sh`.
- [x] Таблица «роль → агент» задана в одном месте — раздел `## SDD` проекта.
- [x] Плагин superpowers отключён (`claude plugin disable`, не удалён).
- [ ] Сухой прогон: задача 11 плана, в новой сессии.
- [ ] Перенос telegram-from-scratch и work-frontend: задача 12 плана, после завершения сессий в них.
- [ ] Боевой прогон на фиче пет-проекта.

## Проверка срабатывания

2026-10-15, `claude-opus-5-5`, 3 прогона на фразу, один воркер, superpowers отключён ([как запускать](../tests/evals/README.md)).

| скилл | результат | промахи |
|---|---|---|
| `spec` | 19/20 | «перед тем как писать код, давай обсудим как сделать закреплённые сообщения в этом репо» — 0/3: модель обсуждает в чате, не вызывая скилл |
| `sdd` | 20/20 | — |

Все обязательные «не должен» прошли: идея нового приложения не уходит в `spec`, «следующая партия» — не в `spec`, «распиши план» и «issue готов» — не в `sdd`. Описания не менялись: порог 18/20 выполнен.

## Сухой прогон

Ещё не проводился — задача 11 плана, в новой сессии.
