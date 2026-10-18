# test(install): cover install.sh with sandboxed tests

## Что меняется для пользователя

`install.sh` двигает и удаляет файлы в `~/.claude`, а был проверен только руками. Теперь `sh tests/install.test.sh` прогоняет 7 сценариев в песочнице и входит в гейт харнесса: сломанный бэкап, удаление своих или чужих ссылок, «тихий» `--dry-run` — гейт краснеет. Заодно SDD-скиллы перестали писать в `.claude/` проекта — исполнители больше не вызывают запрос разрешения на каждый файл.

## Партии

| партия | что сделано | отчёт |
|---|---|---|
| P1 `install-test-runner` | раннер на POSIX `sh`, песочница с fail-closed подготовкой, хелперы, сценарии link / unchanged / dry-run / bad-arg | `.sdd/install-tests/P1-report.md` |
| P2 `install-test-backup-prune` | сценарии backup / prune / prune-foreign | `.sdd/install-tests/P2-report.md` |
| fixes | `--dry-run` против бэкапа и prune, снимок дерева с inode, запускаемая команда мутанта в README | `.sdd/install-tests/fixes-report.md` |

Ревью: `P1-review.md` (Critical — раннер стёр бы рабочее дерево при упавшем `mktemp`), `P2-review.md`, `final-review-tests.md`. Все Critical и Important закрыты.

Сухой прогон SDD-скиллов на этой фиче: итоги и исправления в скиллах — [`issues/001-own-superpowers.md`](../../issues/001-own-superpowers.md), раздел «Сухой прогон».

## Приёмка

- [x] `sh tests/install.test.sh` → `7/7 passed`, exit 0 — `.sdd/install-tests/fixes-gate-merge.log`.
- [x] Под `dash` и `bash` → `7/7 passed` — `.sdd/install-tests/fixes-gate.log`.
- [x] Каждая мутация `install.sh` роняет свой сценарий, и только его; исключение `49d` (link + backup) — таблицы в отчётах партий, воспроизведено ведущим.
- [x] Настоящий `~/.claude` не изменился — `find -newer` пуст, в отчётах партий.
- [x] Гейт `sh tests/lint-harness.sh && bash -n install.sh && sh tests/install.test.sh` — в `CLAUDE.md` и README.

## Ручная проверка перед мержем

1. `sh tests/install.test.sh` → 7 строк `ok …` и `7/7 passed`.
2. `m=$(mktemp); sed '45d' install.sh > "$m"; INSTALL_SH="$m" sh tests/install.test.sh; echo $?` → `FAIL backup: …`, `6/7 passed`, `1`.

## Не вошло

- Висячая ссылка на месте `dst` (`install.sh:43`) не покрыта сценарием; `-h/--help` не покрыт.
- Каталог бэкапа с точностью до секунды — кандидат в #007.
- SIGTERM под dash оставляет песочницу (Minor из ревью P1).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
