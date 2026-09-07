## tools/publish.nim
## Скрипт автоматизации тестирования и публикации nimorphy на GitHub

import std/[os, osproc, strutils]

proc runCmd(cmd: string, fatal = true) =
  echo ">> ", cmd
  let code = execCmd(cmd)
  if code != 0 and fatal:
    quit("Ошибка при выполнении: " & cmd)

echo "=================================================="
echo "   nimorphy: Автоматизация сборки и релиза"
echo "=================================================="

# 1. Прогоняем тесты функционала
echo "\n[1/4] Запуск тестов библиотеки..."
runCmd("nim c -r -d:release --mm:orc -d:danger tools/test_features.nim")

# 2. Проверяем наличие dict.bin.zip
echo "\n[2/4] Проверка архива словаря..."
var zipPath = "tools" / "dict.bin.zip"
if not fileExists(zipPath):
  zipPath = "dict.bin.zip"
if not fileExists(zipPath):
  echo "Архив dict.bin.zip не найден. Создаем из dict.bin..."
  when defined(windows):
    runCmd("powershell -command \"Compress-Archive -Path tools/dict.bin -DestinationPath tools/dict.bin.zip -Force\"")
    zipPath = "tools" / "dict.bin.zip"
  else:
    runCmd("zip -j tools/dict.bin.zip tools/dict.bin")
    zipPath = "tools" / "dict.bin.zip"

echo "Архив готов: ", zipPath, " (", (getFileSize(zipPath).float / (1024.0 * 1024.0)).formatFloat(ffDecimal, 2), " МБ)"

# 3. Настройка Git и коммит
echo "\n[3/4] Подготовка Git-репозитория..."
if not dirExists(".git"):
  runCmd("git init")
  runCmd("git branch -M main")
  runCmd("git remote add origin https://github.com/framefrok/nimorphy.git", fatal = false)

runCmd("git add .")
runCmd("git commit -m \"feat: initial release of nimorphy v0.1.0 - high-performance Russian morphology\"", fatal = false)

# 4. Пуш в репозиторий и создание тега
echo "\n[4/4] Отправка в GitHub..."
runCmd("git push -u origin main")
runCmd("git tag -a v0.1.0 -m \"Release v0.1.0: First stable release with prebuilt OpenCorpora dictionary\"", fatal = false)
runCmd("git push origin v0.1.0 --force")

echo "\n=================================================="
echo " Код успешно опубликован на GitHub!"
echo " Репозиторий: https://github.com/framefrok/nimorphy"
echo "=================================================="
echo "\nОстался последний простой шаг (залить dict.bin.zip):"
echo "1. Перейди по ссылке: https://github.com/framefrok/nimorphy/releases/new"
echo "2. Выбери существующий тег: v0.1.0"
echo "3. В поле перетащи файл: ", getCurrentDir() / zipPath
echo "4. Нажми 'Publish release'."