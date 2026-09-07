## nimorphy/dict_manager.nim
## Менеджер автозагрузки и кэширования словарей

import std/[os, osproc, strutils]

const
  DefaultDictReleaseUrl* = "https://github.com/framefrok/nimorphy/releases/download/v0.1.2/dict.bin.zip"
  DictFileName* = "dict.bin"

proc getAppCacheDictPath*(): string =
  let cacheDir = getCacheDir("nimorphy")
  createDir(cacheDir)
  result = cacheDir / DictFileName

proc extractZip(zipPath, destDir: string) =
  when defined(windows):
    # 1. Пробуем tar.exe (встроен в Windows 10/11)
    let tarCmd = "tar.exe -xf " & quoteShell(zipPath) & " -C " & quoteShell(destDir)
    if execShellCmd(tarCmd) == 0:
      return

    # 2. Пробуем powershell.exe с экранированием апострофов и флагом -LiteralPath
    let psZip = zipPath.replace("'", "''")
    let psDest = destDir.replace("'", "''")
    let psCmd = "powershell.exe -NoProfile -Command \"Expand-Archive -LiteralPath '" & psZip & "' -DestinationPath '" & psDest & "' -Force\""
    if execShellCmd(psCmd) == 0:
      return

    # 3. Пробуем python.exe
    let pyCmd = "python.exe -m zipfile -e " & quoteShell(zipPath) & " " & quoteShell(destDir)
    if execShellCmd(pyCmd) == 0:
      return

    raise newException(IOError, "Не удалось распаковать словарь (tar.exe, powershell.exe и python.exe недоступны)")
  else:
    if execShellCmd("unzip -o " & quoteShell(zipPath) & " -d " & quoteShell(destDir)) == 0:
      return
    if execShellCmd("tar -xf " & quoteShell(zipPath) & " -C " & quoteShell(destDir)) == 0:
      return
    raise newException(IOError, "Failed to extract dictionary archive (unzip/tar required)")

proc downloadNative(url, destPath: string) =
  ## Системная загрузка через curl / PowerShell (не требует внешних OpenSSL DLL)
  when defined(windows):
    let curlCmd = "curl.exe -f -L -o " & quoteShell(destPath) & " " & quoteShell(url)
    if execShellCmd(curlCmd) == 0 and fileExists(destPath) and getFileSize(destPath) > 1000:
      return

    let psDest = destPath.replace("'", "''")
    let psUrl = url.replace("'", "''")
    let psCmd = "powershell.exe -NoProfile -Command \"[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile('" & psUrl & "', '" & psDest & "')\""
    if execShellCmd(psCmd) == 0 and fileExists(destPath) and getFileSize(destPath) > 1000:
      return

    raise newException(IOError, "Не удалось скачать словарь через curl.exe или powershell.exe")
  else:
    let curlCmd = "curl -f -L -o " & quoteShell(destPath) & " " & quoteShell(url)
    if execShellCmd(curlCmd) == 0 and fileExists(destPath) and getFileSize(destPath) > 1000:
      return

    let wgetCmd = "wget -O " & quoteShell(destPath) & " " & quoteShell(url)
    if execShellCmd(wgetCmd) == 0 and fileExists(destPath) and getFileSize(destPath) > 1000:
      return

    raise newException(IOError, "Failed to download dictionary via curl/wget")

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