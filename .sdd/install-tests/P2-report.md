# Отчёт партии P2 `install-test-backup-prune`

## Файлы

| файл | что изменилось |
|---|---|
| tests/install.test.sh | хелпер `assert_file_content`, сценарии `t_backup`, `t_prune`, `t_prune_foreign`, три имени в списке цикла (+38/-1 строк) |
| README.md | комментарий у строки раннера (:207) дополнен: бэкап, prune своих и чужих висячих ссылок |

Коммиты (ветка `sdd/install-tests-P2`, оба со скоупом `install`, трейлеры на месте, эмодзи поставил хук):
- `d75d383` test(install): cover backup and prune in install tests
- `3a61e7e` docs(install): list backup and prune in harness check

`git status --short` перед коммитами: только `README.md` и `tests/install.test.sh`. После коммитов пусто.

## Гейт

`sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh` — зелёный, exit 0. Тестов: 4 → 7 (`4/4 passed` → `7/7 passed`). Вывод: `lint: ok`, семь строк `ok` (link, unchanged, dry-run, bad-arg, backup, prune, prune-foreign), `7/7 passed`.

- `dash tests/install.test.sh` → `7/7 passed`, exit 0.
- `bash tests/install.test.sh` → `7/7 passed`, exit 0.
- `ls "${TMPDIR:-/tmp}" | grep install-test.` после всех прогонов, включая 7 с FAIL: пусто (grep exit 1).

## Решения

- Мутант `49d` на полном раннере: FAIL `link` (`symlink …/home/agents/a.md / not a symlink`) и FAIL `backup` (та же причина), остальные пять `ok`, `5/7 passed`, exit 1. Это задокументированное исключение из «мутант роняет только свой сценарий»: `backup` по решению ведущего проверяет ссылку `home/agents/a.md`, потому что главный риск бэкапа — файл увезли, а ссылку не поставили.
- prune и prune-foreign готовятся руками, а не первым прогоном — иначе `49d` уронил бы и их. В prune заранее ставится одна ссылка `s2` (потом `repo/claude/skills/s2` удаляется), остальные четыре не ставятся: с ними `41d` дал бы `backed_up=4`, и prune упал бы вместе с unchanged. Отступление от спеки («повторный прогон») сделано по брифу. В prune-foreign цель `$sb/elsewhere/foreign` вне `repo/claude` и не существует: ссылка висячая, значит, её защищает только guard `install.sh:60`, а не проверка `-e`.
- Единственный каталог бэкапа: `set -- "$sb"/home/backups/harness-*`, затем `[ "$#" -eq 1 ] && [ -d "$1" ] || fail …`. Если glob не совпал, `$1` — сам шаблон, и `-d` ложно; два каталога дают `$# -eq 2`.
- Добавлен хелпер `assert_file_content <путь> <строка>`: сначала `[ -f ] && [ ! -L ]`, потом `cat` и сравнение, всё через `fail`. Стоит рядом с остальными `assert_*`. Сравнение через `$(cat)` срезает завершающий перевод строки, что для `mine` допустимо.
- `assert_tree_unchanged` и `snapshot` в P2 не используются: все три сценария по замыслу меняют `home`. Хелперы P1, `sandbox`, `run_install`, `fail`, механика цикла не тронуты. `install.sh` не тронут.

## Мутации

Для каждого мутанта `diff install.sh "$m"` показал ровно одну правку, `bash -n "$m"` прошёл (syntax-ok). Exit code печатался отдельно, без pipe.

| тест | испорченная строка | покраснел | из нужного ассерта | фактический результат |
|---|---|---|---|---|
| backup | install.sh:45 `sed '45d'` (нет `mv`, `ln -s` падает) | да | да, `assert_status 0` | `FAIL backup: exit status 0 / exit status 1`, `6/7 passed`, exit 1 |
| prune | install.sh:62 `sed '62d'` (нет `rm`) | да | да, `assert_not_exists` | `FAIL prune: …/home/skills/s2 absent / …/home/skills/s2 exists`, `6/7 passed`, exit 1 |
| prune-foreign | install.sh:60 `sed '60s|"\$SRC"/\*)|*)|'` | да | да, `assert_link` | `FAIL prune-foreign: symlink …/home/skills/foreign / not a symlink`, `6/7 passed`, exit 1 |
| link | install.sh:49 `sed '49d'` | да | да, `assert_link` a.md | FAIL `link` и FAIL `backup` (исключение), `5/7 passed`, exit 1 |
| unchanged | install.sh:41 `sed '41d'` | да | да, `assert_output_contains` | FAIL только `unchanged` (`linked=5 unchanged=5 backed_up=5 pruned=0`), `6/7 passed`, exit 1 |
| dry-run | install.sh:28 `-eq 1` → `-eq 9` | да | да, `assert_tree_unchanged` | FAIL только `dry-run`, `6/7 passed`, exit 1 |
| bad-arg | install.sh:24 `exit 1` → `exit 0` | да | да, `assert_status 1` | `FAIL bad-arg: exit status 1 / exit status 0`, `6/7 passed`, exit 1 |

Мутанты, кроме `49d`, роняют только свой сценарий.

## Проверка `~/.claude`

```
marker=$(mktemp); sh tests/install.test.sh; dash tests/install.test.sh
find ~/.claude/agents ~/.claude/skills ~/.claude/CLAUDE.md -maxdepth 1 -newer "$marker"
```
Вывод `find`: пусто.

## Ручная проверка для владельца

1. `cd ~/Projects/ai-harness-config/.claude/worktrees/install-tests-P2 && sh tests/install.test.sh` → семь строк `ok …` и `7/7 passed`.
2. `m=$(mktemp); sed '45d' install.sh > "$m"; INSTALL_SH="$m" sh tests/install.test.sh; echo $?` → `FAIL backup: exit status 0 / exit status 1`, `6/7 passed`, `1`.

## Не сделано

Всё сделано. Не покрыто: `--dry-run` вместе с бэкапом и prune (не входит в партию); бэкап каталога вместо файла (`s1` как реальный каталог); два запуска в одну секунду с одинаковым `harness-<ts>`.

Замечание вне партии: `usage` на `-h|--help` (install.sh:22) тестом не покрыт.

## Находки в install.sh

Нет. Тесты показали поведение, совпадающее с кодом.

## Просьбы к другим агентам

Нет.

## Фикс-раунд

Коммит: `test(install): prune agents links and guard repo-prefix targets` (скоуп install, один коммит, правился только `tests/install.test.sh`). `git status --short` после коммита пуст.

Правки:
- Important 1: `t_prune` создаёт висячую `home/agents/gone.md -> $sb/repo/claude/agents/gone.md`, проверяет `assert_not_exists` на неё, итоговая строка `linked=4 unchanged=0 backed_up=0 pruned=2`.
- Important 2 (бывший Minor 2): цель чужой ссылки в `t_prune_foreign` — `$sb/repo/claude-other/foreign` (в `ln -s` и в `assert_link`): начинается с `$SRC`, но вне `$SRC/`.
- Minor 3 в код не вносился, по указанию координатора.

Новые мутанты (diff — ровно одна правка, `bash -n` ok, exit каждого отдельно от pipe):

| мутант | результат | exit |
|---|---|---|
| `sed '85d'` (нет `prune "$DEST/agents"`) | `FAIL prune: …/home/agents/gone.md absent / …/home/agents/gone.md exists`, остальные `ok`, `6/7 passed` | 1 |
| `sed '60s|"\$SRC"/\*)|"$SRC"*)|'` | `FAIL prune-foreign: symlink …/home/skills/foreign / not a symlink`, остальные `ok`, `6/7 passed` | 1 |

Повторная матрица исходных семи мутантов на новом раннере (в каждом случае exit 1):

| мутант | результат |
|---|---|
| `45d` | FAIL только `backup` (`exit status 0 / exit status 1`), `6/7 passed` |
| `62d` | FAIL только `prune` (`…/skills/s2 absent / … exists`), `6/7 passed` |
| guard `*)` | FAIL только `prune-foreign` (`not a symlink`), `6/7 passed` |
| `49d` | FAIL `link` и `backup` (`not a symlink`), `5/7 passed` |
| `41d` | FAIL только `unchanged`, `6/7 passed` |
| `-eq 9` | FAIL только `dry-run`, `6/7 passed` |
| `24s` | FAIL только `bad-arg` (`exit status 1 / exit status 0`), `6/7 passed` |

Гейт: `sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh` — `lint: ok`, семь `ok`, `7/7 passed`, exit 0. `dash tests/install.test.sh` и `bash tests/install.test.sh` — `7/7 passed` (у этих двух прогонов вывод шёл через `tail -1`, поэтому `echo $?` в логе относится к `tail`; сами сценарии все `ok`, FAIL нет). `ls "${TMPDIR:-/tmp}" | grep install-test.` — пусто.
