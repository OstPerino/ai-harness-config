# Свои скиллы SDD — план реализации

> **Для исполнителя:** задачи выполняются по порядку, шаги отмечаются чекбоксами (`- [ ]`). Скиллы и шаблоны — это markdown-промпты, а не код. Поэтому вместо полного текста каждого файла в задаче дан **обязательный состав**: разделы и правила, которые должны быть в файле дословно или по смыслу. Сам текст пишет исполнитель, по правилам ниже.

**Цель:** процесс SDD владельца становится скиллами харнесса `spec` и `sdd`. superpowers отключается без потери debugging / TDD / verification.

**Архитектура:**
- `spec` ведёт диалог и пишет спеку с таблицей партий.
- `sdd` ведёт партии: бриф от `planner` → исполнитель в worktree → гейт → одно ревью → один фикс → мерж в SDD-ветку → итоговое ревью → `pr.md`.
- Настройки проекта лежат в разделе `## SDD` его `CLAUDE.md`.
- Шаблоны артефактов — в `claude/skills/sdd/references/`.

**Стек:** markdown-скиллы и агенты Claude Code, POSIX `sh` для проверки харнесса, `run_eval.py` из skill-creator для проверки срабатывания.

**Спека:** `docs/specs/2026-10-15-sdd-skills-design.md`. Читать вместе с планом: решения и обоснования — там.

## Глобальные ограничения

- Промпты агентов — на английском, отчёты агентов — на русском (решение 2026-10-15).
- Модели: `opus` — рассуждения, ревью, планы; `sonnet` — код и тесты.
- Ни один скилл процесса не вызывает `general-purpose` для реализации или ревью.
- Скопированные скиллы superpowers: текст без изменений, кроме ссылок `superpowers:<имя>` → `<имя>`.
- Поясняющих комментариев в коде нет (глобальный `CLAUDE.md`). `sh`-скрипты — без комментариев, кроме shebang и директив `shellcheck`.
- Действия наружу (PR, мерж в основную ветку, issue в трекере) — только по команде владельца.
- Коммиты — по git-flow харнесса: скоупы `agents skills rules install docs issues`, трейлер `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Гейт харнесса: `sh tests/lint-harness.sh && bash -n install.sh`.

## На что смотреть ревьюеру

Пять случаев, которые спека подразумевает, но ни одна задача не проверяет напрямую. Для каждого в задаче-владельце есть отдельный пункт.

1. **`/clear` посреди партии.** Статус `work` или `fix`, worktree жив, а ID исполнителя потерян, и SendMessage невозможен. Ожидание: `sdd` запускает нового исполнителя того же типа с брифом и ревью на входе и прямо говорит, что контекст прошлого исполнителя потерян (задача 7).
2. **Рабочий репозиторий, где `CLAUDE.md` в git и его видит команда.** Ожидание: раздел пишется в `CLAUDE.local.md`, файл попадает в `.git/info/exclude`, `CLAUDE.md` не меняется (задача 7).
3. **Спека без таблицы партий или со статусами не из списка.** Ожидание: `sdd` не стартует и отправляет в `spec` (задача 7).
4. **Проект без очевидной команды гейта** (Rust, Python, нет `package.json`). Ожидание: `sdd` предлагает команду по манифестам (`cargo fmt --check && cargo clippy -- -D warnings && cargo test`) и спрашивает, а не оставляет гейт пустым (задача 7).
5. **Пересечение триггеров с `project-architect`** («сделай спеку»). Ожидание: идея нового проекта → `project-architect`, фича в существующем репо → `spec` (задачи 6 и 9).

---

### Задача 1: проверка харнесса `tests/lint-harness.sh`

**Файлы:**
- Создать: `tests/lint-harness.sh`

**Интерфейсы:**
- Производит: команду `sh tests/lint-harness.sh`. Код выхода 0 — всё в порядке, 1 — есть нарушения; каждое нарушение — строка `lint: <файл>: <что не так>` в stderr. Её используют гейт харнесса и все следующие задачи.

- [ ] **Шаг 1: написать скрипт**

```sh
#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE="$ROOT/claude"
errors=0

err() {
  printf 'lint: %s: %s\n' "$1" "$2" >&2
  errors=$((errors + 1))
}

frontmatter() {
  awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 {print}' "$1"
}

field() {
  frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1
}

for skill in "$CLAUDE"/skills/*/; do
  dir=$(basename "$skill")
  file="$skill/SKILL.md"
  if [ ! -f "$file" ]; then
    err "skills/$dir" "missing SKILL.md"
    continue
  fi
  name=$(field "$file" name)
  [ "$name" = "$dir" ] || err "skills/$dir/SKILL.md" "name '$name' does not match directory"
  [ -n "$(field "$file" description)" ] || err "skills/$dir/SKILL.md" "missing description"
done

for agent in "$CLAUDE"/agents/*.md; do
  base=$(basename "$agent" .md)
  name=$(field "$agent" name)
  [ "$name" = "$base" ] || err "agents/$base.md" "name '$name' does not match file name"
  [ -n "$(field "$agent" description)" ] || err "agents/$base.md" "missing description"
  model=$(field "$agent" model)
  case "$model" in
    "" | opus | sonnet | haiku | inherit) ;;
    *) err "agents/$base.md" "model '$model' is not an alias (opus|sonnet|haiku|inherit)" ;;
  esac
done

refs=$(grep -rln --exclude=VENDORED.md 'superpowers:' "$CLAUDE" 2>/dev/null || true)
for f in $refs; do
  err "${f#"$ROOT"/}" "references superpowers: skill namespace"
done

for skill in spec sdd; do
  [ -d "$CLAUDE/skills/$skill" ] || continue
  if grep -rqn 'general-purpose' "$CLAUDE/skills/$skill"; then
    err "skills/$skill" "dispatches general-purpose instead of harness agents"
  fi
done

[ "$errors" -eq 0 ] || { printf 'lint: %s problem(s)\n' "$errors" >&2; exit 1; }
echo "lint: ok"
```

- [ ] **Шаг 2: запустить и увидеть текущие нарушения**

Run: `sh tests/lint-harness.sh`
Ожидание: FAIL. Как минимум одна строка `model 'claude-sonnet-5' is not an alias` — у `frontend-dev`, `node-dev`, `devops-dev`. Это реальное нарушение политики моделей (задача #005).

- [ ] **Шаг 3: исправить модели у трёх агентов**

В `claude/agents/frontend-dev.md`, `node-dev.md`, `devops-dev.md` заменить `model: claude-sonnet-5` на `model: sonnet`. Остальное содержимое не трогать: это #005, и правится оно после завершения сессий, которые сейчас работают с этими агентами.

- [ ] **Шаг 4: проверить, что проверка действительно ловит нарушения**

Временно поменять `name:` в `claude/agents/planner.md` на `planer` и запустить скрипт.
Ожидание: FAIL `agents/planner.md: name 'planer' does not match file name`. Вернуть имя, запустить ещё раз.
Ожидание: `lint: ok`, код выхода 0.

- [ ] **Шаг 5: коммит**

```bash
git add tests/lint-harness.sh claude/agents/frontend-dev.md claude/agents/node-dev.md claude/agents/devops-dev.md
git commit -m "feat(install): add harness lint for skill and agent frontmatter" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Задача 2: копии `systematic-debugging`, `test-driven-development`, `verification-before-completion`

**Файлы:**
- Создать: `claude/skills/systematic-debugging/*` — все 11 файлов из `~/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/systematic-debugging/`
- Создать: `claude/skills/test-driven-development/{SKILL.md,writing-good-tests.md}`
- Создать: `claude/skills/verification-before-completion/SKILL.md`
- Создать: `claude/skills/VENDORED.md`

**Интерфейсы:**
- Производит: скиллы с именами `systematic-debugging`, `test-driven-development`, `verification-before-completion`. На них ссылаются `sdd` (задача 7) и бриф (задача 3).

- [ ] **Шаг 1: скопировать**

```bash
P=~/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1
for s in systematic-debugging test-driven-development verification-before-completion; do
  cp -R "$P/skills/$s" claude/skills/
done
```

- [ ] **Шаг 2: поправить ссылки между скиллами**

```bash
grep -rln 'superpowers:' claude/skills/systematic-debugging claude/skills/test-driven-development claude/skills/verification-before-completion \
  | while IFS= read -r f; do sed -i '' 's/superpowers:writing-skills/skill-creator/g; s/superpowers:\([a-z-]*\)/\1/g' "$f"; done
```

Ожидание: три замены — `systematic-debugging/SKILL.md:177` и `:189`, `test-driven-development/writing-good-tests.md:51`. В последнем `superpowers:writing-skills` становится `skill-creator`, потому что `writing-skills` не переносится.

- [ ] **Шаг 3: записать происхождение**

`claude/skills/VENDORED.md`:

```markdown
# Скопированные скиллы

| Скилл | Источник | Версия | Лицензия | Изменения |
|---|---|---|---|---|
| systematic-debugging | obra/superpowers | 6.4.1 | MIT, © 2025 Jesse Vincent | `superpowers:<x>` → `<x>` |
| test-driven-development | obra/superpowers | 6.4.1 | MIT, © 2025 Jesse Vincent | `superpowers:writing-skills` → `skill-creator` |
| verification-before-completion | obra/superpowers | 6.4.1 | MIT, © 2025 Jesse Vincent | нет |

Обновление: `diff -r ~/.claude/plugins/cache/claude-plugins-official/superpowers/<версия>/skills/<скилл> claude/skills/<скилл>`, перенести изменения, повторить замены ссылок.
```

Скопировать `LICENSE` плагина в `claude/skills/LICENSE-superpowers`.

- [ ] **Шаг 4: проверить**

Run: `sh tests/lint-harness.sh && diff -r --exclude=SKILL.md "$P/skills/verification-before-completion" claude/skills/verification-before-completion; ./install.sh`
Ожидание: `lint: ok`, `diff` пустой, установщик создал 3 новых симлинка.

- [ ] **Шаг 5: коммит**

```bash
git add claude/skills/systematic-debugging claude/skills/test-driven-development claude/skills/verification-before-completion claude/skills/VENDORED.md claude/skills/LICENSE-superpowers
git commit -m "feat(skills): vendor debugging, tdd and verification from superpowers 6.4.1" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Задача 3: шаблоны `claude/skills/sdd/references/`

**Файлы:**
- Создать: `claude/skills/sdd/references/{claude-md-sdd,spec,brief,report,review,final-review,pr}.md`

**Интерфейсы:**
- Производит: семь шаблонов. Плейсхолдеры в них оформлены как `<…>`, необязательные блоки помечены `(если …)`. Шаблоны используют `spec` (задача 6), `sdd` (задача 7) и `planner` (задача 4). Имена файлов фиксированы, скиллы ссылаются на них по этим путям.

- [ ] **Шаг 1: `claude-md-sdd.md` — раздел `## SDD`**

Обязательный состав, каждый ключ — отдельная строка `- <Ключ>: <значение>`. Скилл `sdd` парсит ключи по точному имени:

```markdown
## SDD

Процесс — скилл `sdd`. Здесь только отличия этого проекта.

| слой (пути) | исполнитель | ревьюер |
|---|---|---|
| <пути через запятую> | <агент> | <агент> |

- Тип репо: пет | рабочий
- Гейт: `<команда>`
- Основная ветка: <main|master|…>
- Ветка фичи: sdd/<фича> | <шаблон, напр. feature/<KEY>-<slug>>
- Трекер: github | jira <KEY> | нет
- Issue на партию: да | нет
- PR: ведущий | я
- E2E: `<команда>` | нет
- Worktree: .claude/worktrees/
- Параллельные партии: нет | да
- В бриф копировать: <разделы этого CLAUDE.md>
```

- [ ] **Шаг 2: `spec.md`** — разделы ровно из спеки, раздел «Скилл `spec`» → «Шаблон спеки». Таблица партий с колонками `| id | имя | исполнитель | ревьюер | зависит от | issue | статус |` и строкой-легендой статусов: `todo → brief → work → review → fix → done`.

- [ ] **Шаг 3: `brief.md`** — десять разделов из спеки, раздел «Шаблоны» → `brief.md`, в том же порядке. В «Тестах» — строка: *«На каждый новый тест в отчёте — мутация: какую строку испортить, чтобы он покраснел»*. В «Коммитах» — *«по git-flow, скоупы <…>, без push и PR, эмодзи руками не писать»*. В «Чего делать нельзя» — блок `<правила из CLAUDE.md по списку «В бриф копировать», целиком>`.

- [ ] **Шаг 4: `report.md`** — разделы из спеки. Таблица мутаций: `| тест | испорченная строка (файл:строка) | покраснел (да/нет) | из нужного ассерта |`. Первая строка шаблона: *«Отчёт без чисел не принимается»*.

- [ ] **Шаг 5: `review.md` и `final-review.md`** — по спеке. В `review.md` первая строка: *«В фикс-раунд идут только Critical и Important. Повторного ревью нет»*. В `final-review.md` — раздел «Стыки» с тремя подпунктами: контракт между партиями, дублирование, порядок миграций.

- [ ] **Шаг 6: `pr.md`** — по спеке. Последний блок: `(если Тип репо: пет) 🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

- [ ] **Шаг 7: проверить**

Run: `grep -c '' claude/skills/sdd/references/*.md && grep -L '<' claude/skills/sdd/references/*.md`
Ожидание: 7 файлов; второй `grep` пустой — в каждом шаблоне есть плейсхолдеры.

- [ ] **Шаг 8: коммит**

```bash
git add claude/skills/sdd/references
git commit -m "feat(skills): add sdd artifact templates" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

`sdd/SKILL.md` появится в задаче 7, а `lint-harness.sh` требует `SKILL.md` в каждой папке скилла. Поэтому шаг 8 выполняется **вместе с коммитом задачи 7**, а до тех пор шаблоны лежат незакоммиченными.

---

### Задача 4: `planner` — режимы «партии» и «бриф»

**Файлы:**
- Изменить: `claude/agents/planner.md`

**Интерфейсы:**
- Потребляет: шаблоны `spec.md` и `brief.md` из задачи 3 по путям `~/.claude/skills/sdd/references/…`.
- Производит:
  - бриф с первой строкой `Mode: partitions` или `Mode: brief` выбирает режим;
  - в режиме `partitions` агент возвращает таблицу партий, список премисс, флаг безопасности и самокритику;
  - в режиме `brief` пишет файл по пути из брифа.

- [ ] **Шаг 1: переписать Workflow и Task format**

Обязательный состав (английский, 100–150 строк):
- **Modes:** первая строка брифа `Mode: partitions | brief`. Если её нет — спросить ведущего через финальное сообщение, ничего не писать.
- **Mode `partitions`:**
  - вход — согласованный дизайн;
  - партия — одна сдача исполнителя, после которой дерево зелёное;
  - партии нарезаются тонкими вертикальными срезами;
  - владелец и ревьюер — строго из таблицы `## SDD` проекта. Агента, которого нет в таблице, не назначать, а вынести в открытые вопросы;
  - контракт, который трогают два слоя, — отдельная партия раньше обоих потребителей;
  - премиссы — список утверждений «есть / нет в коде» с адресом `file:line`;
  - флаг безопасности по чеклисту (auth, доступы, загрузки, сырой SQL, секреты, авторизация WS).
- **Mode `brief`:**
  - вход — путь к спеке, id партии, пути прошлых брифов и отчётов;
  - заполнить `brief.md`, проверив **каждую** премиссу грепом сегодня и записав дату;
  - переписать правила из `CLAUDE.md` по ключу «В бриф копировать», целиком, не пересказом;
  - если премисса не подтвердилась — бриф не писать, вернуть ведущему список расхождений.
- Self-critique checklist оставить и дополнить: «каждая партия оставляет дерево зелёным», «у каждой партии есть исполнитель из таблицы».
- Output: на русском; финальное сообщение — путь к файлу, вердикт `Ready / Needs input`, расхождения.

- [ ] **Шаг 2: проверить**

Run: `sh tests/lint-harness.sh && grep -c 'Mode: partitions\|Mode: brief' claude/agents/planner.md`
Ожидание: `lint: ok`, не меньше 2.

- [ ] **Шаг 3: коммит**

```bash
git add claude/agents/planner.md
git commit -m "feat(agents): add partitions and brief modes to planner" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Задача 5: `e2e-dev` — правило остановки

**Файлы:**
- Изменить: `claude/agents/e2e-dev.md`

- [ ] **Шаг 1: добавить раздел `## Stop rule` перед `## Hard rules`**

```markdown
## Stop rule

At most 3 attempts per scenario, counting every run you change something for
(spec rewrite, locator fix, flake fix). After the third failed attempt stop
working on that scenario: don't add waits, don't retry, don't quarantine to make
the suite green. Write a manual check for the owner instead:

- steps, starting from the URL and the account/role to use;
- the expected result of each step;
- where to look when it fails (console, network request, server log);
- what you tried, with the trace path of the last attempt.

Then move on to the next scenario. If the project's `## SDD` says `E2E: нет`,
you should not have been dispatched — say so and stop.
```

- [ ] **Шаг 2: в `## Output` добавить пункт** `- Scenarios stopped by the stop rule, with the manual check for each.`

- [ ] **Шаг 3: проверить и закоммитить**

Run: `sh tests/lint-harness.sh && grep -n '## Stop rule' claude/agents/e2e-dev.md`
Ожидание: `lint: ok`, одна строка.

```bash
git add claude/agents/e2e-dev.md
git commit -m "feat(agents): stop e2e-dev after three attempts per scenario" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Задача 6: скилл `spec`

**Файлы:**
- Создать: `claude/skills/spec/SKILL.md`
- Изменить: `claude/skills/project-architect/SKILL.md` (только `description`)

**Интерфейсы:**
- Потребляет: `planner` с `Mode: partitions` (задача 4), шаблон `~/.claude/skills/sdd/references/spec.md` (задача 3).
- Производит: файл `.claude/context/specs/<фича>.md` с таблицей партий в статусе `todo`. С этим файлом стартует `sdd`.

- [ ] **Шаг 1: написать `SKILL.md`**

Обязательный состав:
- **frontmatter `description`** (английский, до 900 символов):
  - триггеры: «распиши план по #N», «сделай спеку для фичи», «давай сделаем фичу», «plan-feature»;
  - явное «Not for a brand-new project idea (project-architect) and not for one-file fixes (issue-start)»;
  - «Use before sdd».
- **тело** (английский, 120–180 строк) — девять шагов из спеки, раздел «Скилл `spec`», в том же порядке, плюс:
  - **HARD-GATE**: до утверждения спеки владельцем — ни строки кода, ни брифов, ни issue;
  - проверка размера, которая называет путь вслух: `one partition → issue-start` / `feature → spec`;
  - вопросы — по одному за сообщение;
  - `planner` вызывается как `Agent(subagent_type: "planner")` с первой строкой `Mode: partitions`;
  - премиссы перепроверяет ведущий грепом сам, после `planner`;
  - issue в трекере — только после «да» владельца;
  - финальное сообщение — путь к спеке и «утверди, чтобы запустить `sdd`».

- [ ] **Шаг 2: развести триггеры с `project-architect`**

В `claude/skills/project-architect/SKILL.md` убрать из `description` фразу `"сделай спеку"` и дописать в конец: `Not for features inside an existing repository — that is the spec skill.`

- [ ] **Шаг 3: проверить**

Run: `sh tests/lint-harness.sh && ! grep -n 'general-purpose' claude/skills/spec/SKILL.md && ./install.sh | tail -1`
Ожидание: `lint: ok`, `linked=1`.

- [ ] **Шаг 4: коммит**

```bash
git add claude/skills/spec claude/skills/project-architect/SKILL.md
git commit -m "feat(skills): add spec skill and split triggers with project-architect" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Задача 7: скилл `sdd`

**Файлы:**
- Создать: `claude/skills/sdd/SKILL.md`
- Закоммитить: `claude/skills/sdd/references/*` из задачи 3

**Интерфейсы:**
- Потребляет:
  - спека из задачи 6;
  - `planner` с `Mode: brief`;
  - исполнители и ревьюеры из таблицы `## SDD`;
  - шаблоны из задачи 3;
  - `issue-done` (задача 8) — для PR в режиме `PR: ведущий`.
- Производит: статусы в таблице партий; файлы `.claude/context/sdd/<фича>/<партия>-{brief,report,review}.md`, `final-review-<слой>.md`, `pr.md`; ветку фичи с партиями, влитыми через `--no-ff`.

- [ ] **Шаг 1: написать `SKILL.md`**

Обязательный состав (английский, 200–260 строк; если больше — детали вынести в `references/`):
- **frontmatter `description`:** триггеры «запускай SDD», «погнали по спеке», «следующая партия», «продолжай SDD»; «Requires an approved spec from the spec skill».
- **Start / resume:**
  - прочитать `## SDD` из `CLAUDE.md` или `CLAUDE.local.md`;
  - нет раздела → первый запуск (ниже);
  - найти спеку;
  - нет таблицы партий или статус не из `todo|brief|work|review|fix|done` → стоп, отправить в `spec` *(ревью-фокус 3)*.
- **First run in a project:**
  - вопрос «рабочий или пет?» с предложенным ответом по пути;
  - стек и слои — по манифестам;
  - гейт — из scripts / CI / Makefile; нет очевидного → предложить по манифесту (`cargo fmt --check && cargo clippy -- -D warnings && cargo test`, `ruff check && pytest`) и спросить *(ревью-фокус 4)*;
  - таблица на подтверждение;
  - куда писать: личное репо → `CLAUDE.md`; рабочее с локальным `CLAUDE.md` → `CLAUDE.md` + exclude; рабочее с `CLAUDE.md` в git → `CLAUDE.local.md` + exclude, `CLAUDE.md` не трогать *(ревью-фокус 2)*;
  - умолчания по типу — таблица из спеки, ADR-5.
- **Work repo guard:**
  - перед первой партией дописать в `.git/info/exclude` недостающие строки из спеки;
  - перед каждым мержем `git status --porcelain | grep '\.claude/\|CLAUDE\.local\.md'` → не пусто → стоп.
- **Feature branch:** создать от основной ветки по ключу «Ветка фичи», если её ещё нет.
- **Partition loop** — шаги 1–7 из спеки дословно по смыслу, с явными вызовами:
  - бриф: `Agent(subagent_type: "planner")` с `Mode: brief`;
  - исполнитель: `Agent(subagent_type: <исполнитель из таблицы>, isolation: "worktree")` или worktree по пути из `## SDD`; сохранить ID агента в строке партии в спеке, в колонке «статус» как `work (agent <id>)`;
  - ревью: `Agent(subagent_type: <ревьюер>)`;
  - фикс: `SendMessage` тому же ID.

  **Первый бриф фичи** показывается владельцу целиком, остальные — сводкой в одну строку.
- **Lost executor** *(ревью-фокус 1)*: статус `work`/`fix`, а ID нет в текущей сессии → новый агент того же типа; вход — бриф, отчёт (если есть) и ревью (если есть); сказать владельцу, что контекст исполнителя потерян.
- **Feature finish:**
  - итоговое ревью по слоям;
  - `security-reviewer` — только при флаге в спеке или по просьбе;
  - партия `fixes` без ревью;
  - `pr.md`;
  - режимы PR: `ведущий` — открыть по команде, мерж по второй команде после зелёного CI, через `issue-done`; `я` — отдать команду `gh pr create …`;
  - предложить `project-checkpoint`.
- **Stop rules** — шесть из спеки, списком.
- **Rules:**
  - повторного ревью нет;
  - исполнителя не отпускают до конца фикс-раунда;
  - вывод гейта читается целиком, без `head`/`tail`;
  - без команды владельца не открывать PR и не мержить в основную ветку.
- **Related skills:** `systematic-debugging` — красный гейт без очевидной причины; `test-driven-development` — бриф требует тесты до кода; `verification-before-completion` — перед любым «партия готова».

- [ ] **Шаг 2: проверить**

Run: `sh tests/lint-harness.sh && grep -c 'subagent_type' claude/skills/sdd/SKILL.md && ./install.sh | tail -1`
Ожидание: `lint: ok` (проверка `general-purpose` по `sdd` проходит), не меньше 3 упоминаний `subagent_type`, `linked=1`.

- [ ] **Шаг 3: коммит (вместе с шаблонами задачи 3)**

```bash
git add claude/skills/sdd
git commit -m "feat(skills): add sdd skill driving partitions through harness agents" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Задача 8: `issue-start`, `issue-done`, удаление `plan-feature`

**Файлы:**
- Изменить: `claude/skills/issue-start/SKILL.md`
- Изменить: `claude/skills/issue-done/SKILL.md`
- Удалить: `claude/skills/plan-feature/`

- [ ] **Шаг 1: `issue-start`** — шаг 5: «consider `plan-feature` first» → «if the issue needs more than one partition, use `spec` instead of starting here». В description добавить: «For single-partition work; multi-partition features go through spec → sdd».

- [ ] **Шаг 2: `issue-done`** — добавить раздел `## SDD feature branch`:
  - если ветка — ветка фичи из `## SDD`, тело PR берётся из `.claude/context/sdd/<фича>/pr.md`, а `Closes` — по всем issue партий;
  - режим `PR: я` → не пушить и не открывать PR, а вывести готовую команду;
  - мерж — только по отдельной команде владельца.

- [ ] **Шаг 3: удалить `plan-feature` и прогнать установщик**

Run: `git rm -r claude/skills/plan-feature && ./install.sh | tail -1 && sh tests/lint-harness.sh && ! grep -rn 'plan-feature' claude/`
Ожидание: `pruned=1`, `lint: ok`, `grep` пустой.

- [ ] **Шаг 4: коммит**

```bash
git commit -m "refactor(skills): route multi-partition work from issue skills to spec and sdd" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- claude/skills/issue-start claude/skills/issue-done
git commit -m "remove(skills): drop plan-feature, replaced by spec" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Первый коммит берёт только пути issue-скиллов. Удаление, проиндексированное `git rm` на шаге 3, уходит вторым.

---

### Задача 9: проверка срабатывания `spec` и `sdd`

**Файлы:**
- Создать: `tests/evals/spec-triggers.json`, `tests/evals/sdd-triggers.json`
- Создать: `tests/evals/README.md`

- [ ] **Шаг 1: наборы запросов**, по 20 в каждом: 10 `should_trigger: true`, 10 `false`. Обязательные `false` для `spec`:
  - «хочу сделать новое приложение для учёта привычек» (→ project-architect, *ревью-фокус 5*);
  - «бери issue 7, там одна правка» (→ issue-start);
  - «поправь опечатку в README»;
  - «следующая партия» (→ sdd).

  Обязательные `false` для `sdd`: «распиши план по #12», «issue готов, делай PR» (→ issue-done), «сделай чекпоинт», «почему падает тест».

  Формат:

```json
[
  {"query": "распиши план по #12, там синхронизация черновиков", "should_trigger": true},
  {"query": "хочу сделать новое приложение для учёта привычек", "should_trigger": false}
]
```

- [ ] **Шаг 2: прогон**

```bash
SC=~/.claude/plugins/cache/claude-plugins-official/skill-creator/f359d43b4060/skills/skill-creator
R=~/Projects/ai-harness-config
(cd "$SC" && python3 -m scripts.run_eval --eval-set "$R/tests/evals/spec-triggers.json" --skill-path "$R/claude/skills/spec" --model claude-opus-5-5 --runs-per-query 3)
(cd "$SC" && python3 -m scripts.run_eval --eval-set "$R/tests/evals/sdd-triggers.json" --skill-path "$R/claude/skills/sdd" --model claude-opus-5-5 --runs-per-query 3)
```

Цена: 2 × 20 × 3 = 120 вызовов `claude -p`. Ожидание: точность ≥ 18/20 по каждому скиллу, обязательные `false` не срабатывают.

- [ ] **Шаг 3: если ниже порога** — поправить `description` один раз, по провалившимся запросам, и прогнать заново. Если снова ниже — записать результаты в `tests/evals/README.md` и сообщить владельцу, без дальнейших итераций.

- [ ] **Шаг 4: коммит**

```bash
git add tests/evals claude/skills/spec/SKILL.md claude/skills/sdd/SKILL.md
git commit -m "test(skills): add trigger evals for spec and sdd" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Задача 10: отключить superpowers, README, статус #001

**Файлы:**
- Изменить: `README.md`, `issues/001-own-superpowers.md`, `.gitignore`

- [ ] **Шаг 1: отключить плагин**

Run: `claude plugin disable superpowers@claude-plugins-official && jq '.enabledPlugins' ~/.claude/settings.json`
Ожидание: `"superpowers@claude-plugins-official": false`. Действует со следующей сессии; текущая сессия продолжает видеть скиллы плагина.

- [ ] **Шаг 2: README**:
  - в «Цикл задачи» — схема `spec → sdd` (spec → planner(partitions) → sdd: planner(brief) → исполнитель → гейт → ревьюер → фикс → мерж в ветку фичи → итоговое ревью → pr.md);
  - в «Скиллы» — `spec`, `sdd` и три скопированных; `plan-feature` убрать;
  - в «Плагины» — superpowers «отключён, заменён своими скиллами»;
  - бейдж `skills` → фактическое число папок в `claude/skills/`;
  - раздел «Проверка харнесса»: `sh tests/lint-harness.sh`.

- [ ] **Шаг 3: `.gitignore`** — добавить `.claude/`: сухой прогон положит туда артефакты SDD.

- [ ] **Шаг 4: #001** — статус «реализовано, ждёт сухого и боевого прогона»; отметить выполненные критерии.

- [ ] **Шаг 5: проверить и закоммитить**

Run: `sh tests/lint-harness.sh && ls -d claude/skills/*/ | wc -l`
Ожидание: `lint: ok`; число совпадает с бейджем.

```bash
git add README.md .gitignore
git commit -m "docs(docs): describe spec and sdd flow in README" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git add issues/001-own-superpowers.md
git commit -m "docs(issues): mark 001 implemented pending dry run" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Задача 11: сухой прогон на харнессе — **в новой сессии**

Выполняется в новой сессии Claude Code в `~/Projects/ai-harness-config`, где superpowers уже отключён. Только так проверяется процесс без вмешательства плагина. Сессию запускает владелец.

- [ ] **Шаг 1:** «распиши план: тесты для `install.sh` — изолированный `CLAUDE_HOME`, сценарии link / unchanged / backup / prune / dry-run». Ожидание: срабатывает `spec`; партий две, например `harness` (скрипт-раннер) и `install-cases`.
- [ ] **Шаг 2:** «запускай SDD». Ожидание: вопрос «пет или рабочий?» с предложенным «пет», раздел `## SDD` в корневом `CLAUDE.md` репозитория, первый бриф показан целиком.
- [ ] **Шаг 3:** пройти обе партии до `pr.md`. Записывать каждое отклонение от спеки в `issues/001-own-superpowers.md`, раздел «Сухой прогон».
- [ ] **Шаг 4:** поправить скиллы по отклонениям одним заходом. Гейт, коммиты по скоупам. Повторный сухой прогон не делается.

---

### Задача 12: перенос `telegram-from-scratch` и `work-frontend`

**Блокирована**, пока владелец не подтвердит, что сессии в этих проектах закончены.

- [ ] **Шаг 1: telegram-from-scratch (пет).**
  - Из `CLAUDE.md` и `.claude/context/sdd/README.md` собрать раздел `## SDD` по шаблону:
    - таблица слоёв из `CLAUDE.md:84-88`;
    - гейт `pnpm lint && pnpm typecheck && pnpm test && pnpm build && pnpm depcruise`;
    - `Основная ветка: master`, `Трекер: github`, `Issue на партию: да`, `PR: ведущий`;
    - `E2E: pnpm test:e2e` — решение владельца 2026-10-15 пересматривает запрет от 2026-07-28.
  - `sdd/README.md` заменить одной строкой «процесс — скилл `sdd`, настройки — `CLAUDE.md` § SDD».
- [ ] **Шаг 2: work-frontend (рабочий).**
  - Раздел `## SDD`: исполнитель `frontend-dev`, ревьюер `frontend-reviewer`, `Ветка фичи` по шаблону задач Jira (спросить), `Трекер: jira`, `PR: я`, `E2E: нет`.
  - Мерж — в `epic-branch`: «Основная ветка: epic-branch» на время эпика.
  - Проверить `.git/info/exclude`.
- [ ] **Шаг 3:** `git status` в обоих репозиториях. В work-frontend изменений в индексе быть не должно; в telegram — только `CLAUDE.md` и `sdd/README.md`. Коммит в telegram по его git-flow — по команде владельца.
