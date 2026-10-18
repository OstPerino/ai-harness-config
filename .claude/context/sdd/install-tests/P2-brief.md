# Партия P2 `install-test-backup-prune` — три сценария раннера: backup, prune, prune-foreign

**Issue:** нет. **Worktree:** `/Users/nikitakucenko/Projects/ai-harness-config/.claude/worktrees/install-tests-P2`, ветка `sdd/install-tests-P2` от `sdd/install-tests` @ `9c5cf3b`. Работать только там.
**Спека:** `/Users/nikitakucenko/Projects/ai-harness-config/docs/specs/2026-10-15-install-tests.md` (§ «Зачем», «Граница», «Решения» ADR-1 и ADR-2, «Партии» — блок P2, «Приёмка»). В worktree может лежать более старая копия, поэтому читать по абсолютному пути.
**Опора:** `/Users/nikitakucenko/Projects/ai-harness-config/.claude/context/sdd/install-tests/P1-brief.md`, `/Users/nikitakucenko/Projects/ai-harness-config/.claude/context/sdd/install-tests/P1-report.md` (особенно «Фикс-раунд»), `/Users/nikitakucenko/Projects/ai-harness-config/.claude/context/sdd/install-tests/P1-review.md`.
**Отчёт писать в:** `/Users/nikitakucenko/Projects/ai-harness-config/.claude/context/sdd/install-tests/P2-report.md`.

## Зачем партия существует

Раннер `tests/install.test.sh` из P1 уже проверяет четыре обязательства `install.sh`: link, unchanged, dry-run, bad-arg. Не проверены три самых опасных пути, где скрипт двигает и удаляет файлы владельца:
- бэкап чужого файла (`mv` в `backups/harness-<ts>/`);
- удаление своей висячей ссылки (`rm`);
- guard, который не даёт удалить чужую висячую ссылку.

Если любой из них сломается, гейт останется зелёным, а владелец потеряет файл в `~/.claude`. После партии гейт показывает `7/7 passed`, и каждый новый сценарий доказан своим мутантом, который не роняет остальные шесть.

## Что есть (проверено 2026-10-18 по коду в worktree и пробным прогоном мутантов во временном каталоге)

| что | где (файл:строка) | как использовать |
|---|---|---|
| `link()`: если `dst` существует и это не правильная ссылка, то `run mkdir -p "$BACKUP"`, `run mv "$dst" "$BACKUP/"`, `backed_up+1`, затем `run ln -s` | `install.sh:43-49`, `mv` на `:45` | сценарий backup; мутант `sed '45d'`: `mv` нет, `ln -s` падает с `File exists`, скрипт выходит с кодом 1 (проверено) |
| `BACKUP="$DEST/backups/harness-$(date +%Y%m%d-%H%M%S)"` | `install.sh:7` | ровно один каталог `home/backups/harness-*`, искать по glob |
| `prune()`: только ссылки, `case "$target" in "$SRC"/*)`, висячие удаляются через `run rm "$entry"` | `install.sh:54-69`, guard на `:60`, `rm` на `:62` | prune: мутант `sed '62d'` (счётчик `pruned=1` всё равно печатается, ловит только проверка отсутствия ссылки). prune-foreign: мутант `sed '60s\|"\$SRC"/\*)\|*)\|'`, после него `bash -n` проходит (проверено) |
| prune идёт по `$DEST/agents` и `$DEST/skills` | `install.sh:85-86` | чужую ссылку класть в `home/skills/foreign`, как в спеке |
| ставятся только существующие `skills/*/` | `install.sh:78-81` | после `rm -r repo/claude/skills/s2` скрипт ставит 4 ссылки, `s2` для него нет |
| итоговая строка `done: linked=… unchanged=… backed_up=… pruned=…` | `install.sh:88` | проверять строку целиком через `assert_output_contains`, как в P1 |
| `sandbox()`: `mktemp`, проверки, `trap 'rm -rf "${sb:?}"' EXIT`, фейковое дерево `repo/claude/{agents/a.md,agents/b.md,skills/s1/SKILL.md,skills/s2/SKILL.md,CLAUDE.md}`, пустой `home/` | `tests/install.test.sh:16-32` | переиспользовать как есть, не менять |
| `run_install` пишет вывод в `$sb/out`, код в `status` | `tests/install.test.sh:34-37` | единственный способ запускать скрипт |
| `fail()`: одна строка `FAIL <сценарий>: <ожидали> / <получили>`, `exit 70` | `tests/install.test.sh:39-42` | все проверки, в том числе новые, идут только через `fail`. Голый `[ … ]` под `set -e` даст «setup and commands succeed / exit status 1», то есть неверный диагноз |
| `assert_status`, `assert_link`, `assert_not_exists`, `assert_output_contains` | `tests/install.test.sh:44-63` | основные кирпичи P2 |
| `snapshot` / `assert_tree_unchanged` на `ls -lAR` | `tests/install.test.sh:65-72` | в P2 не нужны (см. «Решение по Minor из ревью P1») |
| образец ручной подготовки состояния через `mkdir -p` и `ln -s` | `tests/install.test.sh:85-91` (`t_unchanged`) | так же готовить prune и prune-foreign |
| цикл `for SCENARIO in link unchanged dry-run bad-arg`, `fn="t_$(… \| tr - _)"`, `set +e; ( set -e; sandbox; "$fn" ); rc=$?; set -e`, код 70 значит ассерт | `tests/install.test.sh:117-130` | дописать три имени в список, механику цикла не трогать |
| README «Проверка харнесса», комментарий у строки раннера перечисляет сценарии | `README.md:207` | дописать бэкап и prune |
| базовый гейт в worktree | `.claude/context/sdd/install-tests/P2-base-gate.log` | `lint: ok`, четыре `ok`, `4/4 passed` |
| скоупы коммитов | `.gitflow:1` → `agents skills rules install docs issues` | см. «Коммиты» |
| хук формата коммитов | `git config core.hooksPath` → `.githooks` | эмодзи ставит хук |

Проверенные цифры: прогон из песочницы по схеме ниже на настоящем `install.sh` дал такие итоговые строки:
- backup: `linked=5 unchanged=0 backed_up=1 pruned=0`;
- prune: `linked=4 unchanged=0 backed_up=0 pruned=1`;
- prune-foreign: `linked=5 unchanged=0 backed_up=0 pruned=0`.

Ни один из четырёх мутантов P1 (`49d`, `41d`, `-eq 9`, `24s`) не меняет эти строки. Мутанты P2 не задевают сценарии друг друга.

## Что сделать

Все правки только в `tests/install.test.sh` и `README.md`.

1. **`t_backup`.** Подготовка: `mkdir -p "$sb/home/agents"`, `printf 'mine\n' >"$sb/home/agents/a.md"`. Содержимое должно отличаться от `repo/claude/agents/a.md` (`a`). Затем `run_install`, проверки:
   - `assert_status 0`;
   - в `home/backups/` ровно один каталог `harness-*`. Через `set -- "$sb"/home/backups/harness-*`, затем `[ "$#" -eq 1 ] && [ -d "$1" ] || fail …`. Если glob не совпал, `$1` — сам шаблон, и `-d` ложно;
   - в нём есть обычный файл `a.md` (`[ -f ] && [ ! -L ]`) с содержимым `mine`. Сначала проверить, что файл существует, и только потом читать содержимое. Всё через `fail`;
   - `assert_output_contains "linked=5 unchanged=0 backed_up=1 pruned=0"`.

   **Проверять** `assert_link "$sb/home/agents/a.md" "$sb/repo/claude/agents/a.md"` — решение ведущего, 2026-10-18. Главный риск backup для пользователя — файл увезли в бэкап, а ссылку не поставили. Цена: мутант `49d` из P1 роняет и `link`, и `backup`; это задокументированное исключение из приёмки «мутант роняет свой сценарий, и только его», в отчёте отметить.

   Если нужен хелпер для «файл с содержимым», можно добавить `assert_file_content <путь> <строка>` рядом с остальными `assert_*`, через `fail`. Имя выбираете вы, в отчёт.

2. **`t_prune`.** Подготовка руками, а не первым прогоном (иначе мутант `49d` уронит и этот сценарий):
   - `mkdir -p "$sb/home/skills"`;
   - `ln -s "$sb/repo/claude/skills/s2" "$sb/home/skills/s2"`;
   - `rm -r "$sb/repo/claude/skills/s2"`.

   Остальные четыре ссылки заранее **не** ставить: с ними мутант `41d` дал бы `backed_up=4`, и prune упал бы вместе с unchanged.

   Затем `run_install`, проверки:
   - `assert_status 0`;
   - `assert_not_exists "$sb/home/skills/s2"`. Эта проверка ловит мутант `62d`, счётчик его не ловит;
   - `assert_output_contains "linked=4 unchanged=0 backed_up=0 pruned=1"`.

   Отступление от спеки («повторный прогон») — в отчёт.

3. **`t_prune_foreign`** (в выводе — `prune-foreign`). Подготовка: `mkdir -p "$sb/home/skills"`, `ln -s "$sb/elsewhere/foreign" "$sb/home/skills/foreign"`. Цель вне `repo/claude` и не существует: ссылка должна быть именно висячей, тогда её защищает только guard `:60`, а не проверка `-e`. Затем `run_install`, проверки:
   - `assert_status 0`;
   - `assert_link "$sb/home/skills/foreign" "$sb/elsewhere/foreign"`;
   - `assert_output_contains "linked=5 unchanged=0 backed_up=0 pruned=0"`.

   Ссылки `a.md` и прочих не проверять, это зона `link`.

4. **Цикл:** `for SCENARIO in link unchanged dry-run bad-arg backup prune prune-foreign`. Больше в цикле ничего не менять.

5. **`README.md:207`:** комментарий у строки раннера дополнить, например `# install.sh в песочнице: ссылки, повторный прогон, --dry-run, неизвестный аргумент, бэкап, prune своих и чужих висячих ссылок`. Выравнивание `#` с соседними строками сохранить.

## Решение по Minor из ревью P1

- **`ls -lAR`, mtime с точностью до минуты, нет inode.** Ни один сценарий P2 не использует `assert_tree_unchanged`: во всех трёх скрипт по замыслу меняет `home`. Поэтому для P2 эта находка не важна, `snapshot` не трогать. Если вам всё-таки понадобится снимок, это вопрос в отчёте, а не правка хелпера.
- **SIGTERM под dash** и **`$m` в README:210** — вне партии, не трогать.

## Что не трогать

- `install.sh` — ни строчки (граница спеки). Найденный баг записать находкой в отчёт.
- `sandbox`, `run_install`, `fail` (код 70), существующие `assert_*`, `snapshot`, механика цикла и итога, сценарии P1 — не менять.
- `CLAUDE.md`, `tests/lint-harness.sh`, `tests/evals/`, `claude/` — вне партии.
- Настоящий `~/.claude` и рабочее дерево репозитория. Мутанты класть только в `mktemp`.

## Тесты

Партия сама состоит из тестов. Порядок: по одному сценарию, и каждый сразу проверяется своим мутантом.

1. `backup`: на настоящем `install.sh` `ok`, на мутанте `45d` `FAIL backup`.
2. `prune`: так же, мутант `62d`.
3. `prune-foreign`: так же, мутант guard.
4. Полная матрица: все 7 мутантов против раннера с 7 сценариями.

На каждый новый тест в отчёте — мутация: какую строку испортить, чтобы он покраснел. Команды для macOS/BSD sed, `m=$(mktemp)`:

| сценарий | мутант | ожидаемый результат |
|---|---|---|
| backup | `sed '45d' install.sh > "$m"` | FAIL только `backup` (из `assert_status`), `6/7 passed`, exit 1 |
| prune | `sed '62d' install.sh > "$m"` | FAIL только `prune` (из `assert_not_exists`), `6/7 passed` |
| prune-foreign | `sed '60s\|"\$SRC"/\*)\|*)\|' install.sh > "$m"` | FAIL только `prune-foreign` (из `assert_link`), `6/7 passed` |
| link | `sed '49d'` | FAIL `link` и `backup` (исключение), `5/7 passed` |
| unchanged | `sed '41d'` | FAIL только `unchanged`, `6/7 passed` |
| dry-run | `sed 's/"\$DRY_RUN" -eq 1/"$DRY_RUN" -eq 9/'` | FAIL только `dry-run`, `6/7 passed` |
| bad-arg | `sed '24s/exit 1/exit 0/'` | FAIL только `bad-arg`, `6/7 passed` |

В таблице выше `\|` — экранирование для markdown. В shell разделитель sed — обычный `|`: `sed '60s|"\$SRC"/\*)|*)|'`.

Перед каждым прогоном мутанта:
- `diff install.sh "$m"` — правка ровно одна и та, что задумана;
- для guard ещё `bash -n "$m"`.

Exit code печатать для **каждого** мутанта отдельно, не через pipe: в P1 он потерялся у трёх мутантов из четырёх. Если мутант роняет больше одного сценария или ни одного, это вопрос в отчёте, а не подгонка теста.

## Чем доказывается результат

- Гейт `sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh` зелёный. Тестов на входе 4 (`4/4 passed`), на выходе `7/7 passed`. Обе цифры — в отчёт.
- `dash tests/install.test.sh` и `bash tests/install.test.sh` → `7/7 passed`, exit 0.
- Семь мутантов из таблицы: каждый роняет свой сценарий и только его, exit 1.
- Песочницы убраны: после всех прогонов, в том числе с FAIL, `ls "${TMPDIR:-/tmp}" | grep install-test.` пусто.
- Настоящий `~/.claude` не тронут: `marker=$(mktemp); sh tests/install.test.sh; dash tests/install.test.sh; find ~/.claude/agents ~/.claude/skills ~/.claude/CLAUDE.md -maxdepth 1 -newer "$marker"` пусто. Вывод — в отчёт.
- `git status --short` перед коммитами показывает только `tests/install.test.sh` и `README.md`, после коммитов пусто.
- Ручная проверка для владельца:
  1. `cd /Users/nikitakucenko/Projects/ai-harness-config/.claude/worktrees/install-tests-P2 && sh tests/install.test.sh` — семь строк `ok …` и `7/7 passed`.
  2. `m=$(mktemp); sed '45d' install.sh > "$m"; INSTALL_SH="$m" sh tests/install.test.sh; echo $?` — `FAIL backup: …`, `6/7 passed`, `1`.

## Чего делать нельзя

- Пояснительных комментариев в коде не оставлять: никаких абзацев «почему так» над функциями, в тестах и конфигах. Зачем тест — в его имени, почему решение — в отчёте. Остаются только shebang, директивы инструментов (`eslint-disable`, `@ts-expect-error`, `shellcheck`) и одно-два слова у нестандартной директивы конфига.
- Существующие тесты под код не подкручивать: упавший тест — вопрос в отчёте.
- Не править `install.sh`, `CLAUDE.md` и хелперы P1 (см. «Что не трогать»).

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
1. `test(install): cover backup and prune in install tests` — `git add tests/install.test.sh`.
2. `docs(install): list backup and prune in harness check` — `git add README.md`.

В каждом — трейлер `Co-Authored-By: Claude <модель> <noreply@anthropic.com>`.

## Отчёт

По шаблону отчёта:
- файлы;
- гейт с числами: до `4/4 passed`, после `7/7 passed`, плюс прогоны под `dash` и `bash`;
- решения:
  - фактический вывод мутанта `49d` на полном раннере (ожидается FAIL `link` и `backup`, `5/7 passed`);
  - почему prune и prune-foreign готовятся руками и только с одной ссылкой;
  - как ищется единственный каталог бэкапа;
  - добавлен ли хелпер для содержимого файла и как он называется;
  - что `assert_tree_unchanged` в P2 не используется;
- мутации: таблица на все 7, с фактическим выводом и exit code каждого;
- проверка `~/.claude` через `-newer` с выводом;
- ручная проверка;
- что не сделано и почему;
- находки в `install.sh`, если тесты их показали.
