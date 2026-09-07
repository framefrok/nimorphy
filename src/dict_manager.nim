## nimorphy/dict_manager.nim
## Менеджер автозагрузки и кэширования словарей

import std/[os, osproc, streams]

when defined(windows):
  # Гарантируем корректный вывод кириллицы в консоли Windows
  proc SetConsoleOutputCP(wCodePageID: cuint): cint {.stdcall, dynlib: "kernel32", importc.}
  discard SetConsoleOutputCP(65001)

const
  DefaultDictReleaseUrl* = "https://github.com/framefrok/nimorphy/releases/download/v0.1.3/dict.bin.zip"
  DictFileName* = "dict.bin"

proc runCmd(exe: string, args: openArray[string]): bool =
  ## Безопасный запуск процессов: передаёт аргументы напрямую (UTF-16 на Windows),
  ## минуя cmd.exe и проблемы с не-ASCII путями и экранированием.
  try:
    let p = startProcess(exe, args = args, options = {poUsePath, poStdErrToStdOut})
    defer: p.close()
    # Вычитываем вывод, чтобы процесс не завис при переполнении буфера пайпа
    discard p.outputStream.readAll()
    return p.waitForExit() == 0
  except CatchableError:
    return false

proc getAppCacheDictPath*(): string =
  let cacheDir = getCacheDir("nimorphy")
  createDir(cacheDir)
  result = cacheDir / DictFileName

proc extractZip(zipPath, destDir: string) =
  when defined(windows):
    # 1. Встроенный tar.exe (Windows 10/11)
    if runCmd("tar.exe", ["-xf", zipPath, "-C", destDir]):
      return

    # 2. PowerShell с передачей путей через аргументы
    let psScript = "& { param($zip, $dest) $ErrorActionPreference = 'Stop'; Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force }"
    if runCmd("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", psScript, zipPath, destDir]):
      return

    # 3. Python (если установлен)
    if runCmd("python.exe", ["-m", "zipfile", "-e", zipPath, destDir]):
      return

    raise newException(IOError, "Не удалось распаковать словарь (tar.exe, powershell.exe и python.exe недоступны)")
  else:
    if runCmd("unzip", ["-o", zipPath, "-d", destDir]):
      return
    if runCmd("tar", ["-xf", zipPath, "-C", destDir]):
      return
    if runCmd("python3", ["-m", "zipfile", "-e", zipPath, destDir]):
      return

    raise newException(IOError, "Не удалось распаковать архив словаря (требуется unzip, tar или python3)")

proc downloadNative(url, destPath: string) =
  ## Системная загрузка без внешних зависимостей (OpenSSL DLL не требуются)
  when defined(windows):
    if runCmd("curl.exe", ["-f", "-L", "-o", destPath, url]) and fileExists(destPath) and getFileSize(destPath) > 1000:
      return

    let psScript = "& { param($u, $p) $ErrorActionPreference = 'Stop'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile($u, $p) }"
    if runCmd("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", psScript, url, destPath]) and fileExists(destPath) and getFileSize(destPath) > 1000:
      return

    raise newException(IOError, "Не удалось скачать словарь через curl.exe или powershell.exe")
  else:
    if runCmd("curl", ["-f", "-L", "-o", destPath, url]) and fileExists(destPath) and getFileSize(destPath) > 1000:
      return

    if runCmd("wget", ["-O", destPath, url]) and fileExists(destPath) and getFileSize(destPath) > 1000:
      return

    raise newException(IOError, "Не удалось скачать словарь через curl или wget")

proc downloadPrebuiltDict*(url: string = DefaultDictReleaseUrl, targetPath: string = ""): string =
  let finalPath = if targetPath.len > 0: targetPath else: getAppCacheDictPath()
  let destDir = parentDir(finalPath)
  let zipPath = destDir / "dict.bin.zip"

  echo "[nimorphy] Загрузка скомпилированного словаря (~28 МБ)..."
  echo "[nimorphy] Источник: ", url

  downloadNative(url, zipPath)

  echo "[nimorphy] Распаковка словаря в: ", finalPath
  extractZip(zipPath, destDir)

  if fileExists(zipPath):
    removeFile(zipPath)

  if not fileExists(finalPath) or getFileSize(finalPath) < 10_000_000:
    raise newException(IOError, "Ошибка: распакованный словарь поврежден или отсутствует.")

  echo "[nimorphy] Словарь готов к работе!"
  return finalPath

proc resolveDictPath*(customPath: string = ""): string =
  # 1. Явный путь
  if customPath.len > 0 and fileExists(customPath):
    return customPath

  # 2. Поиск по локальным путям проекта
  let localCandidates = [
    DictFileName,
    "tools" / DictFileName,
    getAppDir() / DictFileName,
    getAppDir() / "tools" / DictFileName,
    parentDir(getAppDir()) / "tools" / DictFileName
  ]

  for c in localCandidates:
    if fileExists(c) and getFileSize(c) > 10_000_000:
      return c

  # 3. Файл уже есть в кэше
  let cachePath = getAppCacheDictPath()
  if fileExists(cachePath) and getFileSize(cachePath) > 10_000_000:
    return cachePath

  # 4. Скачивание в кэш
  return downloadPrebuiltDict(DefaultDictReleaseUrl, cachePath)
