## tools/build_dict.nim
## Автономный сборщик бинарного словаря с объединением связанных лемм OpenCorpora.

import std/[
  strutils,
  tables,
  sets,
  parsexml,
  streams,
  times,
  os,
  osproc,
  algorithm
]

import ../src/[tag, trie, dict]

type
  RawRule = object
    suffix: string
    tagId: uint16
    prefix: string

  StoredForm = object
    text: string
    tagId: uint16

  StoredLemma = object
    forms: seq[StoredForm]
    isMerged: bool

  LinkInfo = object
    fromId: uint32
    toId: uint32
    typeId: uint32

  BuilderNode = object
    charByte: uint8
    payloads: seq[WordPayload]
    children: seq[int32]

# ============================================================================
# UTF-8 lowercase для русского
# ============================================================================

proc toLowerRu(s: string): string =
  result = newString(s.len)

  var i = 0
  var o = 0

  while i < s.len:
    let b1 = cast[uint8](s[i])

    if b1 < 128'u8:
      if b1 >= cast[uint8]('A') and b1 <= cast[uint8]('Z'):
        result[o] = cast[char](b1 + 32'u8)
      else:
        result[o] = s[i]

      inc i
      inc o

    elif b1 == 0xD0'u8 and i + 1 < s.len:
      let b2 = cast[uint8](s[i + 1])

      if b2 == 0x81'u8:
        result[o] = cast[char](0xD1'u8)
        result[o + 1] = cast[char](0x91'u8)

      elif b2 >= 0x90'u8 and b2 <= 0x9F'u8:
        result[o] = cast[char](0xD0'u8)
        result[o + 1] = cast[char](b2 + 0x20'u8)

      elif b2 >= 0xA0'u8 and b2 <= 0xAF'u8:
        result[o] = cast[char](0xD1'u8)
        result[o + 1] = cast[char](b2 - 0x20'u8)

      else:
        result[o] = s[i]
        result[o + 1] = s[i + 1]

      i += 2
      o += 2

    else:
      result[o] = s[i]
      inc i
      inc o

  result.setLen(o)

# ============================================================================
# Вспомогательные функции
# ============================================================================

proc getLcp(a, b: string): int {.inline.} =
  var i = 0
  let m = min(a.len, b.len)

  while i < m and a[i] == b[i]:
    inc i

  i

proc addString(
  pool: var string,
  strMap: var Table[string, uint32],
  s: string
): uint32 =
  if s.len == 0:
    return 0

  if strMap.hasKey(s):
    return strMap[s]

  if uint64(pool.len) > uint64(high(uint32)):
    raise newException(
      IOError,
      "String pool exceeds uint32 offset range"
    )

  let offset = pool.len.uint32

  pool.add(s)
  pool.add('\0')
  strMap[s] = offset

  offset

proc addTag(
  tags: var seq[Tag],
  tagMap: var Table[Tag, uint16],
  t: Tag
): uint16 =
  if tagMap.hasKey(t):
    return tagMap[t]

  if tags.len >= high(uint16).int:
    raise newException(
      IOError,
      "Too many unique tags for uint16 tagId"
    )

  let id = tags.len.uint16

  tags.add(t)
  tagMap[t] = id

  id

# ============================================================================
# Trie builder
# ============================================================================

proc newBuilderNode(charByte: uint8): BuilderNode =
  BuilderNode(
    charByte: charByte,
    payloads: @[],
    children: @[]
  )

proc insertWord(
  nodes: var seq[BuilderNode],
  rootIdx: int32,
  word: string,
  payload: WordPayload
) =
  var curr = rootIdx.int

  for i in 0 ..< word.len:
    let b = cast[uint8](word[i])

    var nextNode = -1
    var insertAt = nodes[curr].children.len

    for j in 0 ..< nodes[curr].children.len:
      let child = nodes[curr].children[j].int
      let childByte = nodes[child].charByte

      if childByte == b:
        nextNode = child
        break

      if childByte > b:
        insertAt = j
        break

    if nextNode < 0:
      nextNode = nodes.len
      nodes.add(newBuilderNode(b))

      if insertAt == nodes[curr].children.len:
        nodes[curr].children.add(nextNode.int32)
      else:
        nodes[curr].children.insert(nextNode.int32, insertAt)

    curr = nextNode

  if nodes[curr].payloads.len >= high(uint16).int:
    raise newException(
      IOError,
      "Too many payloads for one trie node"
    )

  nodes[curr].payloads.add(payload)

proc flattenTrie(
  builder: seq[BuilderNode],
  outNodes: var seq[TrieNode],
  outPayloads: var seq[WordPayload]
) =
  if builder.len == 0:
    return

  var queue = newSeqOfCap[int32](builder.len)
  queue.add(0'i32)

  outNodes = newSeqOfCap[TrieNode](builder.len)
  outPayloads = @[]

  outNodes.add(
    TrieNode(
      charByte: 0
    )
  )

  var head = 0

  while head < queue.len:
    let builderIdx = queue[head].int
    let flatIdx = head

    inc head

    let curr = builder[builderIdx]

    if curr.payloads.len > 0:
      outNodes[flatIdx].flags =
        outNodes[flatIdx].flags or FlagTerminal

      outNodes[flatIdx].payloadStart =
        outPayloads.len.uint32

      outNodes[flatIdx].payloadCount =
        curr.payloads.len.uint16

      for payload in curr.payloads:
        outPayloads.add(payload)

    if curr.children.len == 0:
      continue

    if curr.children.len > high(uint8).int:
      raise newException(
        IOError,
        "Trie node has more than 255 children"
      )

    outNodes[flatIdx].childStart =
      outNodes.len.uint32

    outNodes[flatIdx].childCount =
      curr.children.len.uint8

    for childIdx in curr.children:
      let child = childIdx.int

      outNodes.add(
        TrieNode(
          charByte: builder[child].charByte
        )
      )

      queue.add(childIdx)

# ============================================================================
# Автозагрузка словаря
# ============================================================================

proc ensureDictionary(xmlPath: string) =
  if fileExists(xmlPath) and getFileSize(xmlPath) > 10_000_000:
    return

  echo "Файл словаря '", xmlPath, "' не найден или пуст."
  echo "Запуск автозагрузки (с поддержкой зеркал)..."

  let normalizedPath = xmlPath.replace("\\", "\\\\")

  let pyScript = """
import urllib.request
import bz2
import sys

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

    req = urllib.request.Request(
        url,
        headers={
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        }
    )

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

                        print(
                            f"\rЗагрузка и распаковка: "
                            f"{pct}% ({mb} МБ скачано)",
                            end="",
                            flush=True
                        )
                    else:
                        mb = downloaded // (1024 * 1024)

                        print(
                            f"\rСкачано {mb} МБ...",
                            end="",
                            flush=True
                        )

        print(
            "\nСловарь успешно скачан и распакован в " +
            target
        )

        success = True
        break

    except Exception as e:
        print(
            f"\nИсточник недоступен ({e}), "
            "пробуем следующее зеркало..."
        )

if not success:
    print(
        "\nНе удалось скачать словарь ни с одного источника."
    )
    sys.exit(1)
"""

  let helperPath = "download_dict_tmp.py"

  writeFile(helperPath, pyScript)

  defer:
    if fileExists(helperPath):
      removeFile(helperPath)

  var exitCode = execCmd(
    "python " & helperPath
  )

  if exitCode != 0:
    exitCode = execCmd(
      "py " & helperPath
    )

    if exitCode != 0:
      quit(
        "Ошибка: не удалось скачать словарь."
      )

  if not fileExists(xmlPath) or
     getFileSize(xmlPath) < 10_000_000:

    quit(
      "Ошибка: файл " &
      xmlPath &
      " не был сформирован."
    )

# ============================================================================
# Объединение лемм по OpenCorpora Links
# ============================================================================

const ExcludedLinkTypes = [
  "NAME-PATR",
  "FULL-CONTRACTED",
  "CARDINAL-ORDINAL",
  "ADJF_TEXT-ADJF_NUMBER"
]

proc isExcludedLinkType(name: string): bool =
  for excluded in ExcludedLinkTypes:
    if name == excluded:
      return true

  false

# ============================================================================
# Union-Find
# ============================================================================

proc findRoot(
  parent: var Table[uint32, uint32],
  id: uint32
): uint32 =
  if not parent.hasKey(id):
    parent[id] = id
    return id

  var root = id

  while parent[root] != root:
    root = parent[root]

  var current = id

  while parent[current] != current:
    let next = parent[current]
    parent[current] = root
    current = next

  root

proc formKey(
  form: StoredForm
): string {.inline.} =
  result = newStringOfCap(form.text.len + 8)
  result.add(form.text)
  result.add('\x00')
  result.add($form.tagId)

proc mergeLinkedLemmas(
  lemmaTable: var Table[uint32, StoredLemma],
  lemmaOrder: seq[uint32],
  links: seq[LinkInfo],
  linkTypeNames: Table[uint32, string]
): int =
  var parent = initTable[uint32, uint32]()

  for id in lemmaOrder:
    parent[id] = id

  var acceptedLinks = 0

  for link in links:
    if not linkTypeNames.hasKey(link.typeId):
      continue

    let typeName =
      linkTypeNames[link.typeId]
        .strip()
        .toUpperAscii()

    if isExcludedLinkType(typeName):
      continue

    if not lemmaTable.hasKey(link.fromId):
      continue

    if not lemmaTable.hasKey(link.toId):
      continue

    let fromRoot = findRoot(parent, link.fromId)
    let toRoot = findRoot(parent, link.toId)

    if fromRoot == toRoot:
      continue

    # Аналог move_lexeme(link.to, link.from):
    # корнем становится fromRoot.
    parent[toRoot] = fromRoot

    inc acceptedLinks

  var groupedForms =
    initTable[uint32, seq[StoredForm]]()

  for id in lemmaOrder:
    let root = findRoot(parent, id)

    if not groupedForms.hasKey(root):
      groupedForms[root] = @[]

    for form in lemmaTable[id].forms:
      groupedForms[root].add(form)

  for root, forms in groupedForms:
    var seen = initHashSet[string]()
    var merged = newSeqOfCap[StoredForm](forms.len)

    for form in forms:
      let key = formKey(form)

      if key in seen:
        continue

      seen.incl(key)
      merged.add(form)

    lemmaTable[root].forms = merged

  var groups = 0

  for id in lemmaOrder:
    let root = findRoot(parent, id)

    if root != id:
      lemmaTable[id].isMerged = true
    else:
      lemmaTable[id].isMerged = false

      if lemmaTable[id].forms.len > 0:
        inc groups

  echo "Принято связей: ", acceptedLinks
  echo "Фактически объединено компонентов: ", acceptedLinks
  echo "Конечных лемм: ", groups

  groups

# ============================================================================
# Сборка словаря
# ============================================================================

proc buildDictionary*(
  xmlPath,
  outBinPath: string,
  limitLemmata: int = 0
) =
  ensureDictionary(xmlPath)

  echo "=== nimorphy: компиляция бинарного словаря ==="
  echo "Источник: ", xmlPath
  echo "Выходной файл: ", outBinPath

  var xmlStream = newFileStream(xmlPath, fmRead)

  if xmlStream == nil:
    quit(
      "Ошибка: не удалось открыть XML-файл: " &
      xmlPath
    )

  var xml: XmlParser
  xml.open(xmlStream, xmlPath)

  var tags: seq[Tag] = @[]
  var tagMap = initTable[Tag, uint16]()

  var stringPool = "\0"
  var stringMap = initTable[string, uint32]()
  stringMap[""] = 0

  var lemmaTable =
    initTable[uint32, StoredLemma]()

  var lemmaOrder: seq[uint32] = @[]

  var linkTypeNames =
    initTable[uint32, string]()

  var currentTypeId: uint32 = 0
  var inType = false

  var links: seq[LinkInfo] = @[]

  var curElem = ""
  var curLemmaId: uint32 = 0

  var inL = false
  var inF = false

  var curLemmaTags: GrammemeSet = {}
  var curFormText = ""
  var curFormTags: GrammemeSet = {}
  var curForms: seq[StoredForm] = @[]

  var linkFrom: uint32 = 0
  var linkTo: uint32 = 0
  var linkType: uint32 = 0

  let startTime = cpuTime()

  echo "1/4. Парсинг XML-дампа..."

  while true:
    xml.next()

    case xml.kind

    of xmlElementOpen, xmlElementStart:
      curElem = xml.elementName

      case curElem
      of "lemma":
        curForms.setLen(0)
        curLemmaTags = {}
        curLemmaId = 0

      of "l":
        inL = true

      of "f":
        inF = true
        curFormText = ""
        curFormTags = {}

      of "type":
        currentTypeId = 0
        inType = true

      of "link":
        linkFrom = 0
        linkTo = 0
        linkType = 0

      else:
        discard

    of xmlAttribute:
      if curElem == "lemma" and
         xml.attrKey == "id":

        curLemmaId =
          parseUInt(xml.attrValue).uint32

      elif curElem == "f" and
           xml.attrKey == "t":

        curFormText =
          toLowerRu(xml.attrValue)

      elif curElem == "g" and
           xml.attrKey == "v":

        try:
          let g = parseGrammeme(xml.attrValue)

          if inL:
            curLemmaTags.incl(g)
          elif inF:
            curFormTags.incl(g)

        except ValueError:
          echo(
            "Предупреждение: неизвестная граммема: ",
            xml.attrValue
          )

      elif curElem == "type" and
           xml.attrKey == "id":

        currentTypeId =
          parseUInt(xml.attrValue).uint32

      elif curElem == "link":

        if xml.attrKey == "from":
          linkFrom =
            parseUInt(xml.attrValue).uint32

        elif xml.attrKey == "to":
          linkTo =
            parseUInt(xml.attrValue).uint32

        elif xml.attrKey == "type":
          linkType =
            parseUInt(xml.attrValue).uint32

    of xmlCharData:
      if inType and currentTypeId > 0:
        let name =
          xml.charData
            .strip()
            .toUpperAscii()

        if name.len > 0:
          linkTypeNames[currentTypeId] = name

    of xmlElementEnd:
      case xml.elementName

      of "l":
        inL = false

      of "f":
        inF = false

        if curFormText.len > 0:
          let fullTag =
            initTag(
              curLemmaTags +
              curFormTags
            )

          let tagId =
            addTag(
              tags,
              tagMap,
              fullTag
            )

          curForms.add(
            StoredForm(
              text: curFormText,
              tagId: tagId
            )
          )

      of "type":
        inType = false
        currentTypeId = 0

      of "lemma":
        if curForms.len > 0 and
           curLemmaId > 0:

          lemmaTable[curLemmaId] =
            StoredLemma(
              forms: curForms,
              isMerged: false
            )

          lemmaOrder.add(curLemmaId)

          if limitLemmata > 0 and
             lemmaOrder.len >= limitLemmata:
            break

      of "link":
        if linkFrom > 0 and
           linkTo > 0 and
           linkType > 0:

          links.add(
            LinkInfo(
              fromId: linkFrom,
              toId: linkTo,
              typeId: linkType
            )
          )

      else:
        discard

    of xmlEof:
      break

    else:
      discard

  xml.close()

  echo(
    "Парсинг XML завершен за ",
    (cpuTime() - startTime).formatFloat(ffDecimal, 2),
    " сек."
  )

  echo "Всего лемм в словаре: ", lemmaOrder.len
  echo "Типов связей: ", linkTypeNames.len
  echo "Всего связей: ", links.len

  # ==========================================================================
  # Объединяем связанные леммы
  # ==========================================================================

  echo "Обработка связей OpenCorpora..."

  let mergedGroups =
    mergeLinkedLemmas(
      lemmaTable,
      lemmaOrder,
      links,
      linkTypeNames
    )

  echo "Объединение завершено. Групп: ",
       mergedGroups

  # ==========================================================================
  # Построение парадигм
  # ==========================================================================

  echo "2/4. Построение парадигм и дедупликация правил..."

  var rawRules: seq[ParadigmRule] = @[]
  var paradigmOffsets: seq[uint32] = @[0'u32]

  var paradigmMap =
    initTable[seq[RawRule], uint32]()

  var builderNodes: seq[BuilderNode] = @[]
  builderNodes.add(newBuilderNode(0))

  var activeLemmas = 0

  for lId in lemmaOrder:
    let item = lemmaTable[lId]

    if item.isMerged or
       item.forms.len == 0:
      continue

    inc activeLemmas

    let forms = item.forms

    var lcpLen = forms[0].text.len

    for i in 1 ..< forms.len:
      lcpLen =
        min(
          lcpLen,
          getLcp(
            forms[0].text,
            forms[i].text
          )
        )

    var pRules =
      newSeqOfCap[RawRule](forms.len)

    for f in forms:
      let suffix =
        if lcpLen < f.text.len:
          f.text[lcpLen .. ^1]
        else:
          ""

      pRules.add(
        RawRule(
          suffix: suffix,
          tagId: f.tagId,
          prefix: ""
        )
      )

    var paradigmId: uint32

    if paradigmMap.hasKey(pRules):
      paradigmId =
        paradigmMap[pRules]

    else:
      paradigmId =
        (paradigmOffsets.len - 1).uint32

      paradigmMap[pRules] =
        paradigmId

      for r in pRules:
        let sOff =
          addString(
            stringPool,
            stringMap,
            r.suffix
          )

        let pOff =
          addString(
            stringPool,
            stringMap,
            r.prefix
          )

        rawRules.add(
          ParadigmRule(
            suffixOffset: sOff,
            tagId: r.tagId,
            prefixOffset: pOff
          )
        )

      paradigmOffsets.add(
        rawRules.len.uint32
      )

    for formIdx in 0 ..< forms.len:
      let payload =
        WordPayload(
          paradigmId: paradigmId,
          formIdx: formIdx.uint16
        )

      insertWord(
        builderNodes,
        0,
        forms[formIdx].text,
        payload
      )

  echo "Активных объединенных лемм: ",
       activeLemmas

  echo "Уникальных парадигм: ",
       paradigmOffsets.len - 1

  echo "Уникальных тегов: ",
       tags.len

  # ==========================================================================
  # Trie
  # ==========================================================================

  echo "3/4. Линеаризация префиксного дерева..."

  let trieStart = cpuTime()

  var flatNodes: seq[TrieNode] = @[]
  var flatPayloads: seq[WordPayload] = @[]

  flattenTrie(
    builderNodes,
    flatNodes,
    flatPayloads
  )

  echo(
    "Trie скомпилирован за ",
    (cpuTime() - trieStart).formatFloat(ffDecimal, 2),
    " сек."
  )

  echo "Всего узлов дерева: ",
       flatNodes.len

  # ==========================================================================
  # Бинарный словарь
  # ==========================================================================

  echo "4/4. Запись бинарного словаря: ",
       outBinPath

  var outFile =
    open(
      outBinPath,
      fmWrite
    )

  var header =
    DictHeader(
      version: CurrentFormatVersion,
      tagCount: tags.len.uint32,
      stringPoolSize: stringPool.len.uint32,
      ruleCount: rawRules.len.uint32,
      paradigmCount: (paradigmOffsets.len - 1).uint32,
      payloadCount: flatPayloads.len.uint32,
      nodeCount: flatNodes.len.uint32
    )

  copyMem(
    addr header.magic[0],
    cstring(DictMagic),
    8
  )

  proc align16(f: File) =
    let pos = f.getFilePos()
    let rem = pos mod 16

    if rem != 0:
      let pad = 16 - rem

      let zeroes: array[16, uint8] =
        [
          0, 0, 0, 0,
          0, 0, 0, 0,
          0, 0, 0, 0,
          0, 0, 0, 0
        ]

      discard f.writeBuffer(
        unsafeAddr zeroes[0],
        pad
      )

  # Header
  discard outFile.writeBuffer(
    addr header,
    sizeof(header)
  )

  # Tags
  outFile.align16()

  header.tagOffset =
    outFile.getFilePos().uint64

  if tags.len > 0:
    discard outFile.writeBuffer(
      addr tags[0],
      tags.len * sizeof(Tag)
    )

  # String pool
  outFile.align16()

  header.stringPoolOffset =
    outFile.getFilePos().uint64

  if stringPool.len > 0:
    discard outFile.writeBuffer(
      addr stringPool[0],
      stringPool.len
    )

  # Rules
  outFile.align16()

  header.ruleOffset =
    outFile.getFilePos().uint64

  if rawRules.len > 0:
    discard outFile.writeBuffer(
      addr rawRules[0],
      rawRules.len * sizeof(ParadigmRule)
    )

  # Paradigm index
  outFile.align16()

  header.paradigmIndexOffset =
    outFile.getFilePos().uint64

  discard outFile.writeBuffer(
    addr paradigmOffsets[0],
    paradigmOffsets.len * sizeof(uint32)
  )

  # Payloads
  outFile.align16()

  header.payloadOffset =
    outFile.getFilePos().uint64

  if flatPayloads.len > 0:
    discard outFile.writeBuffer(
      addr flatPayloads[0],
      flatPayloads.len * sizeof(WordPayload)
    )

  # Trie
  outFile.align16()

  header.nodeOffset =
    outFile.getFilePos().uint64

  if flatNodes.len > 0:
    discard outFile.writeBuffer(
      addr flatNodes[0],
      flatNodes.len * sizeof(TrieNode)
    )

  # Обновляем header
  outFile.setFilePos(0)

  discard outFile.writeBuffer(
    addr header,
    sizeof(header)
  )

  outFile.close()

  let totalSize =
    getFileSize(outBinPath)

  echo(
    "Сборка завершена успешно! Размер словаря: ",
    (
      totalSize.float /
      (1024.0 * 1024.0)
    ).formatFloat(ffDecimal, 2),
    " МБ."
  )

# ============================================================================
# CLI
# ============================================================================

when isMainModule:
  let args = commandLineParams()

  var xmlPath = "dict.opcorpora.xml"
  var binPath = "dict.bin"
  var limit = 0

  if args.len >= 1 and
     not args[0].startsWith("--"):
    xmlPath = args[0]

  if args.len >= 2 and
     not args[1].startsWith("--"):
    binPath = args[1]

  for a in args:
    if a.startsWith("--limit:"):
      limit = parseInt(a[8 .. ^1])

  buildDictionary(
    xmlPath,
    binPath,
    limit
  )
