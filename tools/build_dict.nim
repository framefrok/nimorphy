## tools/build_dict.nim
## Автономный сборщик бинарного словаря с автоскачиванием из зеркал и распаковкой

import std/[parsexml, streams, tables, strutils, times, os, osproc, algorithm]
import ../src/[tag, trie, dict]

type
  RawRule = object
    suffix: string
    tagId: uint16
    prefix: string

  RawForm = object
    text: string
    tag: Tag

  BuilderNode = ref object
    charByte: uint8
    isTerminal: bool
    payloads: seq[WordPayload]
    children: seq[BuilderNode]

proc getLcp(a, b: string): int {.inline.} =
  var i = 0
  let m = min(a.len, b.len)
  while i < m and a[i] == b[i]:
    inc i
  return i

proc addString(pool: var string, strMap: var Table[string, uint32], s: string): uint32 =
  if s.len == 0: return 0
  if strMap.hasKey(s): return strMap[s]
  let offset = pool.len.uint32
  pool.add(s)
  pool.add('\0')
  strMap[s] = offset
  return offset

proc addTag(tags: var seq[Tag], tagMap: var Table[Tag, uint16], t: Tag): uint16 =
  if tagMap.hasKey(t): return tagMap[t]
  let id = tags.len.uint16
  tags.add(t)
  tagMap[t] = id
  return id

proc insertWord(root: BuilderNode, word: string, payload: WordPayload) =
  var curr = root
  for i in 0 ..< word.len:
    let b = cast[uint8](word[i])
    var nextNode: BuilderNode = nil
    for child in curr.children:
      if child.charByte == b:
        nextNode = child
        break
    if nextNode == nil:
      nextNode = BuilderNode(charByte: b)
      curr.children.add(nextNode)
    curr = nextNode
  curr.isTerminal = true
  curr.payloads.add(payload)

proc flattenTrie(root: BuilderNode, outNodes: var seq[TrieNode], outPayloads: var seq[WordPayload]) =
  var queue: seq[BuilderNode] = @[root]
  outNodes.add(TrieNode(charByte: 0))

  var head = 0
  while head < queue.len:
    let currBuilder = queue[head]
    let currFlatIdx = head
    inc head

    if currBuilder.isTerminal and currBuilder.payloads.len > 0:
      outNodes[currFlatIdx].flags = outNodes[currFlatIdx].flags or FlagTerminal
      outNodes[currFlatIdx].payloadStart = outPayloads.len.uint32
      outNodes[currFlatIdx].payloadCount = currBuilder.payloads.len.uint16
      for p in currBuilder.payloads:
        outPayloads.add(p)

    currBuilder.children.sort(proc(x, y: BuilderNode): int = cmp(x.charByte, y.charByte))
    let childCount = currBuilder.children.len
    if childCount > 0:
      let childStart = outNodes.len.uint32
      outNodes[currFlatIdx].childStart = childStart
      outNodes[currFlatIdx].childCount = childCount.uint8

      for child in currBuilder.children:
        outNodes.add(TrieNode(charByte: child.charByte))
        queue.add(child)

proc ensureDictionary(xmlPath: string) =
  if fileExists(xmlPath) and getFileSize(xmlPath) > 10_000_000:
    return

  echo "Файл словаря '", xmlPath, "' не найден или пуст."
  echo "Запуск автозагрузки (с поддержкой зеркал)..."

  let normalizedPath = xmlPath.replace("\\", "\\\\")
  let pyScript = """
import urllib.request, bz2, os, sys

urls = [
    'https://web.archive.org/web/20231010000000id_/http://opencorpora.org/files/export/dict/dict.opcorpora.xml.bz2',
    'https://web.archive.org/web/20240101000000id_/http://opencorpora.org/files/export/dict/dict.opcorpora.xml.bz2',
    'http://opencorpora.org/files/export/dict/dict.opcorpora.xml.bz2',
    'https://opencorpora.org/files/export/dict/dict.opcorpora.xml.bz2'
]
target = '""" & normalizedPath & """'

success = False
for url in urls:
    print(f"Подключение к: {url[:70]}...")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
    try:
        with urllib.request.urlopen(req, timeout=40) as resp:
            total = int(resp.headers.get('Content-Length', 0))
            decomp = bz2.BZ2Decompressor()
            downloaded = 0
            with open(target, 'wb') as out_f:
                while True:
                    chunk = resp.read(1024 * 1024)
                    if not chunk:
                        break
                    downloaded += len(chunk)
                    out_f.write(decomp.decompress(chunk))
                    if total > 0:
                        pct = int(downloaded * 100 / total)
                        mb = downloaded // (1024 * 1024)
                        print(f"\rЗагрузка и распаковка: {pct}% ({mb} МБ скачано)", end="", flush=True)
                    else:
                        mb = downloaded // (1024 * 1024)
                        print(f"\rСкачано {mb} МБ...", end="", flush=True)
        print("\nСловарь успешно скачан и распакован в " + target)
        success = True
        break
    except Exception as e:
        print(f"\nИсточник недоступен ({e}), пробуем следующее зеркало...")

if not success:
    print("\nНе удалось скачать словарь ни с одного источника.")
    sys.exit(1)
"""
  let helperPath = "download_dict_tmp.py"
  writeFile(helperPath, pyScript)
  defer:
    if fileExists(helperPath):
      removeFile(helperPath)

  var exitCode = execCmd("python " & helperPath)
  if exitCode != 0:
    exitCode = execCmd("py " & helperPath)
    if exitCode != 0:
      quit("Ошибка: не удалось скачать словарь.")

  if not fileExists(xmlPath) or getFileSize(xmlPath) < 10_000_000:
    quit("Ошибка: файл " & xmlPath & " не был сформирован.")

proc buildDictionary*(xmlPath, outBinPath: string, limitLemmata: int = 0) =
  ensureDictionary(xmlPath)

  echo "=== nimorphy: компиляция бинарного словаря ==="
  echo "Источник: ", xmlPath
  echo "Выходной файл: ", outBinPath

  var xmlStream = newFileStream(xmlPath, fmRead)
  if xmlStream == nil:
    quit("Ошибка: не удалось открыть XML-файл: " & xmlPath)

  var xml: XmlParser
  xml.open(xmlStream, xmlPath)

  var tags: seq[Tag] = @[]
  var tagMap = initTable[Tag, uint16]()
  var stringPool: string = "\0"
  var stringMap = initTable[string, uint32]()
  stringMap[""] = 0

  var rawRules: seq[ParadigmRule] = @[]
  var paradigmOffsets: seq[uint32] = @[0]
  var paradigmMap = initTable[seq[RawRule], uint32]()
  let builderRoot = BuilderNode(charByte: 0)

  var curElem = ""
  var inL = false
  var inF = false
  var curLemmaTags: GrammemeSet = {}
  var curFormText = ""
  var curFormTags: GrammemeSet = {}
  var curForms: seq[RawForm] = @[]

  var lemmaCount = 0
  let startTime = cpuTime()

  echo "Парсинг XML-дампа..."

  while true:
    xml.next()
    case xml.kind
    of xmlElementOpen, xmlElementStart:
      curElem = xml.elementName
      case curElem
      of "lemma":
        curForms.setLen(0)
        curLemmaTags = {}
      of "l":
        inL = true
      of "f":
        inF = true
        curFormText = ""
        curFormTags = {}
      else: discard

    of xmlAttribute:
      if curElem == "l" and xml.attrKey == "t":
        discard
      elif curElem == "f" and xml.attrKey == "t":
        curFormText = xml.attrValue.toLowerAscii()
      elif curElem == "g" and xml.attrKey == "v":
        try:
          let g = parseGrammeme(xml.attrValue)
          if inL:
            curLemmaTags.incl(g)
          elif inF:
            curFormTags.incl(g)
        except ValueError:
          discard

    of xmlElementEnd:
      case xml.elementName
      of "l":
        inL = false
      of "f":
        inF = false
        if curFormText.len > 0:
          let fullTag = initTag(curLemmaTags + curFormTags)
          curForms.add(RawForm(text: curFormText, tag: fullTag))
      of "lemma":
        if curForms.len > 0:
          inc lemmaCount

          var lcpLen = curForms[0].text.len
          for i in 1 ..< curForms.len:
            lcpLen = min(lcpLen, getLcp(curForms[0].text, curForms[i].text))
          
          var pRules: seq[RawRule] = newSeqOfCap[RawRule](curForms.len)
          for f in curForms:
            let suffix = f.text[lcpLen .. ^1]
            let tagId = addTag(tags, tagMap, f.tag)
            pRules.add(RawRule(suffix: suffix, tagId: tagId, prefix: ""))

          var paradigmId: uint32 = 0
          if paradigmMap.hasKey(pRules):
            paradigmId = paradigmMap[pRules]
          else:
            paradigmId = (paradigmOffsets.len - 1).uint32
            paradigmMap[pRules] = paradigmId
            for r in pRules:
              let sOff = addString(stringPool, stringMap, r.suffix)
              let pOff = addString(stringPool, stringMap, r.prefix)
              rawRules.add(ParadigmRule(
                suffixOffset: sOff,
                tagId: r.tagId,
                prefixOffset: pOff.uint16
              ))
            paradigmOffsets.add(rawRules.len.uint32)

          for formIdx in 0 ..< curForms.len:
            let payload = WordPayload(
              paradigmId: paradigmId,
              formIdx: formIdx.uint16
            )
            insertWord(builderRoot, curForms[formIdx].text, payload)

          if lemmaCount mod 50000 == 0:
            echo "Обработано лемм: ", lemmaCount, " (", (cpuTime() - startTime).formatFloat(ffDecimal, 1), " сек.)"

          if limitLemmata > 0 and lemmaCount >= limitLemmata:
            break
      else: discard

    of xmlEof:
      break
    else: discard

  xml.close()
  echo "Парсинг завершен за ", (cpuTime() - startTime).formatFloat(ffDecimal, 2), " сек."
  echo "Уникальных лемм: ", lemmaCount
  echo "Уникальных тегов: ", tags.len
  echo "Уникальных парадигм: ", paradigmOffsets.len - 1

  echo "Линеаризация префиксного дерева (Trie)..."
  let trieStart = cpuTime()
  var flatNodes: seq[TrieNode] = @[]
  var flatPayloads: seq[WordPayload] = @[]
  flattenTrie(builderRoot, flatNodes, flatPayloads)
  echo "Trie скомпилирован за ", (cpuTime() - trieStart).formatFloat(ffDecimal, 2), " сек."
  echo "Всего узлов дерева: ", flatNodes.len

  echo "Запись бинарного словаря: ", outBinPath
  var outFile = open(outBinPath, fmWrite)
  
  var header = DictHeader(
    version: CurrentFormatVersion,
    tagCount: tags.len.uint32,
    stringPoolSize: stringPool.len.uint32,
    ruleCount: rawRules.len.uint32,
    paradigmCount: (paradigmOffsets.len - 1).uint32,
    payloadCount: flatPayloads.len.uint32,
    nodeCount: flatNodes.len.uint32
  )
  copyMem(addr header.magic[0], cstring(DictMagic), 8)

  proc align16(f: File) =
    let pos = f.getFilePos()
    let rem = pos mod 16
    if rem != 0:
      let pad = 16 - rem
      let zeroes: array[16, uint8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      discard f.writeBuffer(unsafeAddr zeroes[0], pad)

  discard outFile.writeBuffer(addr header, sizeof(header))

  outFile.align16()
  header.tagOffset = outFile.getFilePos().uint64
  if tags.len > 0:
    discard outFile.writeBuffer(addr tags[0], tags.len * sizeof(Tag))

  outFile.align16()
  header.stringPoolOffset = outFile.getFilePos().uint64
  if stringPool.len > 0:
    discard outFile.writeBuffer(addr stringPool[0], stringPool.len)

  outFile.align16()
  header.ruleOffset = outFile.getFilePos().uint64
  if rawRules.len > 0:
    discard outFile.writeBuffer(addr rawRules[0], rawRules.len * sizeof(ParadigmRule))

  outFile.align16()
  header.paradigmIndexOffset = outFile.getFilePos().uint64
  if paradigmOffsets.len > 0:
    discard outFile.writeBuffer(addr paradigmOffsets[0], paradigmOffsets.len * sizeof(uint32))

  outFile.align16()
  header.payloadOffset = outFile.getFilePos().uint64
  if flatPayloads.len > 0:
    discard outFile.writeBuffer(addr flatPayloads[0], flatPayloads.len * sizeof(WordPayload))

  outFile.align16()
  header.nodeOffset = outFile.getFilePos().uint64
  if flatNodes.len > 0:
    discard outFile.writeBuffer(addr flatNodes[0], flatNodes.len * sizeof(TrieNode))

  outFile.setFilePos(0)
  discard outFile.writeBuffer(addr header, sizeof(header))
  outFile.close()

  let totalSize = getFileSize(outBinPath)
  echo "Успешно! Размер словаря: ", (totalSize.float / (1024.0 * 1024.0)).formatFloat(ffDecimal, 2), " МБ."

when isMainModule:
  let args = commandLineParams()
  var xmlPath = "dict.opcorpora.xml"
  var binPath = "dict.bin"
  var limit = 0

  if args.len >= 1 and not args[0].startsWith("--"):
    xmlPath = args[0]
  if args.len >= 2 and not args[1].startsWith("--"):
    binPath = args[1]

  for a in args:
    if a.startsWith("--limit:"):
      limit = parseInt(a[8 .. ^1])

  buildDictionary(xmlPath, binPath, limit)