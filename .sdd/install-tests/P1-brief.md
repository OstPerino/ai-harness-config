# Партия P1 `install-test-runner` — раннер `tests/install.test.sh` с песочницей, хелперами и четырьмя сценариями (link, unchanged, dry-run, bad-arg)

**Issue:** нет. **Worktree:** `~/Projects/ai-harness-config/.claude/worktrees/install-tests-P1`, ветка `sdd/install-tests-P1` от `sdd/install-tests` @ `dafccc0`. Работать только там.
**Спека:** `~/Projects/ai-harness-config/docs/specs/2026-10-15-install-tests.md` (§ «Зачем», «Что есть», «Граница», «Решения» ADR-1 и ADR-2, «Партии» — блок P1, «Приёмка») — в worktree лежит более старая копия, читать по абсолютному пути.
**Опора:** нет (первая партия).
**Отчёт писать в:** `~/Projects/ai-harness-config/.claude/context/sdd/install-tests/P1-report.md`.

## Зачем партия существует

`install.sh` двигает и удаляет файлы в `~/.claude`, а проверен только руками: гейт харнесса сейчас — `lint-harness.sh` и `bash -n install.sh`, то есть только синтаксис. Партия создаёт раннер, на котором P2 допишет ещё три сценария (backup, prune, prune-foreign), поэтому хелперы и песочница должны быть пригодны для них без переделки. Если песочница протечёт — тест сломает настоящий `~/.claude` владельца или живое дерево `claude/` репозитория; поэтому каждый запуск `install.sh` — только копия скрипта, только `CLAUDE_HOME` во временном каталоге.

## Что есть (проверено грепом 2026-10-15)

| что | где (файл:строка) | как использовать |
|---|---|---|
| bash-скрипт, `set -euo pipefail`, `local` в функциях | `install.sh:1-2`, `:38`, `:55` | запускать только `bash "$sb/repo/install.sh"`, не `sh` и не `dash` — даже когда раннер идёт под dash |
| корень по `BASH_SOURCE` через `cd … && pwd` | `install.sh:4` | копия в `$sb/repo/install.sh` считает корнем `$sb/repo`; корень песочницы нормализовать тем же `cd … && pwd`, иначе `readlink` и ожидаемый путь разойдутся |
| `SRC="$REPO/claude"` | `install.sh:5` | ожидаемые цели ссылок — `$sb/repo/claude/…` |
| `DEST="${CLAUDE_HOME:-$HOME/.claude}"` | `install.sh:6` | каждый запуск — с `CLAUDE_HOME="$sb/home"`; дополнительно `HOME="$sb"`, чтобы без `CLAUDE_HOME` скрипт тоже писал в песочницу |
| `case "${1:-}"`, ветка `*) usage; exit 1 ;;` | `install.sh:20-25`, `:24` | сценарий bad-arg; мутация `sed '24s/exit 1/exit 0/'` |
| `usage` пишет `Usage: ./install.sh [--dry-run]` в stdout | `install.sh:10-18`, `:12` | в bad-arg захватывать `2>&1`, искать `Usage:` |
| `run()`: при `DRY_RUN=1` печатает `  [dry-run] $*` | `install.sh:27-33`, `:28-29` | сценарий dry-run; мутация `sed 's/"\$DRY_RUN" -eq 1/"$DRY_RUN" -eq 9/'` — тело всегда `"$@"` |
| ветка unchanged с ранним `return` | `install.sh:39-42`, `:41` | сценарий unchanged; мутация `sed '41d'` |
| `run ln -s "$src" "$dst"` | `install.sh:49` | сценарий link; мутация `sed '49d'` |
| `run mkdir -p "$DEST/agents" "$DEST/skills"` тоже через `run` | `install.sh:72` | в dry-run `home` остаётся пустым каталогом — снимок «до» и «после» совпадает |
| что ставится: `agents/*.md`, `skills/*/` (без хвостового `/`), `CLAUDE.md` | `install.sh:74-83` | фейковое дерево из ADR-1 даёт ровно 5 ссылок: `agents/a.md`, `agents/b.md`, `skills/s1`, `skills/s2`, `CLAUDE.md` |
| итог `done: linked=… unchanged=… backed_up=… pruned=…` | `install.sh:88` | счётчики проверять по этой строке целиком, например `linked=5 unchanged=0 backed_up=0 pruned=0` |
| образец POSIX-скрипта харнесса: `#!/bin/sh`, `set -eu`, `ROOT="$(cd "$(dirname "$0")/.." && pwd)"`, вывод через `printf` | `tests/lint-harness.sh:1-11` | повторить шапку и стиль; `INSTALL_SH="${INSTALL_SH:-$ROOT/install.sh}"` |
| `tests/install.test.sh` нет, `INSTALL_SH` нигде в коде нет | `ls tests` → `evals lint-harness.sh`; `git grep -n INSTALL_SH` → только спека | создаём с нуля |
| `/bin/dash` есть, `shellcheck` не установлен | `ls -l /bin/dash`; `command -v shellcheck` пусто | прогон под `dash` обязателен; shellcheck не требовать |
| README «Проверка харнесса» — блок ```bash с двумя командами | `README.md:202-207` | добавить третью строку раннера |
| README «Структура», строка `tests/` | `README.md:184` | дописать `install.test.sh` |
| скоупы коммитов | `.gitflow:1` → `agents skills rules install docs issues` | см. «Коммиты» |
| хук формата коммитов подключён | `git config core.hooksPath` → `.githooks` | эмодзи ставит хук |

## Что сделать

1. Создать `tests/install.test.sh` (`#!/bin/sh`, исполняемый `chmod +x`), шапка — как `tests/lint-harness.sh:1-4`: `ROOT`, затем `INSTALL_SH="${INSTALL_SH:-$ROOT/install.sh}"`. Если `INSTALL_SH` не читается файлом — сообщение в stderr и exit 2.
2. Песочница (ADR-1). Функция, которая внутри текущей подоболочки:
   - создаёт `sb` через `mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX"` и нормализует `sb=$(cd "$sb" && pwd)`;
   - ставит `trap 'rm -rf "${sb:?}"' EXIT` (защита от пустой переменной обязательна);
   - кладёт `cp "$INSTALL_SH" "$sb/repo/install.sh"`, фейковое дерево `repo/claude/agents/a.md`, `repo/claude/agents/b.md`, `repo/claude/skills/s1/SKILL.md`, `repo/claude/skills/s2/SKILL.md`, `repo/claude/CLAUDE.md` (по одной строке содержимого) и пустой `home/`.
   Запуск скрипта — одна функция-обёртка: `CLAUDE_HOME="$sb/home" HOME="$sb" bash "$sb/repo/install.sh" "$@" >"$sb/out" 2>&1`, код возврата сохранить в переменную (без падения раннера), вывод — в `$sb/out` для `assert_output_contains`.
3. Хелперы (их же будет использовать P2, имена из спеки не менять). Каждый при провале печатает одну строку `FAIL <имя сценария>: <что ожидали> / <что получили>` и делает `exit 1` из подоболочки сценария:
   - `assert_link <путь> <ожидаемая цель>` — `[ -L ]` и `readlink` совпадает строкой;
   - `assert_not_exists <путь>` — ни `-e`, ни `-L`;
   - `assert_output_contains <подстрока>` — по `$sb/out` (`grep -F`), в FAIL показать фактический вывод или его хвост;
   - `assert_tree_unchanged <каталог> <файл-снимок>` плюс функция снимка `snapshot <каталог> <файл>`: `ls -lAR` по каталогу (решение из открытого вопроса спеки; если поймаете ложное срабатывание — перейти на `find … -exec stat` и описать в отчёте);
   - для кода возврата — `assert_status <ожидаемый>` или эквивалент; имя — на ваше решение, в отчёт.
4. Цикл сценариев. Каждый сценарий — функция `t_<имя>`, запускается в своей подоболочке `( sandbox; t_<имя> )` под `if`, имя сценария лежит в переменной, которую видят хелперы. Родитель считает `passed`/`total`, печатает `ok <имя>` на успех; в конце `<passed>/<total> passed`, exit 1 если `passed != total`. Учтите: внутри `if ( … )` `set -e` не действует — провал фиксируют только хелперы явным `exit 1`.
5. Сценарии (имена в выводе — ровно `link`, `unchanged`, `dry-run`, `bad-arg`):
   - **link**: пустой `home`, один прогон → exit 0; `assert_link` на все 5 путей с целями `$sb/repo/claude/agents/a.md`, `…/agents/b.md`, `…/skills/s1`, `…/skills/s2`, `…/CLAUDE.md`; в выводе `linked=5 unchanged=0 backed_up=0 pruned=0`.
   - **unchanged**: состояние «уже поставлено» подготовить **руками** (`mkdir -p home/agents home/skills` и пять `ln -s` на те же цели), снять снимок `home`, один прогон → exit 0; в выводе `linked=0 unchanged=5 backed_up=0 pruned=0`; `assert_tree_unchanged home`; `assert_not_exists home/backups`. Почему руками, а не первым прогоном скрипта: иначе мутация `49d` (link) роняет и этот сценарий, а приёмка требует «мутация роняет свой сценарий, и только его». Это отступление от формулировки спеки «второй прогон» — описать в отчёте.
   - **dry-run**: снимок пустого `home`, прогон с `--dry-run` → exit 0; `assert_tree_unchanged home`; в выводе `[dry-run]`.
   - **bad-arg**: прогон с `--nope` → код 1; в выводе `Usage:`; `home` пуст (снимок или `assert_not_exists home/agents`).
6. `README.md`:
   - «Проверка харнесса» (`README.md:204-207`): третьей строкой в блок `sh tests/install.test.sh   # install.sh в песочнице: ссылки, повторный прогон, --dry-run, неизвестный аргумент` и одной фразой под блоком — как проверить тест мутантом: `sed '<правка>' install.sh > "$m" && INSTALL_SH="$m" sh tests/install.test.sh`.
   - «Структура» (`README.md:184`): `lint-harness.sh, install.test.sh, evals срабатывания скиллов`, выравнивание колонки сохранить.

## Что не трогать

- `install.sh` — ни строчки (граница спеки). Найденный тестом баг — находка в отчёте, не правка.
- `CLAUDE.md` в корне — ключ `Гейт:` обновит ведущий при мерже партии на новый гейт `sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh`. Исполнитель его не меняет.
- `tests/lint-harness.sh`, `tests/evals/`, `claude/` — вне партии.
- Сценарии backup, prune, prune-foreign — это P2; не писать их и не держать заглушки.
- Настоящий `~/.claude` и рабочее дерево репозитория: мутанты класть только в `mktemp`, не рядом с `install.sh`.

## Тесты

Партия сама — тесты. Порядок:

1. Сначала каркас: песочница, обёртка запуска, хелперы, цикл, итог — и один сценарий `link`. Убедиться, что на настоящем `install.sh` он `ok`, а на мутанте `49d` — `FAIL link: …` и exit 1.
2. Затем по одному `unchanged`, `dry-run`, `bad-arg`, каждый сразу проверять своим мутантом.
3. Проверить сам раннер на провал: при любом FAIL итог `3/4 passed` (или меньше) и exit 1; песочницы после прогона (и после FAIL) удалены — `ls "${TMPDIR:-/tmp}" | grep install-test.` пусто.

На каждый новый тест в отчёте — мутация: какую строку испортить, чтобы он покраснел. Таблица мутаций (команды для macOS/BSD sed, `m=$(mktemp)`):

| сценарий | мутант | ожидаемый результат |
|---|---|---|
| link | `sed '49d' install.sh > "$m"` | FAIL только `link`, `3/4 passed`, exit 1 |
| unchanged | `sed '41d' install.sh > "$m"` | FAIL только `unchanged` |
| dry-run | `sed 's/"\$DRY_RUN" -eq 1/"$DRY_RUN" -eq 9/' install.sh > "$m"` | FAIL только `dry-run` |
| bad-arg | `sed '24s/exit 1/exit 0/' install.sh > "$m"` | FAIL только `bad-arg` |

Перед каждым прогоном мутанта `diff install.sh "$m"` — убедиться, что правка ровно одна и та, что задумана. В отчёт — фактический вывод каждого прогона (строки `ok`/`FAIL` и итог). Если мутант роняет больше одного сценария — это вопрос в отчёте, не подгонка теста.

## Чем доказывается результат

- Гейт: `sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh` — зелёный, `4/4 passed`. В отчёт числа до и после (тестов на входе: 0; базовый гейт `sh tests/lint-harness.sh && bash -n install.sh` → `lint: ok`).
- `dash tests/install.test.sh` → `4/4 passed`, exit 0.
- `bash tests/install.test.sh` → `4/4 passed` (раннер не опирается на bash, но и не ломается под ним).
- Четыре мутанта из таблицы — каждый роняет свой сценарий и только его.
- Настоящий `~/.claude` не тронут: `marker=$(mktemp); sh tests/install.test.sh; dash tests/install.test.sh; find ~/.claude/agents ~/.claude/skills -maxdepth 1 -newer "$marker"` — пусто; вывод — в отчёт.
- Рабочее дерево чистое, кроме двух файлов партии: `git status --short` → только `tests/install.test.sh` и `README.md` до коммита, пусто после.
- Ручная проверка для владельца: `cd <worktree> && sh tests/install.test.sh` — видны 4 строки `ok …` и `4/4 passed`; затем `m=$(mktemp); sed '49d' install.sh > "$m"; INSTALL_SH="$m" sh tests/install.test.sh; echo $?` — `FAIL link: …`, `3/4 passed`, `1`.

## Чего делать нельзя

- Пояснительных комментариев в коде не оставлять: никаких абзацев «почему так» над функциями, в тестах и конфигах. Зачем тест — в его имени, почему решение — в отчёте. Остаются только shebang, директивы инструментов (`eslint-disable`, `@ts-expect-error`, `shellcheck`) и одно-два слова у нестандартной директивы конфига.
- Существующие тесты под код не подкручивать: упавший тест — вопрос в отчёте.
- Не править `install.sh` и `CLAUDE.md` (см. «Что не трогать»).

Из `CLAUDE.md` проекта, дословно:

## Код

- Скрипты — POSIX `sh` без зависимостей; `install.sh` — bash (`BASH_SOURCE`). Ничего не ставить через пакетные менеджеры.
- Тесты и проверки не трогают настоящий `~/.claude` и рабочее дерево репозитория: только временные каталоги (`mktemp -d`) и `CLAUDE_HOME`.
- Пояснительных комментариев нет: остаются shebang и директивы `shellcheck`.

## Коммиты

- Формат `type(scope): subject`, скоупы — из `.gitflow` (`agents skills rules install docs issues`), заголовок ≤ 72 символов. Эмодзи ставит хук `.githooks/commit-msg`, руками не писать.
- Трейлер `Co-Authored-By: Claude <модель> <noreply@anthropic.com>` в каждом коммите.

## Коммиты

По git-flow, скоупы `agents skills rules install docs issues`, раздельно по скоупу. Без push и PR. Эмодзи руками не писать — его ставит хук. Не `git add -A`.

Для этой партии — два коммита, оба со скоупом `install`:
1. `test(install): add sandboxed runner for install.sh` — `git add tests/install.test.sh`.
2. `docs(install): add install tests to harness check` — `git add README.md`.

В каждом — трейлер `Co-Authored-By: Claude <модель> <noreply@anthropic.com>`.

## Отчёт

По шаблону отчёта: файлы; гейт с числами (до: `lint: ok`, 0 тестов; после: `4/4 passed`, плюс прогон под `dash`); решения — способ снимка в `assert_tree_unchanged` и почему он стабилен, подготовка состояния в `unchanged` руками вместо первого прогона, переопределение `HOME` в обёртке, имя и форма хелпера кода возврата, как раннер ведёт себя при отсутствующем `INSTALL_SH`; мутация на каждый тест — таблица с фактическим выводом; проверка `~/.claude` через `-newer` с выводом; ручная проверка; что не сделано и почему; находки в `install.sh`, если тесты их показали.
