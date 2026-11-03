# Patch34 ReaPack

[English](README.md) · **Русский**

Личный каталог ReaPack со скриптами и JSFX для REAPER. Автор: [Aleksei Vorobev / Patch34](https://github.com/patch-34).

## Подключение каталога

1. Установите [ReaPack](https://reapack.com/) в REAPER.
2. Откройте **Extensions → ReaPack → Import repositories…** и добавьте адрес:

   `https://raw.githubusercontent.com/patch-34/patch34-reapack/main/index.xml`

3. Откройте **Extensions → ReaPack → Browse packages** и выберите нужный скрипт или JSFX.
4. Установите выбранные пакеты и выполните синхронизацию. В дальнейшем обновления устанавливаются через тот же интерфейс.

## Состав каталога

В каталоге `Scripts/` подготовлены семь новых ReaScript:

- Delete Nearest Marker to Cursor.
- Duplicate Selected Items to Next Measure.
- Play 2s Before Next Marker or Region.
- Find and Recolor Glued Items.
- Focus Blanket.
- REAPER Timeline Screensaver.
- Region Time Counter Mini.

Каталог `Effects/` содержит **Raw Six** — шестиголосный JSFX-генератор сигнала. В состав пакета входит шаблон трека, который устанавливается вместе с эффектом.

Ранее опубликованные пакеты **Region Time Counter** (полная версия), **ReaNotepad** и **Podcast HTML/DOCX Script Viewer** остаются отдельными пакетами и не изменяются.

## Публикация

Индекс генерируется автоматически через `.github/workflows/reapack.yml` при отправке изменений в ветку `main`. Не изменяйте `index.xml` вручную.

После объединения изменений проверьте успешное выполнение GitHub Actions и убедитесь, что все восемь новых пакетов присутствуют в обновлённом индексе.

## Авторство

Автор: [Aleksei Vorobev / Patch34](https://github.com/patch-34).

Руководство пользователя и лицензия каждого пакета приведены в его собственном репозитории.
