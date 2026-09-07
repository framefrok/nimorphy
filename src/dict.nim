## nimorphy/dict.nim
## Спецификация заголовка и загрузка компактного mmap словаря

import tag, trie, mmap

const
  DictMagic* = "NIMORPH1"
  CurrentFormatVersion* = 1.uint32

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
    prefixOffset*: uint16

  WordPayload* {.packed.} = object
    paradigmId*: uint32
    formIdx*: uint16
    reserved: uint16

  MorphDict* = ref object
    mmapFile*: MmapFile
    header*: ptr DictHeader
    
    tags*: ptr UncheckedArray[Tag]
    stringPool*: ptr UncheckedArray[char]
    rules*: ptr UncheckedArray[ParadigmRule]
    paradigmOffsets*: ptr UncheckedArray[uint32]
    payloads*: ptr UncheckedArray[WordPayload]
    nodes*: ptr UncheckedArray[TrieNode]

proc getString*(dict: MorphDict, offset: uint32): string {.inline.} =
  ## Извлекает нуль-терминированную строку из пула строк через cstring ($p)
  if offset == 0:
    return ""
  let p = cast[cstring](addr dict.stringPool[offset])
  result = $p

proc getRule*(dict: MorphDict, paradigmId: uint32, formIdx: uint16): ParadigmRule {.inline.} =
  let baseRuleIdx = dict.paradigmOffsets[paradigmId]
  dict.rules[int(baseRuleIdx) + int(formIdx)]

proc getParadigmLength*(dict: MorphDict, paradigmId: uint32): int {.inline.} =
  let start = dict.paradigmOffsets[paradigmId]
  let nextStart = dict.paradigmOffsets[paradigmId + 1]
  int(nextStart - start)

proc buildLemma*(dict: MorphDict, word: string, payload: WordPayload): (string, Tag) =
  let curRule = dict.getRule(payload.paradigmId, payload.formIdx)
  let curSuffix = dict.getString(curRule.suffixOffset)
  let curPrefix = dict.getString(curRule.prefixOffset.uint32)

  let stemLen = word.len - curSuffix.len - curPrefix.len
  let stemStart = curPrefix.len

  # Защита от выхода за границы строки при непредвиденных формах
  let stem = if stemLen < 0 or stemStart + stemLen > word.len:
               word
             else:
               word[stemStart ..< stemStart + stemLen]

  let lemmaRule = dict.getRule(payload.paradigmId, 0)
  let lemmaSuffix = dict.getString(lemmaRule.suffixOffset)
  let lemmaPrefix = dict.getString(lemmaRule.prefixOffset.uint32)
  let lemmaTag = dict.tags[lemmaRule.tagId]

  var lemma = newStringOfCap(lemmaPrefix.len + stem.len + lemmaSuffix.len)
  lemma.add(lemmaPrefix)
  lemma.add(stem)
  lemma.add(lemmaSuffix)

  return (lemma, lemmaTag)

proc loadDict*(path: string): MorphDict =
  var m = openMmapFile(path)
  if m.size < sizeof(DictHeader):
    m.close()
    raise newException(ValueError, "Corrupted dictionary file (too small)")

  let header = cast[ptr DictHeader](m.address)
  
  var magicStr: string = newString(8)
  copyMem(addr magicStr[0], addr header.magic[0], 8)
  if magicStr != DictMagic:
    m.close()
    raise newException(ValueError, "Invalid dictionary format: expected " & DictMagic)
    
  if header.version != CurrentFormatVersion:
    m.close()
    raise newException(ValueError, "Unsupported dictionary version")

  let fileSize = m.size.uint64
  if header.tagOffset > fileSize or
     header.stringPoolOffset > fileSize or
     header.ruleOffset > fileSize or
     header.paradigmIndexOffset > fileSize or
     header.payloadOffset > fileSize or
     header.nodeOffset > fileSize:
    m.close()
    raise newException(ValueError, "Corrupted dictionary file (section offsets out of bounds)")

  let base = cast[uint](m.address)
  
  result = MorphDict(
    mmapFile: m,
    header: header,
    tags: cast[ptr UncheckedArray[Tag]](base + header.tagOffset),
    stringPool: cast[ptr UncheckedArray[char]](base + header.stringPoolOffset),
    rules: cast[ptr UncheckedArray[ParadigmRule]](base + header.ruleOffset),
    paradigmOffsets: cast[ptr UncheckedArray[uint32]](base + header.paradigmIndexOffset),
    payloads: cast[ptr UncheckedArray[WordPayload]](base + header.payloadOffset),
    nodes: cast[ptr UncheckedArray[TrieNode]](base + header.nodeOffset)
  )

proc close*(dict: MorphDict) =
  if dict != nil:
    dict.mmapFile.close()