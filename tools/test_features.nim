import ../src/nimorphy
import ../src/tag

let morph = newMorphAnalyzer("dict.bin")

echo "========================================"
echo "   nimorphy: Демонстрация возможностей"
echo "========================================"

# 1. Склонение (Inflect)
echo "\n--- 1. Словоизменение (Inflect) ---"
let sword = morph.bestParse("меч")
echo "Исходное слово: ", sword.word, " (", sword.tag, ")"

let swordAblt = morph.inflect(sword, {ablt})
echo "Творительный падеж (ablt):  ", swordAblt.word  # мечом

let swordPlurGen = morph.inflect(sword, {plur, gent})
echo "Множеств. родительный:      ", swordPlurGen.word # мечей

# 2. Согласование с числительными (agreeWithNumber)
echo "\n--- 2. Согласование с числительными ---"
let coin = morph.bestParse("монета")
for n in [1, 2, 4, 5, 11, 21, 25]:
  let agreed = morph.agreeWithNumber(coin, n)
  echo n, " ", agreed.word

# 3. Предиктор для неизвестных слов (Heuristic Predictor)
echo "\n--- 3. Предиктор неизвестных несловарных слов ---"
for unknown in ["криптовалютный", "нейросеточка", "байткодом", "вуглускр"]:
  let res = morph.bestParse(unknown)
  if res.word != "": # Проверяем, что разбор удался
    echo unknown, " -> лемма: ", res.normalForm, " | тег: [", res.tag, "] (score: ", res.score, ")"

morph.close()
