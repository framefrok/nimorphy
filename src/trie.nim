## nimorphy/trie.nim
## Высокопроизводительное компактное префиксное дерево поверх mmap памяти.

type
  TrieNode* {.packed.} = object
    charByte*: uint8      ## Байт UTF-8 перехода в этот узел
    childCount*: uint8    ## Число потомков (0..255)
    flags*: uint16        ## Флаги узла (1 = terminal)
    childStart*: uint32   ## Индекс первого потомка в плоском массиве узлов
    payloadStart*: uint32 ## Смещение в таблице Payload (пар парадигм)
    payloadCount*: uint16 ## Количество грамматических трактовок этого слова
    reserved: uint16

static:
  assert sizeof(TrieNode) == 16, "TrieNode must be 16 bytes aligned"

const
  FlagTerminal* = 1.uint16

proc isTerminal*(node: TrieNode): bool {.inline.} =
  (node.flags and FlagTerminal) != 0

# --- Быстрый поиск потомка среди непрерывного блока узлов ---

proc findChild*(nodes: ptr UncheckedArray[TrieNode], parent: TrieNode, b: uint8): int32 {.inline.} =
  ## Ищет переход по байту `b`. Возвращает индекс дочернего узла или -1.
  let count = int(parent.childCount)
  if count == 0:
    return -1
  
  let start = int(parent.childStart)

  # Для малого числа детей (до 8) линейный скан быстрее бинарного за счёт предвыборки L1
  if count <= 8:
    for i in 0 ..< count:
      let idx = start + i
      let cb = nodes[idx].charByte
      if cb == b: return idx.int32
      if cb > b: return -1 # Дети отсортированы!
    return -1

  # Бинарный поиск для широких разветвлений
  var low = 0
  var high = count - 1
  while low <= high:
    let mid = (low + high) shr 1
    let idx = start + mid
    let cb = nodes[idx].charByte
    if cb == b:
      return idx.int32
    elif cb < b:
      low = mid + 1
    else:
      high = mid - 1
  return -1

proc exactMatch*(nodes: ptr UncheckedArray[TrieNode], rootIdx: int32, key: string): int32 =
  ## Совершает побайтовый переход по строке `key`.
  ## Возвращает индекс терминального узла или -1, если слово не найдено.
  var currIdx = rootIdx
  let L = key.len
  for i in 0 ..< L:
    let b = cast[uint8](key[i])
    currIdx = findChild(nodes, nodes[currIdx], b)
    if currIdx == -1:
      return -1
      
  if nodes[currIdx].isTerminal:
    return currIdx
  return -1