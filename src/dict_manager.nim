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
    let cmd = "powershell -command \"Expand-Archive -Path '" & zipPath & "' -DestinationPath '" & destDir & "' -Force\""
    if execCmd(cmd) != 0:
      raise newException(IOError, "Failed to extract dictionary archive via PowerShell")
  else:
    let cmd = "unzip -o \"" & zipPath & "\" -d \"" & destDir & "\""
    if execCmd(cmd) != 0:
      let tarCmd = "tar -xf \"" & zipPath & "\" -C \"" & destDir & "\""
      if execCmd(tarCmd) != 0:
        raise newException(IOError, "Failed to extract dictionary archive (unzip/tar required)")

proc downloadNative(url, destPath: string) =
  ## Системная загрузка без зависимости от OpenSSL DLL
  when defined(windows):
    # В Windows 10/11 есть встроенный curl.exe со встроенным Schannel SSL
    let curlCmd = "curl.exe -f -L -o \"" & destPath & "\" \"" & url & "\""
    if execCmd(curlCmd) == 0 and fileExists(destPath) and getFileSize(destPath) > 1000:
      return

    # Запасной вариант через PowerShell
    let psCmd = "powershell -command \"[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile('" & url & "', '" & destPath & "')\""
    if execCmd(psCmd) != 0:
      raise newException(IOError, "Не удалось скачать словарь через curl/PowerShell")
  else:
    let curlCmd = "curl -f -L -o \"" & destPath & "\" \"" & url & "\""
    if execCmd(curlCmd) == 0:
      return
    let wgetCmd = "wget -O \"" & destPath & "\" \"" & url & "\""
    if execCmd(wgetCmd) != 0:
      raise newException(IOError, "Не удалось скачать словарь через curl/wget")

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