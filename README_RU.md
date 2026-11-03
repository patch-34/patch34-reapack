# Patch34 Scripts

[English](README.md) · **Русский**

## О проекте

**Patch34 Scripts** — коллекция Lua-скриптов ReaScript и эффектов JSFX для REAPER, которую разрабатывает саунд-дизайнер Aleksei Vorobev.

Коллекция включает инструменты для редактирования аудио, навигации по временной шкале, организации проектов, автоматизации рабочих операций и экспериментального звукового дизайна.

Каждый инструмент разработан как самостоятельная утилита с конкретным назначением, понятным управлением и возможностью использования в повседневной работе с REAPER.

**Автор:** [Aleksei Vorobev / Patch34](https://github.com/patch-34)

## Подключение каталога

1. Установите [ReaPack](https://reapack.com/) в REAPER.
2. Откройте **Extensions → ReaPack → Import repositories…** и добавьте адрес:

   `https://raw.githubusercontent.com/patch-34/patch34-reapack/main/index.xml`

3. Откройте **Extensions → ReaPack → Browse packages** и выберите нужный скрипт или JSFX.
4. Установите выбранные пакеты и выполните синхронизацию. Дальнейшие обновления устанавливаются через тот же интерфейс.

## Состав каталога

В каталоге `Scripts/` размещены Delete Nearest Marker to Cursor, Duplicate Selected Items to Next Measure, Play 2s Before Next Marker or Region, Find and Recolor Glued Items, Focus Blanket, REAPER Timeline Screensaver, Region Time Counter Mini, Region Time Counter, ReaNotepad и Podcast HTML/DOCX Script Viewer.

Каталог `Effects/` содержит Raw Six — шестиголосный генератор JSFX. В состав пакета входит шаблон трека, устанавливаемый вместе с эффектом.

Инструкции по использованию и сведения о лицензии каждого инструмента приведены в его репозитории.

## Публикация обновлений

Файл `index.xml` генерируется автоматически сценарием `.github/workflows/reapack.yml` после отправки изменений в ветку `main`. Не редактируйте индекс вручную. После обновления пакетов проверьте выполнение GitHub Actions и наличие нужных версий в сформированном индексе.
