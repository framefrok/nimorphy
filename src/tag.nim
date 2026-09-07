
## tag.nim
## Модуль представления грамматических признаков (граммем) и тегов OpenCorpora.
## Тег хранится в виде компактной битовой маски.

import std/[strutils, hashes]

type
  Grammeme* = enum
    # ==========================================================================
    # Части речи
    # ==========================================================================

    NOUN
    ADJF
    ADJS
    COMP
    VERB
    INFN
    PRTF
    PRTS
    GRND
    NUMR
    ADVB
    NPRO
    PRED
    PREP
    CONJ
    PRCL
    INTJ

    # ==========================================================================
    # Одушевленность
    # ==========================================================================

    anim
    inan

    # ==========================================================================
    # Род
    # ==========================================================================

    masc
    femn
    neut
    ms_f

    # ==========================================================================
    # Число
    # ==========================================================================

    sing
    plur

    # ==========================================================================
    # Падеж
    # ==========================================================================

    nomn
    gent
    datv
    accs
    ablt
    loct
    voct
    gen1
    gen2
    acc2
    loc1
    loc2

    # ==========================================================================
    # Вид
    # ==========================================================================

    perf
    impf

    # ==========================================================================
    # Переходность
    # ==========================================================================

    tran
    intr

    # ==========================================================================
    # Лицо
    # ==========================================================================

    per1
    per2
    per3

    # ==========================================================================
    # Время
    # ==========================================================================

    pres
    past
    futr

    # ==========================================================================
    # Наклонение
    # ==========================================================================

    indc
    impr

    # ==========================================================================
    # Залог
    # ==========================================================================

    actv
    pssv

    # ==========================================================================
    # Включенность говорящего
    # ==========================================================================

    incl
    excl

    # ==========================================================================
    # Специальные OpenCorpora
    # ==========================================================================

    Init
    Adjx
    Fixd
    Dist
    Ques
    Dmns
    Prnt

    V_be
    V_en
    V_bi
    FRed
    V_ey
    V_oy
    Cmp2
    V_ej
    V_ie
    V_sh

    Sgtm
    Pltm

    GNdr
    Inmx
    Abbr
    Coun

    Impe
    Fimp
    Prdx
    Litr
    Hypo
    Impx
    Af_p

    Anph
    Supr
    Qual
    Apro
    Anum
    Poss
    Vpre
    Arch
    Erro
    Slav
    Coll
    Geox
    Orgn
    Trad
    Subx

    gName
    gSurn
    gPatr

    Infr
    Slng

  GrammemeSet* = set[Grammeme]

  Tag* = object
    grammemes*: GrammemeSet

static:
  assert sizeof(Tag) <= 16, "Tag must fit in 16 bytes"

# ============================================================================
# Категории
# ============================================================================

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

# ============================================================================
# OpenCorpora -> enum
# ============================================================================

proc parseGrammeme*(
  s: string
): Grammeme {.inline.} =
  case s

  # --------------------------------------------------------------------------
  # POS
  # --------------------------------------------------------------------------

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

  # --------------------------------------------------------------------------
  # Animacy
  # --------------------------------------------------------------------------

  of "anim": anim
  of "inan": inan

  # --------------------------------------------------------------------------
  # Gender
  # --------------------------------------------------------------------------

  of "masc": masc
  of "femn": femn
  of "neut": neut

  # В разных источниках встречаются оба варианта.
  of "ms-f": ms_f
  of "Ms-f": ms_f

  # --------------------------------------------------------------------------
  # Number
  # --------------------------------------------------------------------------

  of "sing": sing
  of "plur": plur

  # --------------------------------------------------------------------------
  # Case
  # --------------------------------------------------------------------------

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

  # --------------------------------------------------------------------------
  # Aspect
  # --------------------------------------------------------------------------

  of "perf": perf
  of "impf": impf

  # --------------------------------------------------------------------------
  # Transitivity
  # --------------------------------------------------------------------------

  of "tran": tran
  of "intr": intr

  # --------------------------------------------------------------------------
  # Person
  # --------------------------------------------------------------------------

  of "1per": per1
  of "2per": per2
  of "3per": per3

  # --------------------------------------------------------------------------
  # Tense
  # --------------------------------------------------------------------------

  of "pres": pres
  of "past": past
  of "futr": futr

  # --------------------------------------------------------------------------
  # Mood
  # --------------------------------------------------------------------------

  of "indc": indc
  of "impr": impr

  # --------------------------------------------------------------------------
  # Voice
  # --------------------------------------------------------------------------

  of "actv": actv
  of "pssv": pssv

  # --------------------------------------------------------------------------
  # Involvement
  # --------------------------------------------------------------------------

  of "incl": incl
  of "excl": excl

  # --------------------------------------------------------------------------
  # Special OpenCorpora
  # --------------------------------------------------------------------------

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
  of "V-ie": V_ie
  of "V-sh": V_sh

  of "Sgtm": Sgtm
  of "Pltm": Pltm

  of "GNdr": GNdr
  of "Inmx": Inmx
  of "Abbr": Abbr
  of "Coun": Coun

  of "Impe": Impe
  of "Fimp": Fimp
  of "Prdx": Prdx
  of "Litr": Litr
  of "Hypo": Hypo
  of "Impx": Impx
  of "Af-p": Af_p

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
    raise newException(
      ValueError,
      "Unknown OpenCorpora grammeme: " & s
    )

# ============================================================================
# enum -> OpenCorpora
# ============================================================================

proc toOpenCorporaStr*(
  g: Grammeme
): string =
  case g
  of ms_f:
    "ms-f"

  of per1:
    "1per"
  of per2:
    "2per"
  of per3:
    "3per"

  of V_be:
    "V-be"
  of V_en:
    "V-en"
  of V_bi:
    "V-bi"
  of V_ey:
    "V-ey"
  of V_oy:
    "V-oy"
  of V_ej:
    "V-ej"
  of V_ie:
    "V-ie"
  of V_sh:
    "V-sh"

  of Sgtm:
    "Sgtm"
  of Pltm:
    "Pltm"

  of GNdr:
    "GNdr"
  of Inmx:
    "Inmx"
  of Abbr:
    "Abbr"
  of Coun:
    "Coun"

  of Impe:
    "Impe"
  of Fimp:
    "Fimp"
  of Prdx:
    "Prdx"
  of Litr:
    "Litr"
  of Hypo:
    "Hypo"
  of Impx:
    "Impx"
  of Af_p:
    "Af-p"

  of gName:
    "Name"
  of gSurn:
    "Surn"
  of gPatr:
    "Patr"

  else:
    $g

# ============================================================================
# Constructors
# ============================================================================

proc initTag*(
  grammemes: GrammemeSet
): Tag {.inline.} =
  Tag(
    grammemes: grammemes
  )

proc parseTag*(
  rawTag: string
): Tag =
  var res: GrammemeSet = {}

  var i = 0
  let L = rawTag.len

  while i < L:

    while i < L and
          (rawTag[i] == ' ' or
           rawTag[i] == ','):
      inc i

    if i >= L:
      break

    let start = i

    while i < L and
          rawTag[i] != ' ' and
          rawTag[i] != ',':
      inc i

    let token =
      rawTag[start ..< i]

    if token.len > 0:
      res.incl(
        parseGrammeme(token)
      )

  result =
    Tag(
      grammemes: res
    )

# ============================================================================
# Operations
# ============================================================================

proc contains*(
  tag: Tag,
  g: Grammeme
): bool {.inline.} =
  g in tag.grammemes

proc contains*(
  tag: Tag,
  subset: GrammemeSet
): bool {.inline.} =
  subset <= tag.grammemes

proc `+`*(
  tag: Tag,
  g: Grammeme
): Tag {.inline.} =
  Tag(
    grammemes:
      tag.grammemes + {g}
  )

proc `-`*(
  tag: Tag,
  g: Grammeme
): Tag {.inline.} =
  Tag(
    grammemes:
      tag.grammemes - {g}
  )

proc `+`*(
  tag: Tag,
  gs: GrammemeSet
): Tag {.inline.} =
  Tag(
    grammemes:
      tag.grammemes + gs
  )

proc `-`*(
  tag: Tag,
  gs: GrammemeSet
): Tag {.inline.} =
  Tag(
    grammemes:
      tag.grammemes - gs
  )

proc `==`*(
  a, b: Tag
): bool {.inline.} =
  a.grammemes == b.grammemes

proc hash*(
  tag: Tag
): Hash {.inline.} =
  hash(tag.grammemes)

# ============================================================================
# Accessors
# ============================================================================

proc pos*(
  tag: Tag
): GrammemeSet {.inline.} =
  tag.grammemes * PosGrammemes

proc caseGrammeme*(
  tag: Tag
): GrammemeSet {.inline.} =
  tag.grammemes * CaseGrammemes

proc number*(
  tag: Tag
): GrammemeSet {.inline.} =
  tag.grammemes * NumberGrammemes

proc gender*(
  tag: Tag
): GrammemeSet {.inline.} =
  tag.grammemes * GenderGrammemes

# ============================================================================
# String representation
# ============================================================================

proc `$`*(
  tag: Tag
): string =
  var parts: seq[string] = @[]

  let p =
    tag.pos

  # POS first
  for g in PosGrammemes:
    if g in p:
      parts.add(
        toOpenCorporaStr(g)
      )
      break

  # Remaining grammemes
  for g in Grammeme:
    if g in tag.grammemes and
       g notin PosGrammemes:

      parts.add(
        toOpenCorporaStr(g)
      )

  result =
    parts.join(",")

# ============================================================================
# Self-test
# ============================================================================

when isMainModule:

  import std/times

  let t1 =
    parseTag(
      "NOUN,anim,masc sing,nomn"
    )

  assert NOUN in t1
  assert anim in t1
  assert masc in t1
  assert sing in t1
  assert nomn in t1

  assert neut notin t1
  assert VERB notin t1

  let t2 =
    parseTag(
      "VERB,V-ie,V-sh,Sgtm,Pltm,GNdr,Inmx,Abbr,Coun,Impe,Fimp,Prdx,Litr,Hypo,Impx,Af-p"
    )

  assert VERB in t2
  assert V_ie in t2
  assert V_sh in t2
  assert Sgtm in t2
  assert Pltm in t2
  assert GNdr in t2
  assert Inmx in t2
  assert Abbr in t2
  assert Coun in t2
  assert Impe in t2
  assert Fimp in t2
  assert Prdx in t2
  assert Litr in t2
  assert Hypo in t2
  assert Impx in t2
  assert Af_p in t2

  let t3 =
    parseTag(
      "NOUN,inan,Ms-f sing,nomn"
    )

  assert ms_f in t3

  assert toOpenCorporaStr(V_ie) == "V-ie"
  assert toOpenCorporaStr(V_sh) == "V-sh"
  assert toOpenCorporaStr(Sgtm) == "Sgtm"
  assert toOpenCorporaStr(Pltm) == "Pltm"
  assert toOpenCorporaStr(GNdr) == "GNdr"
  assert toOpenCorporaStr(Inmx) == "Inmx"
  assert toOpenCorporaStr(Abbr) == "Abbr"
  assert toOpenCorporaStr(Coun) == "Coun"
  assert toOpenCorporaStr(Impe) == "Impe"
  assert toOpenCorporaStr(Fimp) == "Fimp"
  assert toOpenCorporaStr(Prdx) == "Prdx"
  assert toOpenCorporaStr(Litr) == "Litr"
  assert toOpenCorporaStr(Hypo) == "Hypo"
  assert toOpenCorporaStr(Impx) == "Impx"
  assert toOpenCorporaStr(Af_p) == "Af-p"

  let query: GrammemeSet =
    {masc, nomn}

  assert query <= t1.grammemes

  let t4 =
    t1 - {nomn} + {ablt}

  assert ablt in t4
  assert nomn notin t4

  echo "Тест корректности пройден!"
  echo "Запуск бенчмарка битовых операций..."

  let start =
    cpuTime()

  var count = 0

  for _ in 1 .. 10_000_000:
    if query <= t1.grammemes:
      inc count

  let elapsed =
    cpuTime() - start

  echo(
    "10,000,000 проверок тегов выполнены за: ",
    elapsed,
    " сек."
  )

  echo(
    "Скорость: ",
    (
      10_000_000.0 /
      elapsed /
      1_000_000.0
    ),
    " млн операций/сек."
  )

