## tools/test_parse.nim
import std/[times, strutils]
import ../src/nimorphy

let morph = newMorphAnalyzer("dict.bin")

echo "=== 1. Проверка омонимии слова 'стали' ==="
let parses = morph.parse("стали")
for p in parses:
  echo "Лемма: ", p.normalForm, " | Тег: ", p.tag

echo "\n=== 2. Проверка регистра и буквы Ё ==="
for w in ["ЁЖ", "ежа", "России", "быстро"]:
  let res = morph.parse(w)
  if res.len > 0:
    echo w, " -> лемма: ", res[0].normalForm, " [", res[0].tag.pos, "]"

echo "\n=== 3. Бенчмарк производительности (1 000 000 разборов) ==="
let words = ["стали", "человек", "красивый", "программирования", "быстро", "москва"]
let totalIterations = 1_000_000

let startTime = cpuTime()
var totalParses = 0

for i in 0 ..< totalIterations:
  let w = words[i mod words.len]
  let res = morph.parse(w)
  totalParses += res.len

let elapsed = cpuTime() - startTime
let speed = totalIterations.float / elapsed

echo "Выполнено разборов: ", totalIterations
echo "Затрачено времени:  ", elapsed.formatFloat(ffDecimal, 3), " сек."
echo "Скорость разбора:   ", int(speed), " слов/сек. (", (speed / 1_000_000.0).formatFloat(ffDecimal, 2), " млн/сек.)"

morph.close()