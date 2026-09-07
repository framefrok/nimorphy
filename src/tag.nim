## Модуль представления грамматических признаков (граммем) и тегов OpenCorpora.
## Тег хранится в виде компактной битовой маски (16 байт), оптимизированной для ARC/ORC.

import std/[strutils, hashes]

type
  Grammeme* = enum
    # --- Части речи (POST / Part of Speech) ---
    NOUN   ## Имя существительное
    ADJF   ## Имя прилагательное (полное)
    ADJS   ## Имя прилагательное (краткое)
    COMP   ## Компаратив
    VERB   ## Глагол (личная форма)
    INFN   ## Инфинитив
    PRTF   ## Причастие (полное)
    PRTS   ## Причастие (краткое)
    GRND   ## Деепричастие
    NUMR   ## Числительное
    ADVB   ## Наречие
    NPRO   ## Местоимение-существительное
    PRED   ## Предикатив
    PREP   ## Предлог
    CONJ   ## Союз
    PRCL   ## Частица
    INTJ   ## Междометие

    # --- Одушевленность (Animacy) ---
    anim   ## одушевлённое
    inan   ## неодушевлённое

    # --- Род (Gender) ---
    masc   ## мужской род
    femn   ## женский род
    neut   ## средний род
    ms_f   ## общий род (м/ж)

    # --- Число (Number) ---
    sing   ## единственное число
    plur   ## множественное число

    # --- Падеж (Case) ---
    nomn   ## именительный
    gent   ## родительный
    datv   ## дательный
    accs   ## винительный
    ablt   ## творительный
    loct   ## предложный
    voct   ## звательный
    gen1   ## первый родительный
    gen2   ## второй родительный (частичный)
    acc2   ## второй винительный
    loc1   ## первый предложный
    loc2   ## второй предложный (местный)

    # --- Вид (Aspect) ---
    perf   ## совершенный
    impf   ## несовершенный

    # --- Переходность (Transitivity) ---
    tran   ## переходный
    intr   ## непереходный

    # --- Лицо (Person) ---
    per1   ## 1-е лицо (1per)
    per2   ## 2-е лицо (2per)
    per3   ## 3-е лицо (3per)

    # --- Время (Tense) ---
    pres   ## настоящее
    past   ## прошедшее
    futr   ## будущее

    # --- Наклонение (Mood) ---
    indc   ## изъявительное
    impr   ## повелительное

    # --- Залог (Voice) ---
    actv   ## действительный
    pssv   ## страдательный

    # --- Включенность говорящего (Involvement) ---
    incl   ## говорящий включен (идем)
    excl   ## говорящий не включен (идите)

    # --- Специфические и стилистические теги OpenCorpora ---
    Init   ## Инициал
    Adjx   ## Притяжательное
    Fixd   ## Неизменяемое
    Dist   ## Искажение / опечатка
    Ques   ## Вопросительное
    Dmns   ## Указательное
    Prnt   ## Вводное слово
    V_be   ## Форма глагола "быть"
    V_en   ## Форма на -енный
    V_bi   ## Форма на -быть
    FRed   ## Редуцированная форма
    V_ey   ## Форма на -ей
    V_oy   ## Форма на -ой
    Cmp2   ## Вторая форма компаратива
    V_ej   ## Форма на -ей (деепричастие)
    Anph   ## Анафорическое
    Supr   ## Превосходная степень
    Qual   ## Качественное
    Apro   ## Местоименное
    Anum   ## Порядковое числительное
    Poss   ## Притяжательное местоимение
    Vpre   ## Вариант предлога
    Arch   ## Архаизм
    Erro   ## Грубая ошибка
    Slav   ## Старославянизм
    Coll   ## Разговорное
    Geox   ## Топоним
    Orgn   ## Организация
    Trad   ## Торговая марка
    Subx   ## Субстантивированное слово
    gName  ## Имя собственное (Name)
    gSurn  ## Фамилия (Surn)
    gPatr  ## Отчество (Patr)
    Infr   ## Неформальное
    Slng   ## Сленг

  GrammemeSet* = set[Grammeme]

  Tag* = object
    ## Морфологический тег слова.
    ## Размер структуры ровно 16 байт, полностью хранится на стеке / в регистрах.
    grammemes*: GrammemeSet

# Проверяем на этапе компиляции, что тип Tag максимально компактен
static:
  assert sizeof(Tag) <= 16, "Tag must fit in 16 bytes"

# --- Константные маски категорий для сверхбыстрой классификации ---

const
  PosGrammemes*: GrammemeSet = {NOUN..INTJ}
  AnimacyGrammemes*: GrammemeSet = {anim..inan}
  GenderGrammemes*: GrammemeSet = {masc..ms_f}
  NumberGrammemes*: GrammemeSet = {sing..plur}
  CaseGrammemes*: GrammemeSet = {nomn..loc2}
  AspectGrammemes*: GrammemeSet = {perf..impf}
  TransitivityGrammemes*: GrammemeSet = {tran..intr}
  PersonGrammemes*: GrammemeSet = {per1..per3}
  TenseGrammemes*: GrammemeSet = {pres..futr}
  MoodGrammemes*: GrammemeSet = {indc..impr}
  VoiceGrammemes*: GrammemeSet = {actv..pssv}

# --- Маппинг строковых представлений OpenCorpora <-> Enum ---

proc parseGrammeme*(s: string): Grammeme {.inline.} =
  ## Быстрое преобразование текстовой граммемы OpenCorpora в Grammeme.
  case s
  of "NOUN": NOUN
  of "ADJF": ADJF
  of "ADJS": ADJS
  of "COMP": COMP
  of "VERB": VERB
  of "INFN": INFN
  of "PRTF": PRTF
  of "PRTS": PRTS
  of "GRND": GRND
  of "NUMR": NUMR
  of "ADVB": ADVB
  of "NPRO": NPRO
  of "PRED": PRED
  of "PREP": PREP
  of "CONJ": CONJ
  of "PRCL": PRCL
  of "INTJ": INTJ
  of "anim": anim
  of "inan": inan
  of "masc": masc
  of "femn": femn
  of "neut": neut
  of "ms-f": ms_f
  of "sing": sing
  of "plur": plur
  of "nomn": nomn
  of "gent": gent
  of "datv": datv
  of "accs": accs
  of "ablt": ablt
  of "loct": loct
  of "voct": voct
  of "gen1": gen1
  of "gen2": gen2
  of "acc2": acc2
  of "loc1": loc1
  of "loc2": loc2
  of "perf": perf
  of "impf": impf
  of "tran": tran
  of "intr": intr
  of "1per": per1
  of "2per": per2
  of "3per": per3
  of "pres": pres
  of "past": past
  of "futr": futr
  of "indc": indc
  of "impr": impr
  of "actv": actv
  of "pssv": pssv
  of "incl": incl
  of "excl": excl
  of "Init": Init
  of "Adjx": Adjx
  of "Fixd": Fixd
  of "Dist": Dist
  of "Ques": Ques
  of "Dmns": Dmns
  of "Prnt": Prnt
  of "V-be": V_be
  of "V-en": V_en
  of "V-bi": V_bi
  of "FRed": FRed
  of "V-ey": V_ey
  of "V-oy": V_oy
  of "Cmp2": Cmp2
  of "V-ej": V_ej
  of "Anph": Anph
  of "Supr": Supr
  of "Qual": Qual
  of "Apro": Apro
  of "Anum": Anum
  of "Poss": Poss
  of "Vpre": Vpre
  of "Arch": Arch
  of "Erro": Erro
  of "Slav": Slav
  of "Coll": Coll
  of "Geox": Geox
  of "Orgn": Orgn
  of "Trad": Trad
  of "Subx": Subx
  of "Name": gName
  of "Surn": gSurn
  of "Patr": gPatr
  of "Infr": Infr
  of "Slng": Slng
  else:
    raise newException(ValueError, "Unknown OpenCorpora grammeme: " & s)

proc toOpenCorporaStr*(g: Grammeme): string =
  ## Преобразование Grammeme обратно в формат OpenCorpora.
  case g
  of ms_f: "ms-f"
  of per1: "1per"
  of per2: "2per"
  of per3: "3per"
  of V_be: "V-be"
  of V_en: "V-en"
  of V_bi: "V-bi"
  of V_ey: "V-ey"
  of V_oy: "V-oy"
  of V_ej: "V-ej"
  of gName: "Name"
  of gSurn: "Surn"
  of gPatr: "Patr"
  else: $g

# --- Конструкторы и базовые операции для Tag ---

proc initTag*(grammemes: GrammemeSet): Tag {.inline.} =
  Tag(grammemes: grammemes)

proc parseTag*(rawTag: string): Tag =
  ## Парсит строку OpenCorpora вида: "VERB,perf,intr plur,past,indc"
  ## или "NOUN,anim,masc sing,nomn".
  var res: GrammemeSet = {}
  var i = 0
  let L = rawTag.len
  while i < L:
    # Пропускаем разделители (запятые, пробелы)
    while i < L and (rawTag[i] == ' ' or rawTag[i] == ','):
      inc i
    if i >= L: break
    
    let start = i
    while i < L and rawTag[i] != ' ' and rawTag[i] != ',':
      inc i
    
    let token = rawTag[start ..< i]
    if token.len > 0:
      res.incl(parseGrammeme(token))
      
  result = Tag(grammemes: res)

# --- Операции над тегами ---

proc contains*(tag: Tag, g: Grammeme): bool {.inline.} =
  ## Проверка наличия граммемы в теге: `g in tag`
  g in tag.grammemes

proc contains*(tag: Tag, subset: GrammemeSet): bool {.inline.} =
  ## Проверка наличия всех граммем из subset в теге: `subset <= tag`
  subset <= tag.grammemes

proc `+`*(tag: Tag, g: Grammeme): Tag {.inline.} =
  Tag(grammemes: tag.grammemes + {g})

proc `-`*(tag: Tag, g: Grammeme): Tag {.inline.} =
  Tag(grammemes: tag.grammemes - {g})

proc `+`*(tag: Tag, gs: GrammemeSet): Tag {.inline.} =
  Tag(grammemes: tag.grammemes + gs)

proc `-`*(tag: Tag, gs: GrammemeSet): Tag {.inline.} =
  Tag(grammemes: tag.grammemes - gs)

proc `==`*(a, b: Tag): bool {.inline.} =
  a.grammemes == b.grammemes

proc hash*(tag: Tag): Hash {.inline.} =
  hash(tag.grammemes)

# --- Аксессоры категорий ---

proc pos*(tag: Tag): GrammemeSet {.inline.} =
  ## Извлекает часть речи из тега
  tag.grammemes * PosGrammemes

proc caseGrammeme*(tag: Tag): GrammemeSet {.inline.} =
  ## Извлекает падежные граммемы
  tag.grammemes * CaseGrammemes

proc number*(tag: Tag): GrammemeSet {.inline.} =
  ## Извлекает граммемы числа
  tag.grammemes * NumberGrammemes

proc gender*(tag: Tag): GrammemeSet {.inline.} =
  ## Извлекает граммемы рода
  tag.grammemes * GenderGrammemes

# --- Строковое представление ---

proc `$`*(tag: Tag): string =
  ## Форматирует тег в канонический формат OpenCorpora:
  ## POS,anim,gn... case,number...
  var parts: seq[string] = @[]
  
  # 1. Часть речи всегда первая
  let p = tag.pos
  for g in PosGrammemes:
    if g in p:
      parts.add(toOpenCorporaStr(g))
      break

  # 2. Все остальные граммемы
  for g in Grammeme:
    if g in tag.grammemes and g notin PosGrammemes:
      parts.add(toOpenCorporaStr(g))
      
  result = parts.join(",")
  
when isMainModule:
  import std/times

  # 1. Корректность парсинга
  let t1 = parseTag("NOUN,anim,masc sing,nomn")
  assert NOUN in t1
  assert anim in t1
  assert masc in t1
  assert sing in t1
  assert nomn in t1
  assert neut notin t1
  assert VERB notin t1

  # 2. Подмножества граммем
  let query: GrammemeSet = {masc, nomn}
  assert query <= t1.grammemes

  # 3. Модификация
  let t2 = t1 - {nomn} + {ablt}
  assert ablt in t2
  assert nomn notin t2

  # 4. Бенчмарк: проверка скорости на 10 000 000 операций
  echo "Тест корректности пройден!"
  echo "Запуск бенчмарка битовых операций..."
  
  let start = cpuTime()
  var count = 0
  for _ in 1 .. 10_000_000:
    if query <= t1.grammemes:
      inc count
  let elapsed = cpuTime() - start
  
  echo "10,000,000 проверок тегов выполнены за: ", elapsed, " сек."
  echo "Скорость: ", (10_000_000.0 / elapsed / 1_000_000.0), " млн операций/сек."