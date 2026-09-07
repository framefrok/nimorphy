# nimorphy

### Fast and lightweight Russian morphological analysis for Nim

`nimorphy` is a native Russian morphological analyzer and word inflection library written in Nim.

It is designed for applications that need Russian word analysis without embedding a Python runtime or rebuilding a large in-memory dictionary at startup.

The library uses a compact binary dictionary, memory-mapped access, a flat trie for word lookup, compact grammatical tags, and stored morphological paradigms.

## Features

* **Russian morphological analysis**

  * Find all available morphological interpretations of a word.
  * Obtain the normal form (lemma).
  * Inspect part of speech and grammatical features.

* **Word inflection**

  * Generate another grammatical form of a known word.
  * Preserve existing grammatical properties where possible.
  * Request properties such as case, number, gender, tense, and other supported grammemes.

* **Number agreement**

  * Select the appropriate form for Russian numerals.
  * Useful for generated text such as:

    * `1 монета`
    * `2 монеты`
    * `5 монет`
    * `21 монета`

* **Unknown-word heuristics**

  * Attempt morphological analysis for words that are not present in the dictionary.
  * Uses suffixes, endings, and known morphological patterns.
  * Useful for technical vocabulary, slang, game terminology, and neologisms.

* **Memory-mapped dictionary**

  * The binary dictionary is accessed directly through memory mapping.
  * The entire dictionary does not need to be parsed into a large object graph on startup.

* **Compact runtime representation**

  * Word lookup uses a flat trie.
  * Grammatical information is stored as compact bit sets.
  * Morphological paradigms are deduplicated during dictionary generation.

* **Native Nim implementation**

  * Runtime code is written in Nim.
  * No Python or Cython runtime is required by the analyzer itself.

## Quick start

Install the package with Nimble:

```bash
nimble install nimorphy
```

Then:

```nim
import nimorphy

let morph = newMorphAnalyzer()

let parses = morph.parse("стали")

for p in parses:
  echo p.normalForm, " -> ", p.tag

morph.close()
```

A word may have multiple interpretations. For example, `стали` can correspond to different lemmas and grammatical analyses depending on interpretation.

## Inflection

Start with a parsed word and request the grammatical properties you need:

```nim
import nimorphy

let morph = newMorphAnalyzer()

let sword = morph.parse("меч")[0]

echo morph.inflect(sword, {ablt}).word
# мечом

echo morph.inflect(sword, {plur, gent}).word
# мечей

morph.close()
```

`inflect()` operates on a `Parse` result and uses the word's stored paradigm to select the requested form.

## Number agreement

Russian noun forms change depending on the number.

`nimorphy` provides a helper for the common agreement rules:

```nim
import nimorphy

let morph = newMorphAnalyzer()

let coin = morph.parse("монета")[0]

echo morph.agreeWithNumber(coin, 1).word
# монета

echo morph.agreeWithNumber(coin, 2).word
# монеты

echo morph.agreeWithNumber(coin, 5).word
# монет

echo morph.agreeWithNumber(coin, 21).word
# монета

morph.close()
```

This is particularly useful for procedural text generation, games, RPG systems, bots, interfaces, and other applications where text is generated dynamically.

## Unknown words

A dictionary can never contain every future word.

For words that are not found directly, `nimorphy` can fall back to a heuristic predictor.

For example:

```nim
import nimorphy

let morph = newMorphAnalyzer()

let result = morph.parse("байткодом")[0]

echo result.normalForm
# байткод

echo result.tag
# NOUN,inan,masc,sing,ablt

morph.close()
```

The predictor is heuristic, not a statistical or neural language model. Its result should therefore be treated as an informed guess rather than a guaranteed analysis.

This makes it useful for vocabulary that commonly appears outside a static dictionary, such as:

* technical terms;
* software and technology vocabulary;
* slang;
* game terminology;
* user-generated words;
* newly coined words.

## How it works

The runtime is built around a precompiled binary dictionary.

```text
                    OpenCorpora XML
                           │
                           ▼
                    Dictionary builder
                           │
             ┌─────────────┴─────────────┐
             │                           │
       paradigm processing          trie construction
             │                           │
             └─────────────┬─────────────┘
                           ▼
                        dict.bin
                           │
                           ▼
                         mmap
                           │
                           ▼
                       MorphDict
                           │
                           ▼
                       word lookup
                           │
                  ┌────────┴────────┐
                  ▼                 ▼
             morphology         paradigm
              analysis           lookup
```

### Memory mapping

The runtime dictionary is stored in `dict.bin` and accessed through memory mapping.

Instead of loading the whole dictionary into a collection of runtime objects, the analyzer works with the mapped binary representation directly.

This keeps startup work small and avoids duplicating large dictionary structures on the heap.

### Trie lookup

Known words are stored in a compact flat trie.

Conceptually:

```text
м
└── е
    └── ч
        └── terminal
            └── payload
```

The trie stores references to the corresponding word metadata and paradigms.

The implementation uses compact integer offsets and a packed node representation to keep dictionary access inexpensive.

### Paradigms

Morphological forms are grouped into paradigms instead of being treated as completely unrelated dictionary entries.

A paradigm contains the information required to reconstruct the forms of a word together with their grammatical tags.

Equivalent paradigms can be shared during dictionary generation, reducing duplicated data.

### Grammemes

Grammatical properties are represented by Nim's compact `set[Grammeme]` representation.

This allows operations such as checking and combining grammatical properties without storing large collections of strings for every parse.

## Dictionary generation

Most users do not need to build the dictionary manually.

The repository also contains a standalone dictionary builder for converting an OpenCorpora XML dump into the binary format used by the runtime.

A typical build command is:

```bash
nim c -r -d:release --mm:orc -d:danger tools/build_dict.nim
```

The general pipeline is:

```text
OpenCorpora XML
      │
      ▼
   XML parsing
      │
      ▼
  lemma/link processing
      │
      ▼
 paradigm normalization
      │
      ▼
 paradigm deduplication
      │
      ▼
  compact trie
      │
      ▼
 binary serialization
      │
      ▼
    dict.bin
```

The builder is intentionally separate from the runtime so applications do not need to carry dictionary-building logic with them.

## Dictionary format

The runtime dictionary is a custom binary format designed specifically for fast lookup and memory mapping.

At a high level it contains structures for:

```text
Header
Tag / grammeme data
String storage
Morphological rules
Paradigm indexes
Word payloads
Trie nodes
```

The runtime validates the dictionary structure before using its internal offsets and counts.

This makes the binary representation compact while still allowing malformed or incompatible dictionary files to be rejected.

## Dictionary management

The analyzer can locate and manage the dictionary automatically.

```nim
import nimorphy

let morph = newMorphAnalyzer()

echo morph.parse("дом")[0].normalForm

morph.close()
```

A precompiled dictionary can be cached locally and reused by subsequent runs.

For controlled deployments, it is also possible to work with a specific dictionary file rather than relying on automatic acquisition.

## Performance

`nimorphy` was built with performance-sensitive applications in mind.

The runtime avoids several common sources of overhead:

* the dictionary is memory-mapped;
* known-word lookup uses a compact trie;
* dictionary structures are represented with fixed-size integer offsets;
* paradigms are deduplicated during generation;
* grammatical tags use compact sets;
* the runtime does not require a Python interpreter.

A benchmark included in the repository performs repeated parsing of a fixed word set.

Benchmark results depend strongly on:

* CPU architecture;
* Nim version;
* compiler settings;
* memory manager;
* dictionary version;
* input data;
* benchmark methodology.

For that reason, benchmark numbers should be treated as machine-specific measurements rather than universal performance guarantees.

## Intended use

`nimorphy` is suitable for applications such as:

* Russian text normalization;
* full-text search and indexing;
* NLP utilities;
* chatbots;
* text-processing tools;
* document analysis;
* corpus processing;
* procedural text generation;
* game dialogue systems;
* RPG and MUD engines;
* localization and grammar-aware interfaces.

One particularly useful combination is morphological analysis with generated text:

```text
1 найденный меч
2 найденных меча
5 найденных мечей
21 найденный меч
```

The library provides the low-level morphological information needed for applications that construct Russian text dynamically.

## Project structure

```text
nimorphy/
├── src/
│   ├── analyzer.nim
│   ├── dict.nim
│   ├── dict_manager.nim
│   ├── nimorphy.nim
│   ├── tag.nim
│   └── trie.nim
│
├── tools/
│   ├── build_dict.nim
│   ├── test_features.nim
│   └── test_parse.nim
│
├── nimorphy.nimble
└── README.md
```

### Runtime modules

* `analyzer.nim` — morphological analysis, inflection, number agreement, and unknown-word handling.
* `dict.nim` — binary dictionary representation, loading, validation, and access.
* `dict_manager.nim` — dictionary discovery, download, caching, and management.
* `tag.nim` — grammatical tags and grammemes.
* `trie.nim` — compact trie structures and lookup.
* `nimorphy.nim` — public package interface.

### Tools

* `build_dict.nim` — builds `dict.bin` from OpenCorpora data.
* `test_parse.nim` — parsing tests and performance experiments.
* `test_features.nim` — feature-level tests.

## Requirements

The runtime requires:

* Nim 2.x;
* a supported operating system;
* filesystem access for the dictionary cache.

The project is intended to work on common desktop/server platforms supported by Nim.

For performance-oriented builds:

```bash
nim c -d:release --mm:orc your_app.nim
```

## Design goals

The project deliberately favors:

**Small runtime overhead**

The dictionary remains a compact binary resource instead of becoming a large collection of runtime objects.

**Predictable data access**

Known-word lookup follows a deterministic trie path and then resolves the associated payload and paradigm.

**Native implementation**

The core analyzer is written in Nim without requiring a Python runtime.

**Practical morphology**

The goal is not to build a general-purpose linguistic framework, but to provide useful Russian morphology and word generation in a form that is easy to embed into Nim applications.

**Separation of build-time and runtime**

Dictionary construction can be expensive and complex. Runtime applications should only need the compiled binary dictionary.

## Limitations

`nimorphy` is intentionally focused on Russian morphology.

The following points are important:

* Unknown-word analysis is heuristic and can be wrong.
* A word may have multiple valid morphological interpretations.
* `parse()` returns analyses; selecting the semantically correct interpretation may require application-level context.
* Benchmark numbers are environment-dependent.
* The dictionary is derived from external linguistic data and therefore inherits the coverage and properties of that data.
* The runtime requires a compatible compiled dictionary.

## License

### Library

The `nimorphy` source code is released under the MIT License.

### Dictionary data

The bundled/generated dictionary data is based on OpenCorpora data.

OpenCorpora data is distributed under the Creative Commons Attribution-ShareAlike 3.0 Unported license (CC BY-SA 3.0).

See the project and data licenses for the exact terms that apply to a particular distribution.

## Contributing

Contributions are welcome.

Useful areas include:

* correctness fixes;
* morphological test cases;
* parser improvements;
* unknown-word heuristics;
* dictionary tooling;
* performance improvements;
* API design;
* documentation;
* reproducible benchmarks.

For larger changes, opening an issue first is recommended.

## Status

`nimorphy` is an actively developed library.

The core dictionary lookup and morphological operations are usable, while some higher-level areas—especially unknown-word analysis and parse ranking—are intentionally heuristic and continue to evolve.

---

# nimorphy

### Быстрый и компактный морфологический анализ русского языка для Nim

`nimorphy` — нативная библиотека для морфологического анализа и словоизменения русского языка, написанная на Nim.

Она предназначена для приложений, которым нужен русский морфологический анализ без встраивания Python и без необходимости полностью разворачивать большой словарь в набор runtime-объектов при запуске.

В основе библиотеки лежат компактный бинарный словарь, memory mapping, плоское префиксное дерево для поиска слов, компактные грамматические признаки и морфологические парадигмы.

## Возможности

* **Морфологический анализ русского языка**

  * получение всех доступных разборов;
  * определение нормальной формы слова;
  * определение части речи и грамматических признаков.

* **Словоизменение**

  * получение нужной грамматической формы;
  * сохранение исходных признаков, когда это возможно;
  * поддержка падежа, числа, рода, времени и других доступных граммем.

* **Согласование с числительными**

  * автоматический выбор формы слова для чисел;
  * удобно для генерации русского текста.

* **Обработка неизвестных слов**

  * эвристический анализ слов, отсутствующих в словаре;
  * использование окончаний, суффиксов и известных морфологических шаблонов;
  * подходит для технических терминов, сленга, игровых терминов и неологизмов.

* **Memory mapping**

  * бинарный словарь напрямую отображается в адресное пространство процесса;
  * не требуется полностью разбирать его в большое дерево runtime-объектов при каждом запуске.

* **Компактное runtime-представление**

  * поиск выполняется через плоский trie;
  * грамматические свойства хранятся как компактные множества;
  * одинаковые парадигмы переиспользуются при построении словаря.

* **Нативный Nim**

  * runtime написан на Nim;
  * сам анализатор не требует Python или Cython во время работы.

## Быстрый старт

Установка через Nimble:

```bash
nimble install nimorphy
```

Использование:

```nim
import nimorphy

let morph = newMorphAnalyzer()

let parses = morph.parse("стали")

for p in parses:
  echo p.normalForm, " -> ", p.tag

morph.close()
```

У одного слова может быть несколько вариантов разбора. Например, `стали` может соответствовать разным леммам и грамматическим интерпретациям.

## Словоизменение

Начните с разбора слова и передайте необходимые грамматические признаки:

```nim
import nimorphy

let morph = newMorphAnalyzer()

let sword = morph.parse("меч")[0]

echo morph.inflect(sword, {ablt}).word
# мечом

echo morph.inflect(sword, {plur, gent}).word
# мечей

morph.close()
```

`inflect()` использует парадигму, связанную с выбранным разбором слова, чтобы получить нужную форму.

## Согласование с числительными

Для русского языка форма существительного зависит от числа.

`nimorphy` предоставляет готовую функцию:

```nim
import nimorphy

let morph = newMorphAnalyzer()

let coin = morph.parse("монета")[0]

echo morph.agreeWithNumber(coin, 1).word
# монета

echo morph.agreeWithNumber(coin, 2).word
# монеты

echo morph.agreeWithNumber(coin, 5).word
# монет

echo morph.agreeWithNumber(coin, 21).word
# монета

morph.close()
```

Это особенно удобно для:

* игр;
* RPG и MUD;
* чат-ботов;
* интерфейсов;
* генераторов текста;
* систем процедурного текста.

## Неизвестные слова

Ни один словарь не может содержать все возможные слова.

Если слово не найдено напрямую, `nimorphy` может использовать эвристический предиктор.

Например:

```nim
import nimorphy

let morph = newMorphAnalyzer()

let result = morph.parse("байткодом")[0]

echo result.normalForm
# байткод

echo result.tag
# NOUN,inan,masc,sing,ablt

morph.close()
```

Предиктор является эвристическим и не использует статистическую или нейросетевую модель. Его результат следует воспринимать как предположение, а не как гарантированно правильный разбор.

Он особенно полезен для слов, которые часто встречаются вне статического словаря:

* технические термины;
* слова из мира программирования и технологий;
* сленг;
* игровые термины;
* пользовательская лексика;
* новые слова.

## Архитектура

Runtime построен вокруг заранее скомпилированного бинарного словаря.

```text
                  OpenCorpora XML
                         │
                         ▼
                   Сборщик словаря
                         │
             ┌───────────┴───────────┐
             │                       │
       обработка парадигм       построение trie
             │                       │
             └───────────┬───────────┘
                         ▼
                      dict.bin
                         │
                         ▼
                        mmap
                         │
                         ▼
                     MorphDict
                         │
                         ▼
                    поиск слова
                         │
                ┌────────┴────────┐
                ▼                 ▼
             анализ           парадигма
```

### Memory mapping

Runtime-словарь хранится в `dict.bin` и используется через memory mapping.

Вместо того чтобы загружать весь словарь в множество runtime-объектов, анализатор работает непосредственно с отображённым бинарным представлением.

Это уменьшает объём работы при запуске и не требует полного дублирования словаря в heap-структурах.

### Trie

Известные слова хранятся в компактном плоском trie.

Упрощённо:

```text
м
└── е
    └── ч
        └── terminal
            └── payload
```

Узлы содержат компактные смещения и ссылки на соответствующие данные слова.

### Морфологические парадигмы

Словоформы не хранятся как полностью независимые записи.

Вместо этого они группируются в парадигмы, содержащие информацию, необходимую для восстановления форм и их грамматических признаков.

Идентичные парадигмы могут переиспользоваться, что уменьшает дублирование данных в словаре.

### Граммемы

Грамматические свойства представлены через компактный тип:

```nim
set[Grammeme]
```

Это позволяет выполнять проверки и комбинировать грамматические признаки без хранения большого количества строк.

## Сборка словаря

Обычному пользователю собирать словарь вручную не требуется.

В репозитории есть отдельный сборщик, который преобразует XML-данные OpenCorpora в бинарный словарь runtime.

Пример команды:

```bash
nim c -r -d:release --mm:orc -d:danger tools/build_dict.nim
```

Общий pipeline выглядит так:

```text
OpenCorpora XML
      │
      ▼
  разбор XML
      │
      ▼
 обработка лемм и связей
      │
      ▼
 нормализация парадигм
      │
      ▼
 дедупликация парадигм
      │
      ▼
  компактный trie
      │
      ▼
 бинарная сериализация
      │
      ▼
    dict.bin
```

Сборщик отделён от runtime, поэтому конечному приложению не требуется содержать код генерации словаря.

## Бинарный словарь

Основной runtime-файл:

```text
dict.bin
```

На высоком уровне в нём находятся:

```text
Header
Tag / grammeme data
String storage
Morphological rules
Paradigm indexes
Word payloads
Trie nodes
```

Runtime проверяет структуру словаря до использования внутренних смещений и счётчиков.

Это позволяет сохранить компактное бинарное представление и одновременно отклонять повреждённые или несовместимые файлы словаря.

## Управление словарём

Анализатор умеет автоматически находить и обслуживать словарь.

```nim
import nimorphy

let morph = newMorphAnalyzer()

echo morph.parse("дом")[0].normalForm

morph.close()
```

Готовый словарь может сохраняться в локальном кеше и повторно использоваться при последующих запусках.

Для контролируемых окружений можно использовать конкретный файл словаря вместо автоматического получения.

## Производительность

`nimorphy` изначально проектируется для приложений, где важны скорость работы и небольшой runtime overhead.

Для этого используются:

* memory-mapped dictionary;
* компактный trie;
* фиксированные целочисленные смещения;
* дедупликация парадигм;
* компактное хранение грамматических признаков;
* отсутствие необходимости в Python runtime.

В репозитории есть отдельные тесты, выполняющие большое число повторных разборов.

Результаты benchmark зависят от:

* процессора;
* версии Nim;
* параметров компиляции;
* memory manager;
* версии словаря;
* входных данных;
* методики измерения.

Поэтому конкретные числа benchmark следует рассматривать как результаты конкретного окружения, а не как универсальную гарантию производительности.

## Для чего подходит

`nimorphy` может использоваться для:

* нормализации русского текста;
* полнотекстового поиска;
* индексации;
* NLP-инструментов;
* чат-ботов;
* обработки документов;
* анализа корпусов;
* процедурной генерации текста;
* игровых диалогов;
* RPG и MUD;
* генераторов текста;
* автоматического согласования.

Особенно полезно сочетание морфологического анализа и динамической генерации текста:

```text
1 найденный меч
2 найденных меча
5 найденных мечей
21 найденный меч
```

Библиотека предоставляет базовые морфологические данные, необходимые для программ, которые генерируют русский текст во время работы.

## Структура проекта

```text
nimorphy/
├── src/
│   ├── analyzer.nim
│   ├── dict.nim
│   ├── dict_manager.nim
│   ├── nimorphy.nim
│   ├── tag.nim
│   └── trie.nim
│
├── tools/
│   ├── build_dict.nim
│   ├── test_features.nim
│   └── test_parse.nim
│
├── nimorphy.nimble
└── README.md
```

### Runtime-модули

* `analyzer.nim` — морфологический анализ, словоизменение, согласование с числами и обработка неизвестных слов.
* `dict.nim` — бинарный словарь, загрузка, проверка и доступ к данным.
* `dict_manager.nim` — поиск, загрузка, кеширование и управление словарём.
* `tag.nim` — грамматические теги и граммемы.
* `trie.nim` — структуры trie и поиск.
* `nimorphy.nim` — публичный интерфейс библиотеки.

### Инструменты

* `build_dict.nim` — сборка `dict.bin` из данных OpenCorpora.
* `test_parse.nim` — тесты анализа и эксперименты с производительностью.
* `test_features.nim` — функциональные тесты.

## Требования

Для runtime необходимы:

* Nim 2.x;
* поддерживаемая операционная система;
* доступ к файловой системе для кеша словаря.

Для release-сборки:

```bash
nim c -d:release --mm:orc your_app.nim
```

## Основные принципы проекта

**Низкий runtime overhead**

Словарь остаётся компактным бинарным ресурсом, а не превращается в большое количество runtime-объектов.

**Предсказуемый поиск**

Поиск известного слова выполняется по детерминированному пути trie с последующим доступом к payload и парадигме.

**Нативный Nim**

Основная логика анализатора реализована непосредственно на Nim.

**Практическая морфология**

Цель проекта — не создать универсальную лингвистическую платформу, а дать Nim-приложениям удобный и быстрый инструмент для работы с русской морфологией.

**Разделение build-time и runtime**

Сложная работа по построению словаря выполняется отдельно. Runtime-приложению нужен только уже подготовленный бинарный словарь.

## Ограничения

`nimorphy` сфокусирован на русском языке.

Важно учитывать:

* анализ неизвестных слов является эвристическим;
* у слова может существовать несколько корректных разборов;
* `parse()` возвращает варианты, а выбор подходящего варианта в зависимости от контекста может потребовать дополнительной логики приложения;
* benchmark зависит от окружения;
* качество покрытия определяется исходными лингвистическими данными;
* runtime требует совместимый бинарный словарь.

## Лицензия

### Библиотека

Исходный код `nimorphy` распространяется под лицензией MIT.

### Данные словаря

Словарь построен на основе данных OpenCorpora.

Данные OpenCorpora распространяются на условиях Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0).

Для конкретной распространяемой версии необходимо учитывать условия лицензии как самого кода, так и используемых словарных данных.

## Участие в разработке

Приветствуются:

* исправления ошибок;
* новые тесты морфологии;
* улучшения анализа;
* улучшение predictor неизвестных слов;
* развитие инструментов сборки словаря;
* оптимизации;
* улучшения API;
* документация;
* воспроизводимые benchmark.

Для крупных изменений желательно сначала открыть issue с описанием предложения.

## Статус проекта

`nimorphy` находится в активной разработке.

Базовый поиск по словарю и основные операции морфологии уже реализованы. Более высокоуровневые части, особенно эвристический анализ неизвестных слов и ранжирование вариантов разбора, продолжают развиваться.
