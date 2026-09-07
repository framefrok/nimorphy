## tools/test_features.nim
import ../src/nimorphy

let morph = newMorphAnalyzer("dict.bin")

echo "========================================"
echo "   nimorphy: Демонстрация возможностей"
echo "========================================"

# 1. Склонение (Inflect)
echo "\n--- 1. Словоизменение (Inflect) ---"
let sword = morph.parse("меч")[0]
echo "Исходное слово: ", sword.word, " (", sword.tag, ")"

let swordAblt = morph.inflect(sword, {ablt})
echo "Творительный падеж (ablt):  ", swordAblt.word  # мечом

let swordPlurGen = morph.inflect(sword, {plur, gent})
echo "Множеств. родительный:      ", swordPlurGen.word # мечей

# 2. Согласование с числительными (agreeWithNumber)
echo "\n--- 2. Согласование с числительными ---"
let coin = morph.parse("монета")[0]
for n in [1, 2, 4, 5, 11, 21, 25]:
  let agreed = morph.agreeWithNumber(coin, n)
  echo n, " ", agreed.word

# 3. Предиктор для неизвестных слов (Heuristic Predictor)
echo "\n--- 3. Предиктор неизвестных несловарных слов ---"
for unknown in ["криптовалютный", "нейросеточка", "байткодом"]:
  let res = morph.parse(unknown)
  if res.len > 0:
    echo unknown, " -> лемма: ", res[0].normalForm, " | тег: [", res[0].tag, "] (score: ", res[0].score, ")"

morph.close()