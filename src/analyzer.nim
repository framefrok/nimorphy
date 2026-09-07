
## src/analyzer.nim
##
## Морфологический анализ русского языка:
## 1. Полноценная лемматизация глаголов (и всех остальных частей речи).
## 2. Прилагательные (умный выбор И.п., ед.ч., м.р. как леммы).
## 3. Местоимения (NPRO).
## 4. Числительные (NUMR).
## 5. Все времена/лица/наклонения глаголов (со Smart Tense Redirection).
## 6. Множественное число.
## 7. Возвратные глаголы (автоматическое разрешение суффиксов -ся/-сь).
## 8. Полная генерация парадигмы (forms).
## 9. Нормализация (normalize).
## 10. Качественный bestParse() (взвешенная система пенальти).
## 11. Расширенный unknown-word predictor (Phase 1: суффиксы, Phase 2: прототипы).
## 12. Максимальная производительность (без лишних аллокаций).
##
## Совместимость:
##   Nim 2.2.10

import std/[algorithm, strutils, tables]

import tag
import trie
import dict
import dict_manager


type
  ## Один морфологический разбор словоформы.
  Parse* = object
    word*: string
    tag*: Tag
    normalForm*: string
    score*: float32
    paradigmId*: uint32
    formIdx*: uint16

  ## Морфологический анализатор.
  MorphAnalyzer* = ref object
    dict*: MorphDict


# ============================================================================
# Russian lowercase
# ============================================================================

proc toLowerRu*(s: string): string =
  ## Быстрое преобразование ASCII и русской кириллицы в нижний регистр.
  result = newString(s.len)
  var i = 0
  var o = 0

  while i < s.len:
    let b1 = cast[uint8](s[i])

    if b1 < 128'u8:
      if b1 >= 65'u8 and b1 <= 90'u8:
        result[o] = cast[char](b1 + 32'u8)
      else:
        result[o] = s[i]
      inc i; inc o
      continue

    if b1 == 0xD0'u8 and i + 1 < s.len:
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
      
      i += 2; o += 2
      continue

    result[o] = s[i]
    inc i; inc o

  result.setLen(o)


# ============================================================================
# Analyzer lifecycle
# ============================================================================

proc newMorphAnalyzer*(dictPath: string = ""): MorphAnalyzer =
  let resolved = resolveDictPath(dictPath)
  result = MorphAnalyzer(dict: loadDict(resolved))

proc close*(analyzer: MorphAnalyzer) =
  if analyzer != nil and analyzer.dict != nil:
    analyzer.dict.close()


# ============================================================================
# Core Extraction & Grammar Helpers
# ============================================================================

template hasGrammemeOpt*(gSet: GrammemeSet, tag1, tag2: untyped): bool =
  when declared(tag1): tag1 in gSet
  elif declared(tag2): tag2 in gSet
  else: false

proc extractStem(dict: MorphDict, word: string, payload: WordPayload): string {.inline.} =
  let rule = dict.getRule(payload.paradigmId, payload.formIdx)
  let suffix = dict.getString(rule.suffixOffset)
  let prefix = dict.getString(rule.prefixOffset)

  if prefix.len > word.len or suffix.len > word.len: return word
  if prefix.len > 0 and not word.startsWith(prefix): return word
  if suffix.len > 0 and not word.endsWith(suffix): return word

  let stemLen = word.len - prefix.len - suffix.len
  if stemLen < 0: return word
  if stemLen == 0: return ""
  return word[prefix.len .. prefix.len + stemLen - 1]

proc getCaseFamily*(grammemes: GrammemeSet): int {.inline.} =
  if nomn in grammemes: return 1
  if gent in grammemes or gen1 in grammemes or gen2 in grammemes: return 2
  if datv in grammemes: return 3
  if accs in grammemes or acc2 in grammemes: return 4
  if ablt in grammemes: return 5
  if loct in grammemes or loc1 in grammemes or loc2 in grammemes: return 6
  if voct in grammemes: return 7
  return 0

proc getNumberFamily*(grammemes: GrammemeSet): int {.inline.} =
  if sing in grammemes: return 1
  if plur in grammemes: return 2
  return 0

proc getGenderFamily*(grammemes: GrammemeSet): int {.inline.} =
  if masc in grammemes: return 1
  if femn in grammemes: return 2
  if neut in grammemes: return 3
  if ms_f in grammemes: return 4
  return 0

proc getCaseRank*(grammemes: GrammemeSet): int {.inline.} =
  if gent in grammemes or accs in grammemes or loct in grammemes: return 0
  if gen1 in grammemes or acc2 in grammemes or loc1 in grammemes: return 1
  if gen2 in grammemes or loc2 in grammemes: return 2
  return 0


# ============================================================================
# Strict Grammar Matching
# ============================================================================

proc isSubsetWithFamilies*(subset, superset: GrammemeSet): bool =
  let subCase = getCaseFamily(subset)
  if subCase != 0 and subCase != getCaseFamily(superset): return false

  let subNum = getNumberFamily(subset)
  if subNum != 0 and subNum != getNumberFamily(superset): return false

  let subGen = getGenderFamily(subset)
  let supGen = getGenderFamily(superset)
  if subGen != 0 and subGen != supGen:
    if not (supGen == 4 and (subGen == 1 or subGen == 2)):
      return false

  let handled = CaseGrammemes + NumberGrammemes + GenderGrammemes
  let strictSubset = subset - handled
  let strictSuperset = superset - handled
  
  return strictSubset <= strictSuperset


# ============================================================================
# Canonical Lemma & Scoring
# ============================================================================

proc resolveCanonicalLemma*(dict: MorphDict, normWord: string, pld: WordPayload): tuple[lemma: string, formIdx: uint16] =
  let paradigmLen = dict.getParadigmLength(pld.paradigmId)
  var bestIdx: uint16 = 0
  var bestScore = -1

  for idx in 0 ..< paradigmLen:
    let uidx = idx.uint16
    let rule = dict.getRule(pld.paradigmId, uidx)
    let g = dict.tags[rule.tagId].grammemes
    
    var score = 0
    if INFN in g: score = 100
    elif NOUN in g and nomn in g and sing in g: score = 100
    elif ADJF in g and nomn in g and sing in g and masc in g: score = 100
    elif ADJS in g and masc in g and sing in g: score = 90
    elif PRTF in g and nomn in g and sing in g and masc in g: score = 80
    elif NUMR in g and nomn in g: score = 100
    elif NPRO in g and nomn in g: score = 100
    elif NOUN in g and nomn in g and plur in g: score = 50

    if score > bestScore:
      bestScore = score
      bestIdx = uidx

  let stem = dict.extractStem(normWord, pld)
  let targetRule = dict.getRule(pld.paradigmId, bestIdx)
  let prefix = dict.getString(targetRule.prefixOffset)
  let suffix = dict.getString(targetRule.suffixOffset)
  
  result = (prefix & stem & suffix, bestIdx)


proc calcParseScore*(tag: Tag, isPrediction: bool, suffixLen: int): float32 =
  let g = tag.grammemes
  var score = 1.0'f32

  # Приоритеты основных частей речи
  if NOUN in g or VERB in g or INFN in g: score += 0.2'f32
  elif ADJF in g or ADJS in g or PRTF in g or PRTS in g: score += 0.1'f32
  elif NPRO in g or NUMR in g: score += 0.2'f32
  elif PREP in g or CONJ in g or PRCL in g: score += 0.3'f32

  if hasGrammemeOpt(g, Surn, gSurn): score -= 0.3'f32
  if hasGrammemeOpt(g, Name, gName): score -= 0.2'f32
  if hasGrammemeOpt(g, Patr, gPatr): score -= 0.3'f32
  if hasGrammemeOpt(g, Geox, gGeox): score -= 0.2'f32
  if hasGrammemeOpt(g, Orgn, gOrgn): score -= 0.2'f32
  if hasGrammemeOpt(g, Infr, gInfr) or hasGrammemeOpt(g, Slng, gSlng) or hasGrammemeOpt(g, Arch, gArch): 
    score -= 0.3'f32
  if hasGrammemeOpt(g, Abbr, gAbbr) or hasGrammemeOpt(g, Init, gInit): 
    score -= 0.5'f32

  let cr = getCaseRank(g)
  if cr > 0: score -= 0.05'f32 * cr.float32

  if isPrediction:
    score -= 0.6'f32
    score += min(suffixLen.float32 * 0.05'f32, 0.4'f32)

  return max(0.01'f32, score)


# ============================================================================
# Inflection
# ============================================================================

proc inflect*(analyzer: MorphAnalyzer, p: Parse, requiredGrammemes: GrammemeSet): Parse =
  if analyzer == nil or analyzer.dict == nil or p.word.len == 0: return p
  
  let dict = analyzer.dict
  let paradigmLen = dict.getParadigmLength(p.paradigmId)
  if paradigmLen <= 0: return p

  var req = requiredGrammemes

  if INFN in p.tag.grammemes:
    let hasVerbFeatures = (req * (TenseGrammemes + PersonGrammemes + MoodGrammemes)).len > 0
    let hasRequestedPos = (req * PosGrammemes).len > 0
    if hasVerbFeatures and not hasRequestedPos:
      req.incl(VERB)

  # Smart Tense: Корректировка времени для совершенного/несовершенного вида.
  if pres in req or futr in req:
    if perf in p.tag.grammemes:
      req.excl(pres)
      req.incl(futr)
    elif impf in p.tag.grammemes:
      req.excl(futr)
      req.incl(pres)

  var preserved = p.tag.grammemes
  if (req * PosGrammemes).len > 0: preserved = preserved - PosGrammemes
  if (req * AnimacyGrammemes).len > 0: preserved = preserved - AnimacyGrammemes
  if (req * GenderGrammemes).len > 0: preserved = preserved - GenderGrammemes
  if (req * NumberGrammemes).len > 0: preserved = preserved - NumberGrammemes
  if (req * CaseGrammemes).len > 0: preserved = preserved - CaseGrammemes
  if (req * AspectGrammemes).len > 0: preserved = preserved - AspectGrammemes
  if (req * TransitivityGrammemes).len > 0: preserved = preserved - TransitivityGrammemes
  if (req * PersonGrammemes).len > 0: preserved = preserved - PersonGrammemes
  if (req * TenseGrammemes).len > 0: preserved = preserved - TenseGrammemes
  if (req * MoodGrammemes).len > 0: preserved = preserved - MoodGrammemes
  if (req * VoiceGrammemes).len > 0: preserved = preserved - VoiceGrammemes

  let target = preserved + req

  type RankTuple = tuple[valid: int, exact: int, intersect: int, negExtra: int, negCaseRank: int]
  var bestIdx = -1
  var bestRank: RankTuple = (valid: 0, exact: -1, intersect: -1, negExtra: -9999, negCaseRank: -9999)

  for idx in 0 ..< paradigmLen:
    let uidx = idx.uint16
    let rule = dict.getRule(p.paradigmId, uidx)
    let formTag = dict.tags[rule.tagId]

    if not isSubsetWithFamilies(req, formTag.grammemes):
      continue

    let isExact = if formTag.grammemes == target: 1 else: 0
    let intersectSize = (formTag.grammemes * target).len
    let extraSize = (formTag.grammemes - target).len
    let caseRank = getCaseRank(formTag.grammemes)

    let rank: RankTuple = (valid: 1, exact: isExact, intersect: intersectSize, negExtra: -extraSize, negCaseRank: -caseRank)

    if rank > bestRank:
      bestRank = rank
      bestIdx = idx.int

  if bestIdx < 0: return p 

  let normWord = toLowerRu(p.word)
  let sourcePayload = WordPayload(paradigmId: p.paradigmId, formIdx: p.formIdx)
  let stem = dict.extractStem(normWord, sourcePayload)

  let targetRule = dict.getRule(p.paradigmId, bestIdx.uint16)
  let prefix = dict.getString(targetRule.prefixOffset)
  let suffix = dict.getString(targetRule.suffixOffset)

  var newWord = newStringOfCap(prefix.len + stem.len + suffix.len)
  newWord.add(prefix)
  newWord.add(stem)
  newWord.add(suffix)

  result = Parse(
    word: newWord,
    tag: dict.tags[targetRule.tagId],
    normalForm: p.normalForm,
    score: p.score,
    paradigmId: p.paradigmId,
    formIdx: bestIdx.uint16
  )

proc inflect*(p: Parse, analyzer: MorphAnalyzer, requiredGrammemes: GrammemeSet): Parse {.inline.} =
  analyzer.inflect(p, requiredGrammemes)


# ============================================================================
# Agreement & Advanced Helpers
# ============================================================================

proc agreeWithNumber*(analyzer: MorphAnalyzer, p: Parse, num: int): Parse =
  let absNum = if num < 0: -num else: num
  let rem100 = absNum mod 100
  let rem10 = absNum mod 10

  var targetCase: Grammeme
  var targetNumber: Grammeme
  let isPltm = hasGrammemeOpt(p.tag.grammemes, Pltm, gPltm)

  if rem100 >= 11 and rem100 <= 14:
    targetCase = gent
    targetNumber = plur
  elif rem10 == 1:
    targetCase = nomn
    targetNumber = if isPltm: plur else: sing
  elif rem10 >= 2 and rem10 <= 4:
    targetCase = gent
    targetNumber = if isPltm: plur else: sing
  else:
    targetCase = gent
    targetNumber = plur

  analyzer.inflect(p, {targetCase, targetNumber})

proc agreeWithNumber*(p: Parse, analyzer: MorphAnalyzer, num: int): Parse {.inline.} =
  analyzer.agreeWithNumber(p, num)

proc normalize*(analyzer: MorphAnalyzer, p: Parse): Parse =
  if analyzer == nil or analyzer.dict == nil: return p
  
  let normWord = toLowerRu(p.word)
  let payload = WordPayload(paradigmId: p.paradigmId, formIdx: p.formIdx)
  let (lemmaStr, bestIdx) = resolveCanonicalLemma(analyzer.dict, normWord, payload)

  let targetRule = analyzer.dict.getRule(p.paradigmId, bestIdx)
  result = Parse(
    word: lemmaStr,
    tag: analyzer.dict.tags[targetRule.tagId],
    normalForm: lemmaStr,
    score: p.score,
    paradigmId: p.paradigmId,
    formIdx: bestIdx
  )

proc hasGrammeme*(p: Parse, g: Grammeme): bool {.inline.} = g in p.tag.grammemes
proc hasPos*(p: Parse, pos: Grammeme): bool {.inline.} = pos in p.tag.grammemes

proc canInflect*(analyzer: MorphAnalyzer, p: Parse, req: GrammemeSet): bool =
  let inf = analyzer.inflect(p, req)
  isSubsetWithFamilies(req, inf.tag.grammemes)

proc forms*(analyzer: MorphAnalyzer, p: Parse): seq[Parse] =
  result = @[]
  if analyzer == nil or analyzer.dict == nil: return
  
  let dict = analyzer.dict
  let paradigmLen = dict.getParadigmLength(p.paradigmId)
  if paradigmLen == 0: return

  let normWord = toLowerRu(p.word)
  let payload = WordPayload(paradigmId: p.paradigmId, formIdx: p.formIdx)
  let stem = dict.extractStem(normWord, payload)

  for idx in 0 ..< paradigmLen:
    let uidx = idx.uint16
    let rule = dict.getRule(p.paradigmId, uidx)
    let prefix = dict.getString(rule.prefixOffset)
    let suffix = dict.getString(rule.suffixOffset)
    let tag = dict.tags[rule.tagId]
    
    result.add(Parse(
      word: prefix & stem & suffix,
      tag: tag,
      normalForm: p.normalForm,
      score: p.score,
      paradigmId: p.paradigmId,
      formIdx: uidx
    ))


# ============================================================================
# Predictor & Main Parser
# ============================================================================

proc predictUnknown(analyzer: MorphAnalyzer, normWord, rawWord: string): seq[Parse] =
  result = @[]
  let dict = analyzer.dict
  let wordLen = normWord.len
  if wordLen < 3: return

  # Phase 1: Smart Suffix Scanning
  type PredCand = object
    paradigmId: uint32
    formIdx: uint16
    suffixLen: int

  var candidates = newSeqOfCap[PredCand](16)
  var candByPar = initTable[uint32, int]()
  let paradigmCount = int(dict.header.paradigmCount)
  let lastChar = normWord[normWord.high]

  for paradigmId in 0 ..< paradigmCount:
    let paradigmLen = dict.getParadigmLength(paradigmId.uint32)
    if paradigmLen == 0: continue

    var bestRuleIdx = -1
    var bestSuffixLen = 0

    for idx in 0 ..< int(paradigmLen):
      let uidx = idx.uint16
      let rule = dict.getRule(paradigmId.uint32, uidx)
      let suffix = dict.getString(rule.suffixOffset)
      
      if suffix.len < 2 or suffix.len > wordLen: continue
      if suffix[suffix.high] != lastChar: continue
      
      if normWord.endsWith(suffix):
        if suffix.len > bestSuffixLen:
          bestSuffixLen = suffix.len
          bestRuleIdx = idx

    if bestRuleIdx >= 0:
      let cand = PredCand(paradigmId: paradigmId.uint32, formIdx: bestRuleIdx.uint16, suffixLen: bestSuffixLen)
      if candByPar.hasKey(paradigmId.uint32):
        let pos = candByPar[paradigmId.uint32]
        if bestSuffixLen > candidates[pos].suffixLen:
          candidates[pos] = cand
      else:
        candByPar[paradigmId.uint32] = candidates.len
        candidates.add(cand)

  candidates.sort(proc(a, b: PredCand): int = cmp(b.suffixLen, a.suffixLen))

  let limit = min(candidates.len, 8)
  for i in 0 ..< limit:
    let cand = candidates[i]
    let payload = WordPayload(paradigmId: cand.paradigmId, formIdx: cand.formIdx)
    let (lemma, _) = resolveCanonicalLemma(dict, normWord, payload)
    let rule = dict.getRule(cand.paradigmId, cand.formIdx)
    let formTag = dict.tags[rule.tagId]

    result.add(Parse(
      word: rawWord,
      tag: formTag,
      normalForm: lemma,
      score: calcParseScore(formTag, true, cand.suffixLen),
      paradigmId: cand.paradigmId,
      formIdx: cand.formIdx
    ))

  # Phase 2: Prototype Fallback
  if result.len == 0:
    var protos: seq[string] = @[]
    if normWord.endsWith("а") or normWord.endsWith("я"): protos = @["вода", "баня", "пуля"]
    elif normWord.endsWith("о") or normWord.endsWith("е"): protos = @["окно", "море", "солнце"]
    elif normWord.endsWith("ь"): protos = @["тень", "день", "мышь"]
    elif normWord.endsWith("й"): protos = @["герой", "большой", "синий"]
    elif normWord.endsWith("и") or normWord.endsWith("ы"): protos = @["столы", "коты", "сани"]
    elif normWord.endsWith("у") or normWord.endsWith("ю"): protos = @["воду", "пулю"]
    elif normWord.endsWith("ом") or normWord.endsWith("ем"): protos = @["домом", "морем"]
    else: protos = @["стол", "завод", "кот"]

    for proto in protos:
      let nIdx = exactMatch(dict.nodes, 0, proto)
      if nIdx != -1:
        let n = dict.nodes[nIdx]
        
        # Исправление ошибки итератора
        let pldCount = int(n.payloadCount)
        let pldStart = int(n.payloadStart)
        
        for i in 0 ..< pldCount:
          let pld = dict.payloads[pldStart + i]
          let rule = dict.getRule(pld.paradigmId, pld.formIdx)
          let sfx = dict.getString(rule.suffixOffset)
          
          if normWord.endsWith(sfx):
            let (lemma, _) = resolveCanonicalLemma(dict, normWord, pld)
            let formTag = dict.tags[rule.tagId]
            
            var isDup = false
            for r in result:
              if r.paradigmId == pld.paradigmId and r.formIdx == pld.formIdx:
                isDup = true
                break
            
            if not isDup:
              result.add(Parse(
                word: rawWord,
                tag: formTag,
                normalForm: lemma,
                score: 0.15'f32,
                paradigmId: pld.paradigmId,
                formIdx: pld.formIdx
              ))


proc parse*(analyzer: MorphAnalyzer, word: string): seq[Parse] =
  result = @[]
  if analyzer == nil or analyzer.dict == nil or word.len == 0: return

  let normWord = toLowerRu(word)
  let dict = analyzer.dict
  let nodeIdx = exactMatch(dict.nodes, 0, normWord)

  if nodeIdx != -1:
    let node = dict.nodes[nodeIdx]
    let pldCount = int(node.payloadCount)
    let pldStart = int(node.payloadStart)

    if pldCount > 0:
      for i in 0 ..< pldCount:
        let payload = dict.payloads[pldStart + i]
        let (lemma, _) = resolveCanonicalLemma(dict, normWord, payload)
        let currentRule = dict.getRule(payload.paradigmId, payload.formIdx)
        let formTag = dict.tags[currentRule.tagId]
        
        result.add(Parse(
          word: word,
          tag: formTag,
          normalForm: lemma,
          score: calcParseScore(formTag, false, 0),
          paradigmId: payload.paradigmId,
          formIdx: payload.formIdx
        ))
      
      result.sort(proc(a, b: Parse): int = cmp(b.score, a.score))
      return

  result = analyzer.predictUnknown(normWord, word)
  result.sort(proc(a, b: Parse): int = cmp(b.score, a.score))

proc bestParse*(analyzer: MorphAnalyzer, word: string): Parse =
  let parses = analyzer.parse(word)
  if parses.len > 0:
    result = parses[0]


# ============================================================================
# String representation
# ============================================================================

proc `$`*(p: Parse): string =
  "Parse(word: \"" & p.word & "\", lemma: \"" & p.normalForm & 
  "\", tag: [" & $p.tag & "], score: " & $p.score & ")"
