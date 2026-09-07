## nimorphy/dict_manager.nim
## Менеджер автозагрузки и кэширования словарей.
##
## Особенности:
## - словарь скачивается только при необходимости;
## - кэш находится в пользовательском каталоге;
## - Windows-пути с кириллицей передаются процессам напрямую;
## - не используется cmd.exe;
## - есть fallback через curl / PowerShell / Python;
## - старый бинарный формат не принимается за актуальный.

import std/[os, osproc, streams]

when defined(windows):
  proc SetConsoleOutputCP(
    wCodePageID: cuint
  ): cint {.stdcall, dynlib: "kernel32", importc.}

  discard SetConsoleOutputCP(65001)


const
  DefaultDictReleaseUrl* =
    "https://github.com/framefrok/nimorphy/releases/download/v0.1.3/dict.bin.zip"

  DictFileName* = "dict.bin"

  DictMagic = "NIMORPH2"

  MinDictSize = 10_000_000


# ============================================================================
# Проверка бинарного словаря
# ============================================================================

proc isValidDictionary*(path: string): bool =
  ## Проверяет, что файл существует, имеет разумный размер
  ## и начинается с magic текущего формата nimorphy.

  if not fileExists(path):
    return false

  if getFileSize(path) < MinDictSize:
    return false

  var f: File

  try:
    f = open(path, fmRead)

    var magic = newString(DictMagic.len)

    let readCount =
      f.readBuffer(
        addr magic[0],
        magic.len
      )

    f.close()

    if readCount != magic.len:
      return false

    result =
      magic == DictMagic

  except CatchableError:
    try:
      if f != nil:
        f.close()
    except CatchableError:
      discard

    result = false


# ============================================================================
# Запуск внешней команды
# ============================================================================

proc runCmd(
  exe: string,
  args: openArray[string]
): bool =
  ## Запускает программу напрямую.
  ##
  ## В Windows startProcess() передаёт аргументы без cmd.exe,
  ## поэтому Unicode-пути не превращаются в mojibake.

  var process: Process = nil

  try:
    process =
      startProcess(
        exe,
        args = args,
        options = {
          poUsePath,
          poStdErrToStdOut
        }
      )

    if process.outputStream != nil:
      discard process.outputStream.readAll()

    result =
      process.waitForExit() == 0

  except CatchableError:
    result = false

  finally:
    if process != nil:
      try:
        process.close()
      except CatchableError:
        discard


# ============================================================================
# Пути
# ============================================================================

proc getAppCacheDictPath*(): string =
  ## Возвращает путь к словарю в пользовательском кэше.

  let cacheDir =
    getCacheDir("nimorphy")

  createDir(cacheDir)

  result =
    cacheDir / DictFileName


when defined(windows):

  proc getPowerShellPath(): string =
    ## PowerShell может отсутствовать в PATH.
    ##
    ## Поэтому сначала используем стандартное расположение
    ## Windows PowerShell.

    let windir =
      getEnv("WINDIR", "C:\\Windows")

    let systemPowerShell =
      windir /
      "System32" /
      "WindowsPowerShell" /
      "v1.0" /
      "powershell.exe"

    if fileExists(systemPowerShell):
      return systemPowerShell

    # Fallback: обычный поиск через PATH.
    "powershell.exe"


  proc getCurlPath(): string =
    ## Ищем системный curl напрямую, чтобы не зависеть
    ## от PATH.

    let windir =
      getEnv("WINDIR", "C:\\Windows")

    let systemCurl =
      windir /
      "System32" /
      "curl.exe"

    if fileExists(systemCurl):
      return systemCurl

    "curl.exe"


  proc getTarPath(): string =
    ## Ищем встроенный Windows tar напрямую.

    let windir =
      getEnv("WINDIR", "C:\\Windows")

    let systemTar =
      windir /
      "System32" /
      "tar.exe"

    if fileExists(systemTar):
      return systemTar

    "tar.exe"


# ============================================================================
# Распаковка ZIP
# ============================================================================

proc extractZip(
  zipPath,
  destDir: string
) =
  when defined(windows):

    # ------------------------------------------------------------------------
    # 1. Встроенный tar.exe.
    # ------------------------------------------------------------------------

    let tarPath =
      getTarPath()

    if runCmd(
      tarPath,
      [
        "-xf",
        zipPath,
        "-C",
        destDir
      ]
    ):
      return

    # ------------------------------------------------------------------------
    # 2. PowerShell.
    #
    # Пути передаются отдельными аргументами, а не вставляются
    # в строку командной строки.
    # ------------------------------------------------------------------------

    let powerShell =
      getPowerShellPath()

    let psScript =
      "& { " &
      "param($zip, $dest) " &
      "$ErrorActionPreference = 'Stop'; " &
      "Expand-Archive " &
      "-LiteralPath $zip " &
      "-DestinationPath $dest " &
      "-Force " &
      "}"

    if runCmd(
      powerShell,
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        psScript,
        zipPath,
        destDir
      ]
    ):
      return

    # ------------------------------------------------------------------------
    # 3. Python.
    # ------------------------------------------------------------------------

    if runCmd(
      "python.exe",
      [
        "-m",
        "zipfile",
        "-e",
        zipPath,
        destDir
      ]
    ):
      return

    raise newException(
      IOError,
      "Не удалось распаковать словарь " &
      "(tar.exe, PowerShell или Python недоступны)"
    )

  else:

    # ------------------------------------------------------------------------
    # Linux / Unix: unzip.
    # ------------------------------------------------------------------------

    if runCmd(
      "unzip",
      [
        "-o",
        zipPath,
        "-d",
        destDir
      ]
    ):
      return

    # ------------------------------------------------------------------------
    # tar.
    # ------------------------------------------------------------------------

    if runCmd(
      "tar",
      [
        "-xf",
        zipPath,
        "-C",
        destDir
      ]
    ):
      return

    # ------------------------------------------------------------------------
    # Python 3.
    # ------------------------------------------------------------------------

    if runCmd(
      "python3",
      [
        "-m",
        "zipfile",
        "-e",
        zipPath,
        destDir
      ]
    ):
      return

    raise newException(
      IOError,
      "Не удалось распаковать архив словаря " &
      "(требуется unzip, tar или python3)"
    )


# ============================================================================
# Загрузка
# ============================================================================

proc downloadNative(
  url,
  destPath: string
) =
  ## Системная загрузка без внешних Nim-зависимостей.
  ##
  ## Очень важно:
  ## путь передаётся как отдельный аргумент startProcess(),
  ## поэтому C:\Users\Георгий\... не проходит через cmd.exe.

  when defined(windows):

    let curlPath =
      getCurlPath()

    # ------------------------------------------------------------------------
    # curl.exe
    # ------------------------------------------------------------------------

    if runCmd(
      curlPath,
      [
        "-f",
        "-L",
        "--retry",
        "2",
        "-o",
        destPath,
        url
      ]
    ):
      if fileExists(destPath) and
         getFileSize(destPath) > 1000:

        return

    # Если curl создал повреждённый/неполный файл,
    # удаляем его перед следующим fallback.

    if fileExists(destPath):
      try:
        removeFile(destPath)
      except CatchableError:
        discard

    # ------------------------------------------------------------------------
    # PowerShell / WebClient
    # ------------------------------------------------------------------------

    let powerShell =
      getPowerShellPath()

    let psScript =
      "& { " &
      "param($u, $p) " &
      "$ErrorActionPreference = 'Stop'; " &
      "[Net.ServicePointManager]::SecurityProtocol = " &
      "[Net.SecurityProtocolType]::Tls12; " &
      "(New-Object Net.WebClient).DownloadFile($u, $p) " &
      "}"

    if runCmd(
      powerShell,
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        psScript,
        url,
        destPath
      ]
    ):
      if fileExists(destPath) and
         getFileSize(destPath) > 1000:

        return

    if fileExists(destPath):
      try:
        removeFile(destPath)
      except CatchableError:
        discard

    raise newException(
      IOError,
      "Не удалось скачать словарь через curl.exe " &
      "или PowerShell."
    )

  else:

    # ------------------------------------------------------------------------
    # curl.
    # ------------------------------------------------------------------------

    if runCmd(
      "curl",
      [
        "-f",
        "-L",
        "--retry",
        "2",
        "-o",
        destPath,
        url
      ]
    ):
      if fileExists(destPath) and
         getFileSize(destPath) > 1000:

        return

    if fileExists(destPath):
      try:
        removeFile(destPath)
      except CatchableError:
        discard

    # ------------------------------------------------------------------------
    # wget.
    # ------------------------------------------------------------------------

    if runCmd(
      "wget",
      [
        "-O",
        destPath,
        url
      ]
    ):
      if fileExists(destPath) and
         getFileSize(destPath) > 1000:

        return

    if fileExists(destPath):
      try:
        removeFile(destPath)
      except CatchableError:
        discard

    raise newException(
      IOError,
      "Не удалось скачать словарь через curl или wget."
    )


# ============================================================================
# Загрузка и распаковка готового словаря
# ============================================================================

proc downloadPrebuiltDict*(
  url: string = DefaultDictReleaseUrl,
  targetPath: string = ""
): string =
  ## Загружает и распаковывает готовый бинарный словарь.

  let finalPath =
    if targetPath.len > 0:
      targetPath
    else:
      getAppCacheDictPath()

  let destDir =
    parentDir(finalPath)

  createDir(destDir)

  # --------------------------------------------------------------------------
  # Используем временный ZIP.
  #
  # ВАЖНО:
  # сам ZIP теперь хранится в tempDir, а не в пользовательском cache path.
  # Это дополнительно уменьшает вероятность проблем с внешними программами.
  # --------------------------------------------------------------------------

  let tempDir =
    getTempDir() /
    "nimorphy_download"

  createDir(tempDir)

  let zipPath =
    tempDir /
    "dict.bin.zip"

  try:

    if fileExists(zipPath):
      try:
        removeFile(zipPath)
      except CatchableError:
        discard

    echo(
      "[nimorphy] Загрузка скомпилированного словаря (~28 МБ)..."
    )

    echo(
      "[nimorphy] Источник: ",
      url
    )

    downloadNative(
      url,
      zipPath
    )

    if not fileExists(zipPath) or
       getFileSize(zipPath) < 1000:

      raise newException(
        IOError,
        "Архив словаря не был загружен."
      )

    # ------------------------------------------------------------------------
    # Распаковка во временную директорию.
    #
    # Это позволяет сначала полностью подготовить словарь,
    # а затем перенести готовый dict.bin в кэш.
    # ------------------------------------------------------------------------

    let extractDir =
      tempDir / "extracted"

    createDir(extractDir)

    echo(
      "[nimorphy] Распаковка словаря..."
    )

    extractZip(
      zipPath,
      extractDir
    )

    let extractedPath =
      extractDir / DictFileName

    if not isValidDictionary(extractedPath):

      raise newException(
        IOError,
        "Ошибка: загруженный словарь имеет " &
        "неверный формат или повреждён."
      )

    # ------------------------------------------------------------------------
    # Копируем/перемещаем только валидный NIMORPH2.
    # ------------------------------------------------------------------------

    let newPath =
      finalPath & ".new"

    if fileExists(newPath):
      try:
        removeFile(newPath)
      except CatchableError:
        discard

    copyFile(
      extractedPath,
      newPath
    )

    if not isValidDictionary(newPath):

      if fileExists(newPath):
        try:
          removeFile(newPath)
        except CatchableError:
          discard

      raise newException(
        IOError,
        "Ошибка: не удалось сохранить словарь в кэш."
      )

    # ------------------------------------------------------------------------
    # Обновляем основной файл.
    # ------------------------------------------------------------------------

    if fileExists(finalPath):
      try:
        removeFile(finalPath)
      except CatchableError:
        discard

    moveFile(
      newPath,
      finalPath
    )

    if not isValidDictionary(finalPath):

      raise newException(
        IOError,
        "Ошибка: сохранённый словарь повреждён."
      )

    echo(
      "[nimorphy] Словарь готов к работе!"
    )

    result =
      finalPath

  finally:

    # ------------------------------------------------------------------------
    # Удаляем временные данные.
    # ------------------------------------------------------------------------

    if fileExists(zipPath):
      try:
        removeFile(zipPath)
      except CatchableError:
        discard

    let extractedDir =
      tempDir / "extracted"

    if dirExists(extractedDir):
      try:
        removeDir(extractedDir)
      except CatchableError:
        discard

    if dirExists(tempDir):
      try:
        removeDir(tempDir)
      except CatchableError:
        discard


# ============================================================================
# Разрешение пути словаря
# ============================================================================

proc resolveDictPath*(
  customPath: string = ""
): string =
  # --------------------------------------------------------------------------
  # 1. Пользователь передал путь явно.
  # --------------------------------------------------------------------------

  if customPath.len > 0 and
     isValidDictionary(customPath):

    return customPath

  # --------------------------------------------------------------------------
  # 2. Поиск локального словаря.
  #
  # ВАЖНО:
  # теперь проверяется не размер, а реальный magic NIMORPH2.
  # --------------------------------------------------------------------------

  let localCandidates = [
    DictFileName,

    "tools" / DictFileName,

    getAppDir() /
      DictFileName,

    getAppDir() /
      "tools" /
      DictFileName,

    parentDir(getAppDir()) /
      "tools" /
      DictFileName
  ]

  for c in localCandidates:
    if isValidDictionary(c):
      return c

  # --------------------------------------------------------------------------
  # 3. Системный кэш.
  # --------------------------------------------------------------------------

  let cachePath =
    getAppCacheDictPath()

  if isValidDictionary(cachePath):
    return cachePath

  # --------------------------------------------------------------------------
  # 4. Если найден старый словарь, удаляем его.
  #
  # Это позволяет автоматически заменить старый формат новым.
  # --------------------------------------------------------------------------

  if fileExists(cachePath):
    echo(
      "[nimorphy] Обнаружен словарь старого или повреждённого формата: ",
      cachePath
    )

    try:
      removeFile(cachePath)
    except CatchableError:
      discard

  # --------------------------------------------------------------------------
  # 5. Скачиваем актуальный словарь.
  # --------------------------------------------------------------------------

  result =
    downloadPrebuiltDict(
      DefaultDictReleaseUrl,
      cachePath
    )
