# Отчёт партии fixes `правки по итоговому ревью`

## Файлы

| файл | что изменилось |
|---|---|
| tests/install.test.sh | `snapshot`: `ls -lAR` → `ls -liAR` (строка 72); `t_dry_run`: три строки подготовки перед `snapshot` (свой `agents/a.md`, висячая своя `agents/gone.md`) |
| README.md | строка 210: команда мутанта начинается с `m=$(mktemp); ` |

Коммиты (ветка `sdd/install-tests-fixes`, от `933fb30`):
- `7947afd` test(install): guard backup and prune under dry-run, snapshot inodes
- `4b1590a` docs(install): make mutant command in README runnable

`install.sh` не менялся. `git diff --stat sdd/install-tests`: только `README.md` (1 строка) и `tests/install.test.sh` (+4/-1). `git status --short` после коммитов пуст.

## Гейт

`sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh` — зелёный, exit 0. Тестов: 7/7 (вход, `fixes-base-gate.log`) → 7/7 (выход). `dash tests/install.test.sh` → `7/7 passed`, exit 0. `bash tests/install.test.sh` → `7/7 passed`, exit 0. Exit-коды сняты без pipe, через файл.

## Решения

- Дыра подтверждена до правок: на раннере `933fb30` мутанты `45s`, `62s`, `44s`, `44s`+`45s`, `ln -sfn` дали `7/7 passed`, exit 0.
- `home/skills` в `t_dry_run` не создаётся: иначе `mkdir -p "$DEST/skills"` на `install.sh:72` в мутанте `72s` не изменил бы дерево. Сейчас `72s` ловится через появившийся `skills`.
- Ассертов на строки `[dry-run] mv` и `[dry-run] rm` нет: иначе `45d` и `62d` роняли бы ещё и dry-run, а мутант должен ронять только свой сценарий. Охрана идёт через `assert_tree_unchanged` и `assert_status`.
- `ls -liAR` не сломал ни `t_unchanged`, ни `t_dry_run` на настоящем `install.sh`: гейт `7/7`, оба `ok`. Inode стабилен между снимками, пока ссылка не пересоздана.
- Комментарии в коде не добавлялись.

## Мутации

Все мутанты в `mktemp`, перед прогоном `diff` и `bash -n` (правка ровно та, синтаксис ок). Результат совпал с ожидаемым в обеих таблицах.

Новые и изменённые ассерты:

| тест | испорченная строка | покраснел | из нужного ассерта |
|---|---|---|---|
| unchanged | install.sh:41 `return` → `run ln -sfn "$src" "$dst"; return` | да, FAIL только `unchanged`, 6/7, exit 1 | да, `assert_tree_unchanged` (inode ссылок в diff) |
| dry-run | install.sh:62 `run rm` → `rm` | да, FAIL только `dry-run`, 6/7, exit 1 | да, `assert_tree_unchanged` (`gone.md` пропал) |
| dry-run | install.sh:44 `run mkdir` → `mkdir` | да, FAIL только `dry-run`, 6/7, exit 1 | да, `assert_tree_unchanged` (появился `backups/harness-*`) |
| dry-run | install.sh:45 `run mv` → `mv` | да, FAIL только `dry-run: exit status 0 / exit status 1`, 6/7, exit 1 | да, `assert_status` (`mv` в несуществующий `$BACKUP`) |
| dry-run | install.sh:44+45 без `run` | да, FAIL только `dry-run`, 6/7, exit 1 | да, `assert_tree_unchanged` (`a.md` уехал в бэкап) |
| dry-run | install.sh:72 `run mkdir` → `mkdir` | да, FAIL только `dry-run`, 6/7, exit 1 | да, `assert_tree_unchanged` (появился `skills`) |
| dry-run (dash) | install.sh:45 без `run` | да, один FAIL `dry-run`, 6/7, exit 1 | да, `assert_status` |
| unchanged (dash) | install.sh:41 `ln -sfn` | да, один FAIL `unchanged`, 6/7, exit 1 | да, `assert_tree_unchanged` |

Исходная матрица на итоговом раннере:

| мутант | результат | exit |
|---|---|---|
| `49d` | FAIL `link` и `backup` (`symlink … not a symlink`), 5/7 | 1 |
| `41d` | FAIL только `unchanged` (вывод `linked=0 unchanged=5…`), 6/7 | 1 |
| тело `run()` → `"$@"` | FAIL только `dry-run`, `assert_tree_unchanged`, 6/7 | 1 |
| `-eq 9` | FAIL только `dry-run`, `assert_tree_unchanged`, 6/7 | 1 |
| `24s` | FAIL только `bad-arg` (`exit status 1 / exit status 0`), 6/7 | 1 |
| `45d` | FAIL только `backup` (`exit status 0 / exit status 1`), 6/7 | 1 |
| `62d` | FAIL только `prune` (`skills/s2 absent / exists`), 6/7 | 1 |
| guard `*)` | FAIL только `prune-foreign` (`symlink … not a symlink`), 6/7 | 1 |
| guard-префикс | FAIL только `prune-foreign`, 6/7 | 1 |
| `85d` | FAIL только `prune` (`agents/gone.md absent / exists`), 6/7 | 1 |
| `86d` | FAIL только `prune` (`skills/s2 absent / exists`), 6/7 | 1 |

Для `49d`, `41d`, `62d` падает сценарий из таблицы; других сценариев в выводе нет.

## Проверка ~/.claude

`marker=$(mktemp); sh tests/install.test.sh; dash tests/install.test.sh; find ~/.claude/agents ~/.claude/skills ~/.claude/CLAUDE.md ~/.claude/backups -maxdepth 1 -newer "$marker"` — вывод пустой. `ls "${TMPDIR:-/tmp}" | grep install-test.` после всех прогонов (в том числе с FAIL) — пусто.

## Ручная проверка для владельца

1. `cd ~/Projects/ai-harness-config/.worktrees/install-tests-fixes && sh tests/install.test.sh` → семь `ok`, `7/7 passed`.
2. Команда из `README.md:210` с `45d` вместо `<правка>`, запущенная как есть из корня worktree: `FAIL backup: exit status 0 / exit status 1`, `6/7 passed`, exit 1 (проверено). С `45s/run mv/mv/` вместо `<правка>` — `FAIL dry-run: exit status 0 / exit status 1`, `6/7 passed` (проверено тем же мутантом через скрипт-обёртку, тот же текст ошибки).

## Не сделано

Всё сделано. Из «Вне границы фичи» ничего не трогалось (`install.sh:43`, `.gitignore`, статус спеки, lint раннера).

Замечание: в README команда `m=$(mktemp); …` оставляет временный файл `$m`; в README это не чистится, брифом не требовалось.

## Просьбы к другим агентам

нет
