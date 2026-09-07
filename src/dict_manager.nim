## nimorphy/dict_manager.nim
## Менеджер автозагрузки и кэширования словарей

import std/[os, osproc, strutils]

const
  DefaultDictReleaseUrl* = "https://github.com/framefrok/nimorphy/releases/download/v0.1.0/dict.bin.zip"
  DictFileName* = "dict.bin"

proc getAppCacheDictPath*(): string =
  let cacheDir = getCacheDir("nimorphy")
  createDir(cacheDir)
  result = cacheDir / DictFileName

proc extractZip(zipPath, destDir: string) =
  when defined(windows):
    # 1. Пробуем встроенный в Windows tar.exe (самый быстрый способ)
    let tarCmd = "tar.exe -xf \"" & zipPath & "\" -C \"" & destDir & "\""
    if execCmd(tarCmd) == 0:
      return

    # 2. Запасной вариант через powershell.exe (с обязательным расширением .exe)
    let psCmd = "powershell.exe -NoProfile -Command \"Expand-Archive -Path '" & zipPath & "' -DestinationPath '" & destDir & "' -Force\""
    if execCmd(psCmd) == 0:
      return

    # 3. Вариант через python
    let pyCmd = "python.exe -m zipfile -e \"" & zipPath & "\" \"" & destDir & "\""
    if execCmd(pyCmd) == 0:
      return

    raise newException(IOError, "Не удалось распаковать словарь (tar.exe / powershell.exe недоступны)")
  else:
    let cmd = "unzip -o \"" & zipPath & "\" -d \"" & destDir & "\""
    if execCmd(cmd) == 0: return
    let tarCmd = "tar -xf \"" & zipPath & "\" -C \"" & destDir & "\""
    if execCmd(tarCmd) == 0: return
    raise newException(IOError, "Failed to extract dictionary archive (unzip/tar required)")

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
  # 1. Пользователь передал путь явно
  if customPath.len > 0 and fileExists(customPath):
    return customPath

  # 2. Поиск по вероятным локальным путям в проекте
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

  # 3. Файл уже есть в системном кэше
  let cachePath = getAppCacheDictPath()
  if fileExists(cachePath) and getFileSize(cachePath) > 10_000_000:
    return cachePath

  # 4. Словаря нигде нет -> автозагрузка через системный Schannel/curl
  return downloadPrebuiltDict(DefaultDictReleaseUrl, cachePath)