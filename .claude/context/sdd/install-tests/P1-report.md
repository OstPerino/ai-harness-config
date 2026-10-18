# Отчёт партии P1 `install-test-runner`

## Файлы

| файл | что изменилось |
|---|---|
| tests/install.test.sh | новый, исполняемый: песочница, обёртка запуска, хелперы, цикл, 4 сценария |
| README.md | строка `tests/` в «Структуре»; третья команда и фраза про мутанты в «Проверке харнесса» |

Коммиты в ветке `sdd/install-tests-P1`: `6a2cc91` test(install) и `006affd` docs(install). Эмодзи поставил хук. `install.sh` и `CLAUDE.md` не тронуты.

## Гейт

`sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh` — зелёный. Тестов: 0 → 4. До: `lint: ok`. После: `ok link`, `ok unchanged`, `ok dry-run`, `ok bad-arg`, `4/4 passed`, exit 0.
Под `dash tests/install.test.sh` — `4/4 passed`, exit 0. Под `bash tests/install.test.sh` — `4/4 passed`, exit 0.
`INSTALL_SH=/nonexistent sh tests/install.test.sh` — в stderr `install-test: cannot read INSTALL_SH: /nonexistent`, exit 2.

## Решения

- Снимок: `ls -lAR <каталог> > файл`, сравнение `cmp -s`. Показывает имена, типы, права, цели ссылок и mtime каталогов. Ничего не создаётся и не удаляется, значит mtime не меняется. В ложные срабатывания не попал, `find -exec stat` не понадобился. Пути в снимке содержат путь песочницы, он один на сценарий, поэтому сравнение «до/после» стабильно.
- `unchanged` готовит состояние руками (`mkdir` и пять `ln -s`), а не первым прогоном скрипта. Иначе мутант `49d` роняет и `link`, и `unchanged`. Это отступление от формулировки спеки «второй прогон».
- Обёртка запуска задаёт и `CLAUDE_HOME="$sb/home"`, и `HOME="$sb"`. Если `CLAUDE_HOME` когда-нибудь потеряется, скрипт всё равно пишет в `$sb/.claude`, а не в настоящий каталог.
- Код возврата: `run_install` кладёт его в переменную `status` (через `|| status=$?`, раннер не падает), проверка — `assert_status <ожидаемый>`. Вывод идёт в `$sb/out`.
- Имена сценариев с дефисом (`dry-run`, `bad-arg`) в функциях заменены на `t_dry_run`, `t_bad_arg`: дефис в имени функции не POSIX. Имя в выводе — `dry-run`, `bad-arg`, как в брифе; функция получается через `tr - _`.
- Отсутствие `INSTALL_SH` как читаемого файла: сообщение в stderr и exit 2 до запуска сценариев.
- Песочница: `mktemp -d`, `cd && pwd`, `trap 'rm -rf "${sb:?}"' EXIT` внутри подоболочки сценария. Работает и после `exit 1` из хелпера. После всех прогонов `ls $TMPDIR | grep install-test.` пусто, в том числе после FAIL.
- FAIL-строка одна: `FAIL <сценарий>: <ожидали> / <получили>`. Для `assert_output_contains` и `assert_tree_unchanged` «получили» — хвост вывода или diff, склеенные через `|`.

## Мутации

Перед каждым запуском `diff install.sh "$m"` показал ровно одну правку.

| тест | испорченная строка | покраснел | из нужного ассерта | фактический результат |
|---|---|---|---|---|
| link | install.sh:49 `run ln -s` удалена | да | да (`assert_link`) | `FAIL link: symlink …/home/agents/a.md / not a symlink`, `ok` у остальных трёх, `3/4 passed`, exit 1 |
| unchanged | install.sh:41 `return` удалён | да | да (`assert_output_contains`) | `FAIL unchanged: output contains 'linked=0 unchanged=5 backed_up=0 pruned=0' / … done: linked=5 unchanged=5 backed_up=5 pruned=0`, остальные `ok`, `3/4 passed`, exit 1 |
| dry-run | install.sh:28 `-eq 1` → `-eq 9` | да | да (`assert_tree_unchanged`) | `FAIL dry-run: …/home unchanged / <diff со списком появившихся ссылок>`, остальные `ok`, `3/4 passed`, exit 1 |
| bad-arg | install.sh:24 `exit 1` → `exit 0` | да | да (`assert_status`) | `FAIL bad-arg: exit status 1 / exit status 0`, остальные `ok`, `3/4 passed`, exit 1 |

Каждый мутант роняет только свой сценарий.

## Проверка ~/.claude

`marker=$(mktemp); sh tests/install.test.sh; dash tests/install.test.sh; find ~/.claude/agents ~/.claude/skills -maxdepth 1 -newer "$marker"` — вывод пустой. `git status --short` до коммитов: только `tests/install.test.sh` (README правился позже); после коммитов пусто.

## Ручная проверка для владельца

1. `cd /Users/nikitakucenko/Projects/ai-harness-config/.claude/worktrees/install-tests-P1 && sh tests/install.test.sh` → четыре строки `ok …` и `4/4 passed`.
2. `m=$(mktemp); sed '49d' install.sh > "$m"; INSTALL_SH="$m" sh tests/install.test.sh; echo $?` → `FAIL link: …`, `3/4 passed`, `1`.

## Не сделано

Всё сделано. `shellcheck` не установлен, не запускался. Сценарии backup, prune, prune-foreign — P2.

Замечание: `lint-harness.sh` не проверяет `tests/install.test.sh`; на ошибки стиля раннера его гейт не реагирует.

## Находки в install.sh

Тесты ничего не показали.

## Просьбы к другим агентам

Ведущему: при мерже партии обновить ключ `Гейт:` в `CLAUDE.md` на `sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh`.

## Фикс-раунд

Коммит: `test(install): fail closed on sandbox setup errors`, меняется только `tests/install.test.sh`. Minor-находки ревью (ls -lAR без inode, SIGTERM под dash, `$m` в README) в код не вошли.

### Что изменено

- Critical: в `sandbox` каждый шаг проверяется явно. `mktemp ... || exit 1`, `[ -n "$sb" ] && [ -d "$sb" ] || exit 1`, `sb=$(cd "$sb" && pwd) || exit 1`, затем `case "${sb##*/}" in install-test.??????) ;; *) exit 1 ;; esac`. `trap 'rm -rf "${sb:?}"' EXIT` ставится только после этих проверок, поэтому при сбое `mktemp` трап не существует и удалять нечего.
- Important: сценарий идёт как `set +e; ( set -e; sandbox; "$fn" ); rc=$?; set -e`, итог по `rc`. Упавший `mkdir`/`cp`/`ln` внутри подоболочки теперь даёт ненулевой код.
- Побочное решение: `fail()` теперь выходит с кодом 70, а не 1. По коду раннер отличает ассерт (FAIL уже напечатан хелпером) от сбоя подготовки или команды, где хелпер молчал: тогда раннер сам печатает `FAIL <имя>: setup and commands succeed / exit status <rc>`. Без этого сбой подготовки давал бы счёт `3/4` без строки FAIL. Бриф говорил «exit 1» в хелперах; код 70 внутренний и наружу не виден (наружу раннер выходит 0 или 1).

### Гейт (после правки)

`sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh` — `lint: ok`, `ok link`, `ok unchanged`, `ok dry-run`, `ok bad-arg`, `4/4 passed`, exit 0. `dash tests/install.test.sh` и `bash tests/install.test.sh` — те же четыре `ok`, `4/4 passed`, exit 0.

### Критический случай ревью: TMPDIR=/nonexistent

Копия раннера, где `rm -rf "${sb:?}"` заменён на `echo WOULD_RM_RF "$sb"` (grep подтвердил одну замену), пустой cwd, `INSTALL_SH` указывает на настоящий `install.sh`, запуск под sh, dash и bash. Одинаковый результат под всеми тремя:

```
mktemp: mkdtemp failed on /nonexistent/install-test.NRlqCD: No such file or directory
FAIL link: setup and commands succeed / exit status 1
mktemp: mkdtemp failed on /nonexistent/install-test.600s39: No such file or directory
FAIL unchanged: setup and commands succeed / exit status 1
mktemp: mkdtemp failed on /nonexistent/install-test.36sQrW: No such file or directory
FAIL dry-run: setup and commands succeed / exit status 1
mktemp: mkdtemp failed on /nonexistent/install-test.dzrmUq: No such file or directory
FAIL bad-arg: setup and commands succeed / exit status 1
0/4 passed
sh exit=1
cwd contents: []
```

dash и bash: те же строки, `0/4 passed`, `exit=1`, `cwd contents: []`. `WOULD_RM_RF` не напечатан ни разу, cwd пуст, ни одного `ok`.

### Сломанная подготовка: cp падает

Копия раннера, где `cp "$INSTALL_SH" "$sb/repo/install.sh"` заменён на `cp /nonexistent-file "$sb/repo/install.sh"`. Под sh, dash и bash по каждому сценарию:

```
cp: /nonexistent-file: No such file or directory
FAIL link: setup and commands succeed / exit status 1
... (то же для unchanged, dry-run, bad-arg)
0/4 passed
```

exit=1 под всеми тремя. До фикса те же сценарии печатали `ok`. После обоих прогонов `ls $TMPDIR | grep install-test.` пусто.

### Четыре мутанта (sh и dash, перед каждым `diff` показал одну правку)

| мутант | результат под sh и dash |
|---|---|
| `49d` | `FAIL link: symlink …/home/agents/a.md / not a symlink`, три `ok`, `3/4 passed`; exit 1 (проверено отдельно, sh и dash) |
| `41d` | `FAIL unchanged: output contains 'linked=0 unchanged=5 backed_up=0 pruned=0' / …`, три `ok`, `3/4 passed` |
| `-eq 1` → `-eq 9` | `FAIL dry-run: …/home unchanged / <diff со ссылками>`, три `ok`, `3/4 passed` |
| `24s/exit 1/exit 0/` | `FAIL bad-arg: exit status 1 / exit status 0`, три `ok`, `3/4 passed` |

Exit code для мутантов `41d`, `-eq 9` и `24s` отдельно не печатал (в моём цикле его съел pipe); он следует из `passed != total` в последней строке раннера и проверен напрямую только для `49d`.
