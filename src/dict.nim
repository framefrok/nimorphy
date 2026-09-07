## src/dict.nim
## Спецификация заголовка и загрузка компактного mmap словаря

import std/strutils

import tag, trie, mmap

const
  DictMagic* = "NIMORPH2"
  CurrentFormatVersion* = 2.uint32

type
  DictHeader* {.packed.} = object
    magic*: array[8, char]
    version*: uint32
    reserved*: uint32

    tagCount*: uint32
    stringPoolSize*: uint32
    ruleCount*: uint32
    paradigmCount*: uint32
    payloadCount*: uint32
    nodeCount*: uint32

    tagOffset*: uint64
    stringPoolOffset*: uint64
    ruleOffset*: uint64
    paradigmIndexOffset*: uint64
    payloadOffset*: uint64
    nodeOffset*: uint64

  ParadigmRule* {.packed.} = object
    suffixOffset*: uint32
    tagId*: uint16
    prefixOffset*: uint32

  WordPayload* {.packed.} = object
    paradigmId*: uint32
    formIdx*: uint16
    reserved*: uint16

  MorphDict* = ref object
    mmapFile*: MmapFile
    header*: ptr DictHeader

    tags*: ptr UncheckedArray[Tag]
    stringPool*: ptr UncheckedArray[char]
    rules*: ptr UncheckedArray[ParadigmRule]
    paradigmOffsets*: ptr UncheckedArray[uint32]
    payloads*: ptr UncheckedArray[WordPayload]
    nodes*: ptr UncheckedArray[TrieNode]

static:
  assert sizeof(ParadigmRule) == 10
  assert sizeof(WordPayload) == 8
  assert sizeof(DictHeader) == 88

proc getString*(dict: MorphDict, offset: uint32): string {.inline.} =
  if dict == nil or dict.header == nil:
    return ""

  if offset == 0:
    return ""

  let poolSize = uint64(dict.header.stringPoolSize)
  let off = uint64(offset)

  if off >= poolSize:
    return ""

  let remaining = int(poolSize - off)
  let base = int(offset)

  var len = 0

  while len < remaining:
    if dict.stringPool[base + len] == '\0':
      break

    inc len

  if len >= remaining:
    return ""

  if len == 0:
    return ""

  result = newString(len)

  copyMem(
    addr result[0],
    addr dict.stringPool[base],
    len
  )

proc getParadigmLength*(
  dict: MorphDict,
  paradigmId: uint32
): int {.inline.} =
  if dict == nil or dict.header == nil:
    return 0

  if uint64(paradigmId) >=
     uint64(dict.header.paradigmCount):
    return 0

  let start =
    uint64(
      dict.paradigmOffsets[paradigmId]
    )

  let nextStart =
    uint64(
      dict.paradigmOffsets[paradigmId + 1]
    )

  if nextStart < start:
    return 0

  let ruleCount =
    uint64(
      dict.header.ruleCount
    )

  if start > ruleCount or
     nextStart > ruleCount:
    return 0

  int(nextStart - start)

proc getRule*(
  dict: MorphDict,
  paradigmId: uint32,
  formIdx: uint16
): ParadigmRule {.inline.} =
  if dict == nil or dict.header == nil:
    return ParadigmRule()

  if uint64(paradigmId) >=
     uint64(dict.header.paradigmCount):
    return ParadigmRule()

  let start =
    dict.paradigmOffsets[paradigmId]

  let nextStart =
    dict.paradigmOffsets[paradigmId + 1]

  if nextStart < start:
    return ParadigmRule()

  let count =
    nextStart - start

  if uint64(formIdx) >=
     uint64(count):
    return ParadigmRule()

  dict.rules[
    int(start) + int(formIdx)
  ]

proc buildLemma*(
  dict: MorphDict,
  word: string,
  payload: WordPayload
): (string, Tag) =
  if dict == nil or dict.header == nil:
    return (word, Tag())

  let paradigmLen =
    dict.getParadigmLength(
      payload.paradigmId
    )

  if paradigmLen <= 0 or
     int(payload.formIdx) >= paradigmLen:
    return (word, Tag())

  let curRule =
    dict.getRule(
      payload.paradigmId,
      payload.formIdx
    )

  let curSuffix =
    dict.getString(
      curRule.suffixOffset
    )

  let curPrefix =
    dict.getString(
      curRule.prefixOffset
    )

  if curPrefix.len > word.len or
     curSuffix.len > word.len:
    return (word, Tag())

  if curPrefix.len > 0 and
     not word.startsWith(curPrefix):
    return (word, Tag())

  if curSuffix.len > 0 and
     not word.endsWith(curSuffix):
    return (word, Tag())

  let stemLen =
    word.len -
    curPrefix.len -
    curSuffix.len

  if stemLen < 0:
    return (word, Tag())

  let stem =
    if stemLen == 0:
      ""
    else:
      word[
        curPrefix.len ..
        curPrefix.len + stemLen - 1
      ]

  let lemmaRule =
    dict.getRule(
      payload.paradigmId,
      0
    )

  let lemmaSuffix =
    dict.getString(
      lemmaRule.suffixOffset
    )

  let lemmaPrefix =
    dict.getString(
      lemmaRule.prefixOffset
    )

  let lemmaTag =
    if uint64(lemmaRule.tagId) <
       uint64(dict.header.tagCount):
      dict.tags[lemmaRule.tagId]
    else:
      Tag()

  var lemma =
    newStringOfCap(
      lemmaPrefix.len +
      stem.len +
      lemmaSuffix.len
    )

  lemma.add(lemmaPrefix)
  lemma.add(stem)
  lemma.add(lemmaSuffix)

  (lemma, lemmaTag)

proc validateStringOffset(
  pool: ptr UncheckedArray[char],
  poolSize: uint64,
  offset: uint32,
  sectionName: string
) =
  if offset == 0:
    return

  let off = uint64(offset)

  if off >= poolSize:
    raise newException(
      ValueError,
      "Corrupted dictionary: " &
      sectionName &
      " string offset out of bounds"
    )

  var pos = off

  while pos < poolSize:
    if pool[int(pos)] == '\0':
      return

    inc pos

  raise newException(
    ValueError,
    "Corrupted dictionary: " &
    sectionName &
    " string is not NUL-terminated"
  )

proc validateSection(
  offset,
  count,
  elementSize,
  fileSize: uint64,
  name: string
) =
  if offset > fileSize:
    raise newException(
      ValueError,
      "Corrupted dictionary: " &
      name &
      " offset out of bounds"
    )

  if elementSize == 0:
    return

  let available =
    fileSize - offset

  if count >
     available div elementSize:
    raise newException(
      ValueError,
      "Corrupted dictionary: " &
      name &
      " section exceeds file size"
    )

proc validateDictionary(
  dict: MorphDict
) =
  let h = dict.header
  let fileSize =
    uint64(dict.mmapFile.size)

  if h.nodeCount == 0:
    raise newException(
      ValueError,
      "Corrupted dictionary: empty trie"
    )

  if h.paradigmCount == 0:
    raise newException(
      ValueError,
      "Corrupted dictionary: empty paradigm table"
    )

  if h.tagCount == 0:
    raise newException(
      ValueError,
      "Corrupted dictionary: empty tag table"
    )

  validateSection(
    h.tagOffset,
    uint64(h.tagCount),
    uint64(sizeof(Tag)),
    fileSize,
    "tags"
  )

  validateSection(
    h.stringPoolOffset,
    uint64(h.stringPoolSize),
    1'u64,
    fileSize,
    "string pool"
  )

  validateSection(
    h.ruleOffset,
    uint64(h.ruleCount),
    uint64(sizeof(ParadigmRule)),
    fileSize,
    "rules"
  )

  validateSection(
    h.paradigmIndexOffset,
    uint64(h.paradigmCount) + 1'u64,
    uint64(sizeof(uint32)),
    fileSize,
    "paradigm index"
  )

  validateSection(
    h.payloadOffset,
    uint64(h.payloadCount),
    uint64(sizeof(WordPayload)),
    fileSize,
    "payloads"
  )

  validateSection(
    h.nodeOffset,
    uint64(h.nodeCount),
    uint64(sizeof(TrieNode)),
    fileSize,
    "trie"
  )

  let headerEnd =
    uint64(sizeof(DictHeader))

  if h.tagOffset < headerEnd or
     h.stringPoolOffset < h.tagOffset or
     h.ruleOffset < h.stringPoolOffset or
     h.paradigmIndexOffset < h.ruleOffset or
     h.payloadOffset < h.paradigmIndexOffset or
     h.nodeOffset < h.payloadOffset:
    raise newException(
      ValueError,
      "Corrupted dictionary: invalid section order"
    )

  if dict.paradigmOffsets[0] != 0:
    raise newException(
      ValueError,
      "Corrupted dictionary: first paradigm offset must be zero"
    )

  for i in 0 ..< int(h.paradigmCount):
    let a =
      uint64(
        dict.paradigmOffsets[i]
      )

    let b =
      uint64(
        dict.paradigmOffsets[i + 1]
      )

    if a > b or
       b > uint64(h.ruleCount):
      raise newException(
        ValueError,
        "Corrupted dictionary: invalid paradigm offsets"
      )

  if dict.paradigmOffsets[h.paradigmCount] !=
     h.ruleCount:
    raise newException(
      ValueError,
      "Corrupted dictionary: final paradigm offset mismatch"
    )

  for i in 0 ..< int(h.ruleCount):
    let rule =
      dict.rules[i]

    if uint64(rule.tagId) >=
       uint64(h.tagCount):
      raise newException(
        ValueError,
        "Corrupted dictionary: rule tagId out of bounds"
      )

    validateStringOffset(
      dict.stringPool,
      uint64(h.stringPoolSize),
      rule.suffixOffset,
      "suffix"
    )

    validateStringOffset(
      dict.stringPool,
      uint64(h.stringPoolSize),
      rule.prefixOffset,
      "prefix"
    )

  for i in 0 ..< int(h.payloadCount):
    let payload =
      dict.payloads[i]

    if uint64(payload.paradigmId) >=
       uint64(h.paradigmCount):
      raise newException(
        ValueError,
        "Corrupted dictionary: payload paradigmId out of bounds"
      )

    let paradigmLen =
      dict.getParadigmLength(
        payload.paradigmId
      )

    if int(payload.formIdx) >=
       paradigmLen:
      raise newException(
        ValueError,
        "Corrupted dictionary: payload formIdx out of bounds"
      )

  for i in 0 ..< int(h.nodeCount):
    let node =
      dict.nodes[i]

    let childStart =
      uint64(node.childStart)

    let childCount =
      uint64(node.childCount)

    let payloadStart =
      uint64(node.payloadStart)

    let payloadCount =
      uint64(node.payloadCount)

    if childStart >
       uint64(h.nodeCount) or
       childCount >
       uint64(h.nodeCount) - childStart:
      raise newException(
        ValueError,
        "Corrupted dictionary: trie child range out of bounds"
      )

    if payloadStart >
       uint64(h.payloadCount) or
       payloadCount >
       uint64(h.payloadCount) - payloadStart:
      raise newException(
        ValueError,
        "Corrupted dictionary: trie payload range out of bounds"
      )

proc loadDict*(
  path: string
): MorphDict =
  var m =
    openMmapFile(path)

  if m.size <
     sizeof(DictHeader):
    m.close()

    raise newException(
      ValueError,
      "Corrupted dictionary file (too small)"
    )

  let header =
    cast[ptr DictHeader](
      m.address
    )

  var magicStr =
    newString(8)

  copyMem(
    addr magicStr[0],
    addr header.magic[0],
    8
  )

  if magicStr != DictMagic:
    m.close()

    raise newException(
      ValueError,
      "Invalid dictionary format: expected " &
      DictMagic
    )

  if header.version !=
     CurrentFormatVersion:
    m.close()

    raise newException(
      ValueError,
      "Unsupported dictionary version"
    )

  let fileSize =
    uint64(m.size)

  if header.stringPoolSize == 0:
    m.close()

    raise newException(
      ValueError,
      "Corrupted dictionary: empty string pool"
    )

  let base =
    cast[uint](
      m.address
    )

  var d =
    MorphDict(
      mmapFile: m,
      header: header,

      tags:
        cast[
          ptr UncheckedArray[Tag]
        ](
          base +
          header.tagOffset
        ),

      stringPool:
        cast[
          ptr UncheckedArray[char]
        ](
          base +
          header.stringPoolOffset
        ),

      rules:
        cast[
          ptr UncheckedArray[ParadigmRule]
        ](
          base +
          header.ruleOffset
        ),

      paradigmOffsets:
        cast[
          ptr UncheckedArray[uint32]
        ](
          base +
          header.paradigmIndexOffset
        ),

      payloads:
        cast[
          ptr UncheckedArray[WordPayload]
        ](
          base +
          header.payloadOffset
        ),

      nodes:
        cast[
          ptr UncheckedArray[TrieNode]
        ](
          base +
          header.nodeOffset
        )
    )

  try:
    validateSection(
      header.tagOffset,
      uint64(header.tagCount),
      uint64(sizeof(Tag)),
      fileSize,
      "tags"
    )

    validateSection(
      header.stringPoolOffset,
      uint64(header.stringPoolSize),
      1'u64,
      fileSize,
      "string pool"
    )

    validateSection(
      header.ruleOffset,
      uint64(header.ruleCount),
      uint64(sizeof(ParadigmRule)),
      fileSize,
      "rules"
    )

    validateSection(
      header.paradigmIndexOffset,
      uint64(header.paradigmCount) + 1'u64,
      uint64(sizeof(uint32)),
      fileSize,
      "paradigm index"
    )

    validateSection(
      header.payloadOffset,
      uint64(header.payloadCount),
      uint64(sizeof(WordPayload)),
      fileSize,
      "payloads"
    )

    validateSection(
      header.nodeOffset,
      uint64(header.nodeCount),
      uint64(sizeof(TrieNode)),
      fileSize,
      "trie"
    )

    validateDictionary(d)

  except CatchableError:
    d.mmapFile.close()
    raise

  result = d

proc close*(
  dict: MorphDict
) =
  if dict != nil:
    dict.mmapFile.close()

