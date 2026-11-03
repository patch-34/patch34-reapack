# Patch34 ReaPack

[English](README.md) · **Русский**

Личный каталог ReaPack для скриптов и JSFX REAPER. Автор: [Aleksei Vorobev / Patch34](https://github.com/patch-34).

## Подключение каталога

1. Установите [ReaPack](https://reapack.com/) в REAPER.
2. Выберите **Extensions → ReaPack → Import repositories…** и добавьте адрес:

   `https://raw.githubusercontent.com/patch-34/patch34-reapack/main/index.xml`

3. Откройте **Extensions → ReaPack → Browse packages**, найдите нужный скрипт или эффект и установите пакет.
4. Выполните синхронизацию. Дальнейшие обновления устанавливаются через ReaPack.

## Состав

В каталоге `Scripts/` размещаются семь новых скриптов: Delete Nearest Marker to Cursor, Duplicate Selected Items to Next Measure, Play 2s Before Next Marker or Region, Find and Recolor Glued Items, Focus Blanket, REAPER Timeline Screensaver и Region Time Counter Mini.

В каталоге `Effects/` размещается Raw Six — шестиголосный генератор JSFX. Вместе с эффектом устанавливается шаблон трека. Существующие пакеты, включая полную версию Region Time Counter, ReaNotepad и Podcast HTML/DOCX Script Viewer, остаются самостоятельными и не изменяются.

## Публикация обновлений

Файл `index.xml` генерируется автоматически сценарием `.github/workflows/reapack.yml` после изменений в `main`. Не редактируйте индекс вручную. После объединения PR необходимо проверить успешное выполнение GitHub Actions и наличие восьми новых пакетов в обновлённом индексе.

## Авторство

[Aleksei Vorobev / Patch34](https://github.com/patch-34). Условия лицензирования и руководство пользователя указаны в репозитории каждого пакета.
