# Партия fixes `правки по итоговому ревью` — dry-run охраняет бэкап и prune, unchanged ловит пересоздание ссылок, команда мутанта в README запускается

**Issue:** нет. **Worktree:** `/Users/nikitakucenko/Projects/ai-harness-config/.worktrees/install-tests-fixes`, ветка `sdd/install-tests-fixes` от `sdd/install-tests` @ `933fb30`. Работать только там.
**Спека:** `/Users/nikitakucenko/Projects/ai-harness-config/docs/specs/2026-10-15-install-tests.md` (§ «Зачем», «Граница», ADR-1, ADR-2, «Партии», «Приёмка»). Читать по абсолютному пути.
**Опора:**
- `/Users/nikitakucenko/Projects/ai-harness-config/.sdd/install-tests/final-review-tests.md` — вход партии, находки Important 1, Minor 2, Minor 3;
- `/Users/nikitakucenko/Projects/ai-harness-config/.sdd/install-tests/P1-brief.md`, `P1-report.md`, `P1-review.md`;
- `/Users/nikitakucenko/Projects/ai-harness-config/.sdd/install-tests/P2-brief.md`, `P2-report.md` (особенно «Фикс-раунд» с матрицей мутантов), `P2-review.md`.

Артефакты SDD переехали из `.claude/context/sdd/` в `.sdd/` в коммите `933fb30`. Пути `.claude/context/sdd/…` и `.claude/worktrees/…` внутри старых брифов и отчётов — история, по ним не ходить.

**Отчёт писать в:** `/Users/nikitakucenko/Projects/ai-harness-config/.sdd/install-tests/fixes-report.md`.

**Ревью после этой партии нет.** Ведущий сам прогонит гейт и посмотрит дифф. Поэтому матрица мутантов в отчёте — единственное доказательство, полнота обязательна.

## Зачем партия существует

Итоговое ревью нашло три дыры.

1. **Important 1.** `t_dry_run` запускается на пустом `home`. Под `--dry-run` скрипт не доходит ни до бэкапа (`install.sh:44-45`), ни до prune (`install.sh:62`). Мутанты, которые убирают `run` перед `mv`, `rm` или `mkdir -p "$BACKUP"`, дают `7/7 passed`. На живой машине мутант `44s`+`45s` на команде «только показать» увозит агента владельца в бэкап. Обещание спеки «ничего не делает в `--dry-run`» сейчас держится только для создания ссылок.
2. **Minor 2.** `README.md:210`: команда для мутанта использует `$m`, но нигде её не задаёт. При копировании выходит `> ""` и ошибка `cannot create`.
3. **Minor 3.** `snapshot` снимает дерево через `ls -lAR`. Там нет inode, а mtime показан с точностью до минуты. Мутант, который пересоздаёт ссылку в ветке unchanged (`ln -sfn`), даёт `7/7 passed`. Обязательство «не трогает уже поставленное» не проверено.

Партия закрывает все три дыры. Число сценариев не меняется (7), `install.sh` не меняется. Каждый новый или изменённый ассерт доказан своим мутантом. Полная исходная матрица прогоняется заново.

## Что есть (проверено 2026-10-18)

Всё ниже проверено в worktree на `933fb30`. Предложенная правка пробно применена к копии раннера во временном каталоге, на копии прогнана вся матрица из раздела «Тесты». Результаты совпали с ожидаемыми в таблице. Песочниц после прогона не осталось.

| что | где (файл:строка) | как использовать |
|---|---|---|
| `link()`, ветка unchanged: `unchanged+1`, `return` | `install.sh:39-42`, `return` на `:41` | мутант Minor 3: `sed '41s/return/run ln -sfn "$src" "$dst"; return/'` |
| бэкап: `run mkdir -p "$BACKUP"`, `run mv "$dst" "$BACKUP/"` | `install.sh:44`, `:45` | мутанты `44s`, `45s`, `44s`+`45s` |
| prune: `run rm "$entry"` для висячей ссылки внутри `$SRC/` | `install.sh:62` | мутант `62s` |
| `run mkdir -p "$DEST/agents" "$DEST/skills"` | `install.sh:72` | мутант `72s`; `home/skills` в dry-run не создавать, чтобы эта строка осталась под охраной |
| `run()`: в dry-run печатает `  [dry-run] $*`, иначе выполняет | `install.sh:27-33` | исходный мутант dry-run (тело → `"$@"`) и `-eq 9` |
| `snapshot()` на `ls -lAR` | `tests/install.test.sh:71-73`, строка `:72` | заменить на `ls -liAR` (Minor 3) |
| `assert_tree_unchanged` → `snapshot` + `cmp -s` + `fail` | `tests/install.test.sh:75-78` | не трогать, только снимок станет с inode |
| `t_unchanged`: ставит 5 ссылок руками, снимок, прогон, сверка | `tests/install.test.sh:91-104` | не трогать, мутант `ln -sfn` роняет его через `assert_tree_unchanged` |
| `t_dry_run`: снимок пустого `home`, `run_install --dry-run`, три ассерта | `tests/install.test.sh:106-112` | добавить подготовку перед `snapshot`, ассерты оставить |
| образец подготовки бэкапа: `mkdir -p "$sb/home/agents"`, `printf 'mine\n' >…/a.md` | `tests/install.test.sh:122-123` (`t_backup`) | так же готовить файл в dry-run |
| образец висячей своей ссылки `agents/gone.md` | `tests/install.test.sh:137-138` (`t_prune`) | так же готовить ссылку в dry-run |
| `sandbox`, `run_install`, `fail` (код 70), цикл сценариев | `tests/install.test.sh:16-42`, `:155-173` | не трогать |
| строка про мутант в README | `README.md:210` | начать с `m=$(mktemp); ` |
| блок гейта в README | `README.md:204-208` | не трогать |
| базовый гейт worktree | `/Users/nikitakucenko/Projects/ai-harness-config/.sdd/install-tests/fixes-base-gate.log` | `lint: ok`, семь `ok`, `7/7 passed` |
| скоупы коммитов | `.gitflow:1` → `agents skills rules install docs issues` | см. «Коммиты» |
| хук сообщений коммитов | `git config core.hooksPath` → `.githooks` (`commit-msg`) | эмодзи ставит хук |

Проверено на текущем раннере (`933fb30`): `45s`, `62s`, `44s` и `ln -sfn` дают `7/7 passed`, то есть дыра есть. `72s` уже сейчас роняет dry-run (`6/7`): пустой `home` ловит создание `agents`. После правки `72s` должен по-прежнему ронять только dry-run, теперь через созданный `skills`.

## Что сделать

Правки только в `tests/install.test.sh` и `README.md`.

1. **`tests/install.test.sh:72` (Minor 3).** В `snapshot` заменить `ls -lAR "$1" >"$2"` на `ls -liAR "$1" >"$2"`. Больше в `snapshot` и `assert_tree_unchanged` ничего не менять.

2. **`t_dry_run` (Important 1), `tests/install.test.sh:106-112`.** Первыми строками функции, до `snapshot`, вставить ровно эти три:
   ```sh
   mkdir -p "$sb/home/agents"
   printf 'mine\n' >"$sb/home/agents/a.md"
   ln -s "$sb/repo/claude/agents/gone.md" "$sb/home/agents/gone.md"
   ```
   `home/skills` **не** создавать. Ассерты оставить как есть, в том же порядке: `assert_status 0`, `assert_tree_unchanged`, `assert_output_contains "[dry-run]"`. Ассерты на конкретные строки `[dry-run] mv …` и `[dry-run] rm …` **не** добавлять. Иначе мутанты `45d` и `62d` уронят и dry-run, а это нарушит критерий «мутант роняет только свой сценарий».

3. **`README.md:210` (Minor 2).** Внутри обратных кавычек команда должна начинаться с `m=$(mktemp); `. Итоговая строка:
   ```
   Чтобы проверить тест мутантом: `m=$(mktemp); sed '<правка>' install.sh > "$m" && INSTALL_SH="$m" sh tests/install.test.sh`.
   ```
   Остальной текст строки и соседние строки не менять.

## Что не трогать

- `install.sh` — ни строчки (граница спеки и решение ведущего).
- `sandbox`, `run_install`, `fail`, `assert_*`, `assert_tree_unchanged`, цикл и итог раннера, сценарии кроме `t_dry_run`, ассерты `t_dry_run`.
- `CLAUDE.md`, `tests/lint-harness.sh`, `tests/evals/`, `claude/`, `.gitignore`, спека (статус спеки ведёт ведущий).
- Настоящий `~/.claude` и рабочее дерево основного репозитория. Мутанты — только в `mktemp`.
- Находки ревью из раздела «Вне границы фичи» (`install.sh:43`, `.gitignore`, статус спеки, lint раннера) — не делать.

## Тесты

Партия сама состоит из тестов. Порядок такой.

1. **До правок.** На текущем раннере прогнать мутанты `45s`, `62s`, `44s`, `44s`+`45s`, `ln -sfn`. Все должны дать `7/7 passed`: так фиксируется, что дыра есть. В отчёт.
2. Правка 1 (`ls -liAR`). Гейт `7/7`. Мутант `ln -sfn` → FAIL только `unchanged`.
3. Правка 2 (`t_dry_run`). Гейт `7/7`. Новые мутанты dry-run.
4. Правка 3 (README). Скопировать строку из README, подставить `45d` вместо `<правка>` и запустить как есть из корня worktree. Ожидается `FAIL backup`, `6/7 passed`.
5. Полная матрица ниже на итоговом раннере.

Команды для macOS/BSD sed. На каждый мутант: `m=$(mktemp)`, затем `diff install.sh "$m"` (правка ровно та, что задумана), `bash -n "$m"`, прогон `INSTALL_SH="$m" sh tests/install.test.sh`. Exit code печатать **отдельно, не через pipe** (`…; echo "exit $?"`). В P2 из-за `| tail -1` в лог попал код `tail`.

Новые и изменённые ассерты:

| мутант | команда | ожидается (проверено планировщиком на копии) |
|---|---|---|
| `ln -sfn` в unchanged | `sed '41s/return/run ln -sfn "$src" "$dst"; return/' install.sh` | FAIL только `unchanged`, из `assert_tree_unchanged` (в diff меняются inode ссылок), `6/7`, exit 1 |
| `62s` | `sed '62s/run rm/rm/' install.sh` | FAIL только `dry-run`, из `assert_tree_unchanged` (`gone.md` пропал), `6/7`, exit 1 |
| `44s` | `sed '44s/run mkdir/mkdir/' install.sh` | FAIL только `dry-run`, из `assert_tree_unchanged` (появился `backups/harness-*`), `6/7`, exit 1 |
| `45s` | `sed '45s/run mv/mv/' install.sh` | FAIL только `dry-run`, из `assert_status` (`exit status 0 / exit status 1`: `mv` в несуществующий `$BACKUP`), `6/7`, exit 1 |
| `44s`+`45s` | `sed -e '44s/run mkdir/mkdir/' -e '45s/run mv/mv/' install.sh` | FAIL только `dry-run`, из `assert_tree_unchanged` (`a.md` уехал в бэкап), `6/7`, exit 1 |
| `72s` | `sed '72s/run mkdir/mkdir/' install.sh` | FAIL только `dry-run`, из `assert_tree_unchanged` (появился `skills`), `6/7`, exit 1 |

Исходная матрица (повторный прогон на итоговом раннере):

| мутант | команда | ожидается |
|---|---|---|
| `49d` | `sed '49d'` | FAIL `link` и `backup` (исключение из приёмки), `5/7`, exit 1 |
| `41d` | `sed '41d'` | FAIL только `unchanged`, `6/7` |
| тело `run()` → `"$@"` | `perl -0pe 's/run\(\) \{\n.*?\n\}/run() {\n  "\$@"\n}/s' install.sh` | FAIL только `dry-run`, `assert_tree_unchanged`, `6/7` |
| `-eq 9` | `sed 's/"\$DRY_RUN" -eq 1/"$DRY_RUN" -eq 9/'` | FAIL только `dry-run`, `6/7` |
| `24s` | `sed '24s/exit 1/exit 0/'` | FAIL только `bad-arg`, `assert_status`, `6/7` |
| `45d` | `sed '45d'` | FAIL только `backup`, `assert_status`, `6/7` |
| `62d` | `sed '62d'` | FAIL только `prune`, `assert_not_exists`, `6/7` |
| guard `*)` | `sed '60s\|"\$SRC"/\*)\|*)\|'` | FAIL только `prune-foreign`, `assert_link`, `6/7` |
| guard-префикс | `sed '60s\|"\$SRC"/\*)\|"$SRC"*)\|'` | FAIL только `prune-foreign`, `assert_link`, `6/7` |
| `85d` | `sed '85d'` | FAIL только `prune` (`agents/gone.md exists`), `6/7` |
| `86d` | `sed '86d'` | FAIL только `prune` (`skills/s2 exists`), `6/7` |

`\|` в таблице — экранирование для markdown. В shell разделитель sed — обычный `|`: `sed '60s|"\$SRC"/\*)|*)|'`.

Отдельно под `dash`: мутанты `45s` и `ln -sfn` (`INSTALL_SH="$m" dash tests/install.test.sh`) → по одному FAIL своего сценария, `6/7`.

Если какой-то мутант уронит больше или меньше, чем в таблицах, тест не подгонять. Записать это вопросом в отчёт.

## Чем доказывается результат

- Гейт `sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh` зелёный. На входе `7/7 passed` (`fixes-base-gate.log`), на выходе `7/7 passed`. Обе цифры — в отчёт.
- `dash tests/install.test.sh` и `bash tests/install.test.sh` → `7/7 passed`, exit 0 (код печатать без pipe).
- Обе таблицы из «Тесты»: фактический результат и exit code каждого мутанта.
- Песочницы убраны: после всех прогонов, в том числе с FAIL, `ls "${TMPDIR:-/tmp}" | grep install-test.` пусто.
- Настоящий `~/.claude` не тронут: `marker=$(mktemp); sh tests/install.test.sh; dash tests/install.test.sh; find ~/.claude/agents ~/.claude/skills ~/.claude/CLAUDE.md ~/.claude/backups -maxdepth 1 -newer "$marker"` пусто. Вывод — в отчёт.
- `git diff --stat sdd/install-tests` — только `tests/install.test.sh` и `README.md`, `install.sh` не в списке.
- `git status --short` перед коммитами показывает только эти два файла, после коммитов пусто.
- Ручная проверка для владельца:
  1. `cd /Users/nikitakucenko/Projects/ai-harness-config/.worktrees/install-tests-fixes && sh tests/install.test.sh` → семь `ok`, `7/7 passed`.
  2. Скопировать команду из `README.md:210` и подставить `45s/run mv/mv/` вместо `<правка>` → `FAIL dry-run: exit status 0 / exit status 1`, `6/7 passed`.

## Чего делать нельзя

- Пояснительных комментариев в коде не оставлять: никаких абзацев «почему так» над функциями, в тестах и конфигах. Зачем тест — в его имени, почему решение — в отчёте. Остаются только shebang, директивы инструментов (`eslint-disable`, `@ts-expect-error`, `shellcheck`) и одно-два слова у нестандартной директивы конфига.
- Существующие тесты под код не подкручивать: упавший тест — вопрос в отчёте.
- Не править `install.sh` и всё из «Что не трогать».
- Не добавлять в `t_dry_run` ассерты на конкретные строки вывода `[dry-run] mv`/`[dry-run] rm`.

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

Для этой партии — два коммита со скоупом `install`, как в P2:
1. `test(install): guard backup and prune under dry-run, snapshot inodes` — `git add tests/install.test.sh`.
2. `docs(install): make mutant command in README runnable` — `git add README.md`.

В каждом — трейлер `Co-Authored-By: Claude <модель> <noreply@anthropic.com>`.

## Отчёт

По шаблону отчёта:
- файлы и коммиты;
- гейт с числами: до `7/7`, после `7/7`, плюс прогоны под `dash` и `bash`;
- решения:
  - прогон мутантов до правок (шаг 1 «Тестов»): дыра подтверждена;
  - почему в dry-run не создаётся `home/skills` (охрана `install.sh:72`);
  - почему нет ассертов на строки `[dry-run] mv/rm`;
  - что под `ls -liAR` не сломался ни `t_unchanged`, ни `t_dry_run` на настоящем скрипте;
- мутации: обе таблицы из «Тесты», с фактическим выводом (ассерт, на котором упало) и exit code каждого, плюс два прогона под dash;
- проверка `~/.claude` через `-newer` с выводом;
- ручная проверка, в том числе запуск команды, скопированной из README;
- что не сделано и почему;
- находки в `install.sh`, если тесты их показали (только записать, не править).
