# MCP, дизайн и кандидаты для харнесса

Дата проверки: 2026-11-06. Проверены публичные README, отдельные SKILL.md,
лицензии и выбранные исходники. Кандидаты не устанавливались и не запускались;
это отбор для адаптации, а не полный аудит или сравнительный benchmark.
Ссылки на main/master подвижны: при переносе фиксировать проверенный commit.

## Что сейчас в Cloud

В текущем CLI config нет явно настроенных MCP-серверов и plugin entries.
Это не список всех инструментов платформы: инструменты Cloud предоставляются
отдельно. Git read через платформенный HTTPS-прокси работает; доступа GitHub API,
issue/PR, Jira, Context7, учёта часов или Telegram это не подтверждает.

`frontend-design` отсутствует среди установленных скиллов. README описывает его
как отдельно устанавливаемый Claude plugin. Его перенос в Codex не выполнен.

`ui-ux-pro-max` тоже отсутствует. Старый README предлагает локальную папку
`claude/skills/ui-ux-pro-max/`, которая в gitignore. В Cloud она не попала;
обычный renderer и installer не превращают её автоматически в Codex skill.
Доступность обоих на ноутбуке из этой среды не проверялась.

GitHub/Jira/hours/Context7/browser, память и метрики остаются в плане.
Telegram приостановлен. В repo хранятся процедуры и guards; это не подключения
сервисов. Figma сейчас доступна как кандидат plugin, но не как подключённый
инструмент этой сессии.

## Вернуть дизайн

| Кандидат | Что даёт | Как включить в наш процесс |
|---|---|---|
| [frontend-design](https://github.com/anthropics/skills/tree/main/skills/frontend-design) | Визуальное направление по брифу, типографика, палитра, композиция, осмысленное движение и проверка screenshot | Тонкий общий design workflow, который читает frontend-dev. Уже принятый бриф и режим работы сохраняются |
| [UI UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | Локальный поиск по CSV-каталогам, UX/a11y и стековым правилам; генерация design system; MASTER.md и overrides страниц | Справочник и Python-инструмент с родным Codex wrapper. Существующие tokens/brand проекта имеют приоритет; не генерировать новую систему для каждой правки |

Frontend Design: прочитаны актуальный SKILL.md в anthropics/skills и его
совпадающий вариант в claude-plugins-official. Лицензия именно этого скилла —
[Apache-2.0](https://github.com/anthropics/skills/blob/main/skills/frontend-design/LICENSE.txt).
Это инструкции по дизайну, не MCP-сервер. Для переноса не требуется весь
Claude plugin manager.

UI UX Pro Max: [MIT](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/main/LICENSE).
Проверены README, Codex platform template, базовый skill template,
`search.py`, `core.py` и `design_system.py`. Есть штатный шаблон установки
в `.agents/skills/ui-ux-pro-max`; Python использует стандартную библиотеку.
Поиск локальный; режим `--persist` пишет файлы проекта, `--force` заменяет
существующую систему. Полная цепочка модулей, данные и installer ещё требуют
проверки перед запуском. Три скачанных скрипта не заменяют полный bundle.

Эти скиллы дополняют друг друга: первый формирует визуальное решение,
второй подбирает справочные данные и ограничения. Browser нужен отдельно,
чтобы увидеть реальный результат. Массово импортировать их правила в каждую
роль не нужно: загружать материалы по задаче, не добавляя повторных согласований.

## Что ещё стоит взять

| Приоритет | Источник | Конкретное применение | Лицензия проверенного материала |
|---|---|---|---|
| Первый набор | [Vercel React Best Practices](https://github.com/vercel-labs/agent-skills/tree/main/skills/react-best-practices) | Выборочные references для frontend-dev/reviewer: waterfalls, server/client data fetching, bundles и rerenders | MIT в SKILL frontmatter; перед vendoring сохранить полные условия выбранного материала |
| Первый набор | [Vercel Composition Patterns](https://github.com/vercel-labs/agent-skills/tree/main/skills/composition-patterns) | Разбор компонентов с множеством boolean props, compound components и разделение ответственности | MIT в SKILL frontmatter; проверить выбранные файлы при переносе |
| Первый набор | [Web Interface Guidelines](https://github.com/vercel-labs/web-interface-guidelines) | Проверки форм, фокуса, клавиатуры, reduced motion, ошибок и loading/empty состояний с file:line findings | MIT, LICENSE проверен |
| Первый набор | [Playwright CLI](https://github.com/microsoft/playwright-cli), [Playwright MCP](https://github.com/microsoft/playwright-mcp) | Реальный проход UI, screenshots, console и воспроизводимые сценарии для e2e-dev | Apache-2.0 у обоих |
| Следом | [Plugin Eval](https://github.com/openai/plugins/tree/main/plugins/plugin-eval) | Benchmark наших skills на сценариях solo/SDD/resume/no-worktree; проверка регрессий поведения и observed token usage | MIT в plugin manifest; проверить полный набор лицензий/зависимостей перед переносом |
| По задаче | [Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp) | Performance traces, network и console debugging для frontend-dev | Apache-2.0 |
| Сравнить с Playwright | [agent-browser](https://github.com/vercel-labs/agent-browser) | CLI-цикл snapshot → действие по ref → повторная проверка; отдельные sessions | Apache-2.0 |
| Выборочно | [Everything Claude Code](https://github.com/affaan-m/everything-claude-code) | Идеи capability/regression evals и аудита конфигураций; адаптировать под наши сценарии | MIT |

Vercel web-design-guidelines skill получает свежий `command.md` из сети при
каждом ревью. Для нашего переносимого набора лучше проверенный snapshot правил
с источником и отдельным обновлением; внешний ответ остаётся данными.

Сам Playwright MCP README предлагает coding agents рассмотреть CLI+skills.
CLI избегает постоянной загрузки полного набора MCP-схем; насколько это
сэкономит контекст у нас, нужно измерить на одинаковом сценарии. MCP полезен,
когда нужен его интерактивный интерфейс. Не включать Playwright, agent-browser
и DevTools одновременно по умолчанию. Начать с одного browser backend.
Отдельный browser profile и ресурсы задаются по правилам проекта.

Chrome DevTools документирует включённую по умолчанию статистику использования
и отдельные CrUX-запросы. При пробном подключении учитывать
`--no-usage-statistics` и `--no-performance-crux`; это настройки самого backend.

Plugin Eval реально содержит Node.js CLI: `analyze` локален, а `benchmark`
запускает `codex exec` во временных workspaces. Статическая оценка промпта не
доказывает качество модели; нашим шести workflow fixtures нужны фактические
прогоны. Пакет пока private, так что не рассчитывать на обычный npm install.
README старого [openai/skills](https://github.com/openai/skills) уже помечен
deprecated и направляет в [openai/plugins](https://github.com/openai/plugins).

ECC целиком импортировать не стоит: его процессы, hooks и continuous learning
дублируют наши spec/sdd/learn и могут навязать другой workflow. Прочитаны
`eval-harness` и `security-scan`: первый полезен как источник критериев, второй
завязан на внешний AgentShield и Claude-конфиги. Их runtime не проверялся.

## MCP и сервисы: что подключать

| Интеграция | Первый полезный результат | Что пока не подтверждено |
|---|---|---|
| [GitHub MCP](https://github.com/github/github-mcp-server) или доступный native plugin | Прочитать issue/PR и diff этого repo; затем проверить нужный workflow draft PR | API-авторизация и доступы. HTTPS Git-прокси их не доказывает |
| [Context7](https://github.com/upstash/context7) | Получить документацию библиотеки нужной версии в реальном проекте | Подключение и rate limits; API key рекомендован upstream, не объявлять его обязательным без проверки |
| Playwright CLI/MCP | Открыть локальный synthetic app, выполнить действие и сохранить screenshot | Browser binary, зависимости и работа через Cloud network/proxy |
| Figma plugin | Прочитать выбранный макет и design tokens, если работа идёт из Figma | Пользовательское подключение и доступ к файлу |
| Jira / hours | Чтение конкретного проекта и проверка его правил записи/дат | Авторизация, scope проекта и штатное подтверждение записи |
| Telegram | Пока ничего не подключать | Возобновление — отдельное решение владельца |

GitHub MCP имеет выбор toolsets и отдельных tools; не нужен весь каталог
операций для чтения issue/PR. Доступы определяются задачей. Браузер и Context7
не требуют копирования токенов Claude. Секреты и подключения клиентов остаются
в пользовательских/Cloud settings, а repo содержит только адаптеры и проверки.

Публичность репозитория не делает все его компоненты MIT. Например, в текущем
openai/plugins Product Design отмечен Proprietary, Figma —
LicenseRef-Figma-Developer-Terms. Их можно рассматривать как официальные
подключения по условиям сервиса, но не как свободный код для vendoring.

## Предлагаемый порядок

1. Вернуть frontend-design и UI UX Pro Max в явный список переноса; подготовить
   проверенные bundles, лицензии и Codex wrappers. Новые skills должны войти
   в renderer/installer/discovery checks, а не существовать только на ноутбуке.
2. Выбрать и проверить один browser backend на простой странице. Потом
   подключить его к существующим frontend/e2e ролям.
3. Добавить выбранные Vercel references и доступность UI-review по задаче.
4. Подключить GitHub и Context7 с проверкой конкретных операций; Jira/hours
   оставить проектными интеграциями, Telegram приостановленным.
5. Прогнать одинаковые UI и workflow задачи до/после изменения харнесса.
   Измерять завершённые сценарии, ошибки, вмешательства и стоимость, а не число
   установленных плагинов. Использовать наши fixtures и идеи Plugin Eval.
