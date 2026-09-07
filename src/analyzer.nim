## nimorphy/analyzer.nim
## Морфологический анализ, словоизменение (inflect), согласование с числами
## и интеграция с автозагрузчиком словарей (Smart Dictionary Manager)

import tag, trie, dict, dict_manager

type
  Parse* = object
    word*: string         ## Текущее слово (в запрошенной форме)
    tag*: Tag             ## Морфологический тег формы
    normalForm*: string   ## Нормальная форма (лемма)
    score*: float32       ## Оценка вероятности разбора
    paradigmId*: uint32   ## ID парадигмы
    formIdx*: uint16      ## Индекс формы в парадигме

  MorphAnalyzer* = ref object
    dict*: MorphDict

# --- Побайтовый Lowercase для UTF-8 кириллицы ---

proc toLowerRu*(s: string): string =
  result = newString(s.len)
  var i = 0
  var o = 0
  let L = s.len
  while i < L:
    let b1 = cast[uint8](s[i])
    if b1 < 128:
      if b1 >= cast[uint8]('A') and b1 <= cast[uint8]('Z'):
        result[o] = cast[char](b1 + 32)
      else:
        result[o] = s[i]
      inc i
      inc o
    elif b1 == 0xD0 and i + 1 < L:
      let b2 = cast[uint8](s[i + 1])
      if b2 == 0x81: # 'Ё' -> 'ё'
        result[o] = cast[char](0xD1)
        result[o + 1] = cast[char](0x91)
      elif b2 >= 0x90 and b2 <= 0x9F: # 'А'..'П'
        result[o] = cast[char](0xD0)
        result[o + 1] = cast[char](b2 + 0x20)
      elif b2 >= 0xA0 and b2 <= 0xAF: # 'Р'..'Я'
        result[o] = cast[char](0xD1)
        result[o + 1] = cast[char](b2 - 0x20)
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

# --- Инициализация и освобождение (с поддержкой автозагрузки) ---

proc newMorphAnalyzer*(dictPath: string = ""): MorphAnalyzer =
  ## Создает экземпляр анализатора.
  ## Если dictPath не передан, словарь ищется локально, затем в системном кэше,
  ## а при отсутствии — автоматически скачивается из GitHub Releases.
  let resolved = resolveDictPath(dictPath)
  result = MorphAnalyzer(dict: loadDict(resolved))

proc close*(analyzer: MorphAnalyzer) =
  if analyzer != nil and analyzer.dict != nil:
    analyzer.dict.close()

# --- Вспомогательное извлечение основы слова ---

proc extractStem(dict: MorphDict, word: string, payload: WordPayload): string {.inline.} =
  let curRule = dict.getRule(payload.paradigmId, payload.formIdx)
  let curSuffix = dict.getString(curRule.suffixOffset)
  let curPrefix = dict.getString(curRule.prefixOffset.uint32)

  let stemLen = word.len - curSuffix.len - curPrefix.len
  let stemStart = curPrefix.len
  if stemLen < 0 or stemStart + stemLen > word.len:
    return word
  result = word[stemStart ..< stemStart + stemLen]

# --- Словоизменение (Inflect) ---

proc inflect*(analyzer: MorphAnalyzer, p: Parse, requiredGrammemes: GrammemeSet): Parse =
  ## Изменяет форму слова p в соответствии с требуемыми граммемами (например, {ablt}, {plur, gent})
  result = p
  if p.paradigmId == 0 and p.formIdx == 0 and analyzer == nil:
    return

  let dict = analyzer.dict
  let pLen = dict.getParadigmLength(p.paradigmId)
  if pLen <= 0:
    return

  # Формируем целевой тег с сохранением контекста
  var targetGrammemes = p.tag.grammemes
  
  if (requiredGrammemes * CaseGrammemes).len > 0:
    targetGrammemes = targetGrammemes - CaseGrammemes
  if (requiredGrammemes * NumberGrammemes).len > 0:
    targetGrammemes = targetGrammemes - NumberGrammemes
  if (requiredGrammemes * GenderGrammemes).len > 0:
    targetGrammemes = targetGrammemes - GenderGrammemes
  if (requiredGrammemes * TenseGrammemes).len > 0:
    targetGrammemes = targetGrammemes - TenseGrammemes

  targetGrammemes = targetGrammemes + requiredGrammemes

  let payload = WordPayload(paradigmId: p.paradigmId, formIdx: p.formIdx)
  let stem = dict.extractStem(toLowerRu(p.word), payload)

  # Ищем форму в парадигме с максимальным совпадением граммем
  var bestIdx = -1
  var bestScore = -1

  for idx in 0 ..< pLen:
    let rule = dict.getRule(p.paradigmId, idx.uint16)
    let formTag = dict.tags[rule.tagId]

    if requiredGrammemes <= formTag.grammemes:
      let matchCount = (formTag.grammemes * targetGrammemes).len
      if matchCount > bestScore:
        bestScore = matchCount
        bestIdx = idx

  # Если форма найдена — синтезируем новое слово
  if bestIdx >= 0:
    let bestRule = dict.getRule(p.paradigmId, bestIdx.uint16)
    let sfx = dict.getString(bestRule.suffixOffset)
    let pfx = dict.getString(bestRule.prefixOffset.uint32)

    var newWord = newStringOfCap(pfx.len + stem.len + sfx.len)
    newWord.add(pfx)
    newWord.add(stem)
    newWord.add(sfx)

    result = Parse(
      word: newWord,
      tag: dict.tags[bestRule.tagId],
      normalForm: p.normalForm,
      score: p.score,
      paradigmId: p.paradigmId,
      formIdx: bestIdx.uint16
    )

proc inflect*(p: Parse, analyzer: MorphAnalyzer, requiredGrammemes: GrammemeSet): Parse {.inline.} =
  analyzer.inflect(p, requiredGrammemes)

# --- Согласование с числительными (agreeWithNumber) ---

proc agreeWithNumber*(analyzer: MorphAnalyzer, p: Parse, num: int): Parse =
  ## Согласует существительное p с заданным числом num
  let absNum = abs(num)
  let rem100 = absNum mod 100
  let rem10 = absNum mod 10

  var targetCase: Grammeme
  var targetNumber: Grammeme

  if rem100 >= 11 and rem100 <= 14:
    targetCase = gent
    targetNumber = plur
  elif rem10 == 1:
    targetCase = nomn
    targetNumber = sing
  elif rem10 >= 2 and rem10 <= 4:
    targetCase = gent
    targetNumber = sing
  else:
    targetCase = gent
    targetNumber = plur

  analyzer.inflect(p, {targetCase, targetNumber})

proc agreeWithNumber*(p: Parse, analyzer: MorphAnalyzer, num: int): Parse {.inline.} =
  analyzer.agreeWithNumber(p, num)

# --- Эвристический анализатор неизвестных слов (Predictor) ---

proc predictUnknown(analyzer: MorphAnalyzer, normWord, rawWord: string): seq[Parse] =
  result = @[]
  let dict = analyzer.dict
  let wordLen = normWord.len
  if wordLen < 4:
    return

  var cutLen = min(10, wordLen - 2)
  if cutLen mod 2 != 0: dec cutLen

  while cutLen >= 4:
    let suffix = normWord[wordLen - cutLen .. ^1]
    let nodeIdx = exactMatch(dict.nodes, 0, suffix)
    if nodeIdx != -1:
      let node = dict.nodes[nodeIdx]
      let pCount = int(node.payloadCount)
      if pCount > 0:
        let payload = dict.payloads[int(node.payloadStart)]
        let rule = dict.getRule(payload.paradigmId, payload.formIdx)
        let formTag = dict.tags[rule.tagId]
        
        let (borrowedLemma, _) = dict.buildLemma(normWord, payload)

        result.add(Parse(
          word: rawWord,
          tag: formTag,
          normalForm: borrowedLemma,
          score: 0.2'f32,
          paradigmId: payload.paradigmId,
          formIdx: payload.formIdx
        ))
        break
    cutLen -= 2

# --- Основной разбор (Parse) ---

proc parse*(analyzer: MorphAnalyzer, word: string): seq[Parse] =
  ## Возвращает список всех вариантов морфологического разбора слова
  result = @[]
  if word.len == 0:
    return

  let normWord = toLowerRu(word)
  let dict = analyzer.dict
  let nodeIdx = exactMatch(dict.nodes, 0, normWord)

  if nodeIdx != -1:
    let node = dict.nodes[nodeIdx]
    let pStart = int(node.payloadStart)
    let pCount = int(node.payloadCount)

    if pCount > 0:
      let uniformScore = 1.0'f32 / pCount.float32

      for i in 0 ..< pCount:
        let payload = dict.payloads[pStart + i]
        let (lemma, _) = dict.buildLemma(normWord, payload)
        let curRule = dict.getRule(payload.paradigmId, payload.formIdx)
        let formTag = dict.tags[curRule.tagId]

        result.add(Parse(
          word: word,
          tag: formTag,
          normalForm: lemma,
          score: uniformScore,
          paradigmId: payload.paradigmId,
          formIdx: payload.formIdx
        ))
  else:
    result = analyzer.predictUnknown(normWord, word)

proc `$`*(p: Parse): string =
  "Parse(word: \"" & p.word & "\", lemma: \"" & p.normalForm & "\", tag: [" & $p.tag & "], score: " & $p.score & ")"