# Ревью партии P2 `install-test-backup-prune`

В фикс-раунд идут только Critical и Important. Повторного ревью нет.

**Предмет:** коммиты `sdd/install-tests..sdd/install-tests-P2` (`d75d383`, `3a61e7e`) на `sdd/install-tests-P2`, бриф `.claude/context/sdd/install-tests/P2-brief.md`, отчёт `.claude/context/sdd/install-tests/P2-report.md`.

## Вердикт

| предмет | вердикт |
|---|---|
| `t_backup` | принято |
| `t_prune` | с правками (Important 1) |
| `t_prune_foreign` | принято, Minor 2 |
| `assert_file_content` | принято |
| безопасность (настоящий `~/.claude`, дерево репозитория, уборка песочниц) | принято |
| README:207 | принято |

## Находки

### [Important] 1. prune в `home/agents` не покрыт: мутант `85d` проходит все 7 сценариев
- Где: `tests/install.test.sh:133-141`, `install.sh:85`
- Сценарий: `sed '85d' install.sh` убирает `prune "$DEST/agents"`. Раннер выдаёт `7/7 passed`, exit 0 (проверено). Единственная висячая ссылка в `t_prune` лежит в `home/skills`, а в `home/agents` её нет ни в одном сценарии. Агенты переименовывают и удаляют чаще всего, поэтому висячие `~/.claude/agents/<old>.md` — основной реальный случай prune. Обязательство спеки «убирает свои висячие ссылки» проверено только наполовину, а гейт зелёный. Исполнитель сделал то, что прописано в брифе (там только `s2`). Дыра в брифе, но тест, который должен охранять prune, на этой поломке не падает.
- Исправление: в `t_prune` после `ln -s …/s2` добавить `mkdir -p "$sb/home/agents"` и `ln -s "$sb/repo/claude/agents/gone.md" "$sb/home/agents/gone.md"`, добавить `assert_not_exists "$sb/home/agents/gone.md"`, итоговая строка — `pruned=2`. Я проверил это на копии раннера во временном каталоге: база `7/7`; `85d` роняет только `prune`; `45d`, `62d`, guard, `41d`, `-eq 9`, `24s` по-прежнему роняют только свой сценарий; `49d` роняет `link` и `backup`, как было.

### [Minor] 2. Цель чужой ссылки не ловит ослабление guard до префикса без `/`
- Где: `tests/install.test.sh:145,148`
- Сценарий: правка `60s|"\$SRC"/\*)|"$SRC"*)|` даёт `7/7 passed` (проверено). С таким guard скрипт удалит висячую ссылку владельца на `<repo>/claude-local/...` или `<repo>/claude.bak/...`. Цель `$sb/elsewhere/foreign` отличается от `$SRC` уже в первом компоненте, поэтому тест ловит только полное снятие guard.
- Исправление: цель `"$sb/repo/claude-other/foreign"` (в `ln -s` и в `assert_link`). Она лежит вне `$SRC/`, но начинается с `$SRC`. Проверено на копии: оба варианта guard-мутанта роняют только `prune-foreign`, остальная матрица не меняется.

### [Minor] 3. Неверный диагноз, если glob не совпал
- Где: `tests/install.test.sh:127`
- Сценарий: если каталога бэкапа нет, `$#` равно 1, а `$1` — сам шаблон. Вывод `FAIL backup: … / 1 matches: …/harness-*` читается как «нашёлся один». Сам ассерт работает верно, путает только сообщение.
- Исправление: при `[ ! -e "$1" ]` печатать `0 matches`.

## Мутации из отчёта

Все 7 мутантов воспроизведены на `3a61e7e` под `sh`. Для каждого проверены `diff`, `bash -n` и exit code отдельно от pipe.
- `45d` → `FAIL backup: exit status 0 / exit status 1`, `6/7`, exit 1.
- `62d` → `FAIL prune: …/s2 absent / … exists`, `6/7`, exit 1.
- guard `*)` → `FAIL prune-foreign: symlink … / not a symlink`, `6/7`, exit 1.
- `49d` → FAIL `link` и `backup`, `5/7`, exit 1. Исключение задокументировано в спеке.
- `41d`, `-eq 9`, `24s` → каждый роняет только свой сценарий, `6/7`, exit 1.

Сообщения FAIL совпадают с отчётом. Каждое покраснение пришло из того ассерта, который заявлен в отчёте.

Дополнительно прогнал свои мутанты:
- `44d` (нет `mkdir -p "$BACKUP"`) → FAIL `backup`;
- `47d` (счётчик) → FAIL `backup` по итоговой строке;
- `mv` заменён на `rm "$dst"` → FAIL `backup` в `assert_file_content`: каталог есть, файла нет. Это ровно та потеря данных, ради которой нужен сценарий;
- `86d` → FAIL `prune`;
- инверсия `! -e` → 5 FAIL;
- `57d` → FAIL `dry-run`;
- `85d` и guard-префикс выживают (находки 1 и 2).

Гейт: `sh`, `dash`, `bash` — `7/7 passed`, exit 0. После всех прогонов `ls $TMPDIR | grep install-test.` пусто. `find ~/.claude/{agents,skills,CLAUDE.md} -maxdepth 1 -newer marker` пусто. `git status --short` в worktree пуст. `rm -r` в `t_prune` бьёт только по `$sb/repo/...`: `sb` проверен в `sandbox()`, `install.sh` копируется в песочницу, поэтому `SRC` указывает в `$sb/repo/claude`, а не в живой `claude/`.

## Вне границы партии

- `install.sh:43`: ветку `|| [ -L "$dst" ]` (бэкап висячей или чужой ссылки на месте `dst`) не охраняет ни один сценарий. Мутант, который её снимает, даёт `7/7 passed`. При такой поломке `ln -s` падает на `File exists`: это отказ установки, данные не теряются.
- `install.sh:22`: `-h|--help` не покрыт (отмечено в отчёте).
- `install.sh:7`: точность `BACKUP` до секунды (уже записано в спеке, кандидат в #007).
