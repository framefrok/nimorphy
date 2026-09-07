<div align="center">

# nimorphy

**Fast and lightweight Russian morphological analysis for Nim**

Native Russian morphology, word inflection, number agreement, and heuristic analysis of unknown words — without a Python runtime.

[![Nim](https://img.shields.io/badge/Nim-2.x-FCC624?logo=nim&logoColor=black)](https://nim-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](#license)
[![Dictionary](https://img.shields.io/badge/dictionary-OpenCorpora-7b68ee)](#dictionary-generation)

[🇬🇧 English](#english) · [🇷🇺 Русский](#русский)

</div>

---

<a id="english"></a>

## 🇬🇧 English

`nimorphy` is a native Russian morphological analyzer and word-inflection library written in Nim.

It is built for applications that need practical Russian morphology without embedding Python or rebuilding a large in-memory dictionary on every startup.

### ✨ What it does

| Feature | Description |
|---|---|
| 🔎 **Morphological analysis** | Find all available interpretations, lemmas, parts of speech, and grammatical features. |
| 🔄 **Word inflection** | Generate grammatical forms while preserving the source analysis where possible. |
| 🔢 **Number agreement** | Select the correct form for Russian numerals: `1 монета`, `2 монеты`, `5 монет`. |
| 🧠 **Unknown-word heuristics** | Predict the morphology of words that are not present in the dictionary. |
| 🗂️ **Memory-mapped dictionary** | Access the compiled dictionary directly instead of rebuilding a large object graph. |
| 🌲 **Compact trie** | Fast deterministic lookup using a flat trie and integer offsets. |
| 🧩 **Compact grammar tags** | Grammatical properties are stored as compact `set[Grammeme]` values. |
| ⚡ **Native Nim runtime** | No Python or Cython runtime is required by the analyzer itself. |

---

## 🚀 Quick start

Install with Nimble:

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

A word may have several valid interpretations. For example, `стали` can correspond to different lemmas and grammatical analyses depending on context.

---

## 🔄 Inflection

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

`inflect()` works from a `Parse` result and uses the associated morphological paradigm to select the requested form.

---

## 🔢 Number agreement

Russian noun forms depend on the number. `nimorphy` provides a helper for the common agreement rules:

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

This is especially useful for procedural text generation, games, RPG systems, bots, interfaces, and other applications where Russian text is generated dynamically.

---

## 🧠 Unknown words

A dictionary cannot contain every future word. When a word is not found directly, `nimorphy` can fall back to a heuristic predictor.

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

The predictor is heuristic rather than statistical or neural, so its result should be treated as an informed guess.

It is useful for vocabulary that often lives outside a static dictionary:

- technical terms;
- software and technology vocabulary;
- slang;
- game terminology;
- user-generated words;
- newly coined words.

---

## 🏗️ How it works

The runtime is built around a precompiled binary dictionary.

```text
                    OpenCorpora XML
                           │
                           ▼
                   Dictionary builder
                           │
              ┌────────────┴────────────┐
              │                         │
      paradigm processing        trie construction
              │                         │
              └────────────┬────────────┘
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
                 ┌─────────┴─────────┐
                 ▼                   ▼
             morphology          paradigm
              analysis             lookup
```

### 🗂️ Memory mapping

The runtime dictionary is stored in `dict.bin` and accessed through memory mapping.

Instead of loading the entire dictionary into a large collection of runtime objects, the analyzer works with the mapped binary representation directly. This keeps startup work small and avoids duplicating large dictionary structures on the heap.

### 🌲 Trie lookup

Known words are stored in a compact flat trie:

```text
м
└── е
    └── ч
        └── terminal
            └── payload
```

The trie uses compact integer offsets and packed node data to keep dictionary access inexpensive.

### 🧬 Paradigms

Morphological forms are grouped into paradigms instead of being treated as unrelated dictionary entries.

A paradigm stores the information required to reconstruct a word's forms together with their grammatical tags. Equivalent paradigms can be shared during dictionary generation, reducing duplicated data.

### 🏷️ Grammemes

Grammatical properties use Nim's compact set representation:

```nim
set[Grammeme]
```

This makes checking and combining grammatical properties inexpensive compared with storing many strings for every parse.

---

## 🛠️ Dictionary generation

Most users do not need to build the dictionary manually.

The repository includes a standalone builder that converts an OpenCorpora XML dump into the binary format used by the runtime.

```bash
nim c -r -d:release --mm:orc -d:danger tools/build_dict.nim
```

Pipeline:

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

The builder is intentionally separate from the runtime so applications do not need to carry dictionary-generation logic.

---

## 📦 Dictionary format

The runtime dictionary is a custom binary format designed for fast lookup and memory mapping.

At a high level it contains:

```text
Header
Tag / grammeme data
String storage
Morphological rules
Paradigm indexes
Word payloads
Trie nodes
```

The runtime validates the dictionary structure before using its internal offsets and counts, allowing malformed or incompatible dictionary files to be rejected.

---

## 📚 Dictionary management

The analyzer can locate and manage the dictionary automatically:

```nim
import nimorphy

let morph = newMorphAnalyzer()

echo morph.parse("дом")[0].normalForm

morph.close()
```

A precompiled dictionary can be cached locally and reused by subsequent runs.

For controlled deployments, a specific dictionary file can also be used instead of relying on automatic acquisition.

---

## ⚡ Performance

`nimorphy` is designed with performance-sensitive applications in mind.

The runtime avoids several common sources of overhead:

- memory-mapped dictionary access;
- compact trie lookup;
- fixed-size integer offsets;
- deduplicated paradigms;
- compact grammatical sets;
- no Python interpreter requirement.

The repository also includes benchmark-oriented tests that repeatedly parse a fixed word set.

Benchmark results depend on:

- CPU architecture;
- Nim version;
- compiler settings;
- memory manager;
- dictionary version;
- input data;
- benchmark methodology.

Therefore, benchmark numbers should be treated as machine-specific measurements, not universal performance guarantees.

---

## 🎮 Intended use

`nimorphy` fits applications such as:

- Russian text normalization;
- full-text search and indexing;
- NLP utilities;
- chatbots;
- document processing;
- corpus processing;
- procedural text generation;
- game dialogue systems;
- RPG and MUD engines;
- localization and grammar-aware interfaces.

A particularly useful combination is morphology + dynamic text generation:

```text
1 найденный меч
2 найденных меча
5 найденных мечей
21 найденный меч
```

The library provides the low-level morphological information needed to construct Russian text dynamically.

---

## 📁 Project structure

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

| Module | Purpose |
|---|---|
| `analyzer.nim` | Morphological analysis, inflection, number agreement, unknown-word handling. |
| `dict.nim` | Binary dictionary representation, loading, validation, and access. |
| `dict_manager.nim` | Dictionary discovery, download, caching, and management. |
| `tag.nim` | Grammatical tags and grammemes. |
| `trie.nim` | Compact trie structures and lookup. |
| `nimorphy.nim` | Public package interface. |

### Tools

| Tool | Purpose |
|---|---|
| `build_dict.nim` | Build `dict.bin` from OpenCorpora data. |
| `test_parse.nim` | Parsing tests and performance experiments. |
| `test_features.nim` | Feature-level tests. |

---

## 📋 Requirements

The runtime requires:

- Nim 2.x;
- a supported operating system;
- filesystem access for the dictionary cache.

For performance-oriented builds:

```bash
nim c -d:release --mm:orc your_app.nim
```

---

## 🎯 Design goals

### Small runtime overhead

Keep the dictionary as a compact binary resource instead of turning it into a large collection of runtime objects.

### Predictable data access

Known-word lookup follows a deterministic trie path and then resolves the associated payload and paradigm.

### Native implementation

The core analyzer is written in Nim and does not require a Python runtime.

### Practical morphology

The goal is not a general-purpose linguistic framework. It is a practical Russian morphology and word-generation library that is easy to embed into Nim applications.

### Build-time / runtime separation

Expensive dictionary construction happens separately. Runtime applications only need the prepared binary dictionary.

---

## ⚠️ Limitations

`nimorphy` intentionally focuses on Russian morphology.

Keep in mind:

- unknown-word analysis is heuristic and may be wrong;
- a word may have several valid morphological interpretations;
- `parse()` returns analyses, while choosing the semantically correct one may require application-level context;
- benchmark results depend on the environment;
- dictionary coverage depends on the underlying linguistic data;
- the runtime requires a compatible compiled dictionary.

---

## 📄 License

### Library

The `nimorphy` source code is released under the **MIT License**.

### Dictionary data

The dictionary is based on OpenCorpora data.

OpenCorpora data is distributed under the **Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)** license.

For a particular distribution, consider the terms applying to both the source code and the dictionary data.

---

## 🤝 Contributing

Contributions are welcome.

Useful areas include:

- correctness fixes;
- morphological test cases;
- parser improvements;
- unknown-word heuristics;
- dictionary tooling;
- performance improvements;
- API design;
- documentation;
- reproducible benchmarks.

For larger changes, opening an issue first is recommended.

---

## 🚧 Status

`nimorphy` is actively developed.

Core dictionary lookup and the main morphological operations are usable. Higher-level areas — especially unknown-word analysis and parse ranking — remain heuristic and continue to evolve.

---

<a id="русский"></a>

## 🇷🇺 Русский

`nimorphy` — нативная библиотека для морфологического анализа и словоизменения русского языка, написанная на Nim.

Проект предназначен для приложений, которым нужна практическая русская морфология без встраивания Python и без необходимости полностью разворачивать большой словарь в набор runtime-объектов при каждом запуске.

### ✨ Возможности

| Возможность | Описание |
|---|---|
| 🔎 **Морфологический анализ** | Все доступные разборы, нормальная форма, часть речи и грамматические признаки. |
| 🔄 **Словоизменение** | Получение нужной грамматической формы с сохранением исходных признаков, когда это возможно. |
| 🔢 **Согласование с числительными** | Автоматический выбор формы: `1 монета`, `2 монеты`, `5 монет`. |
| 🧠 **Неизвестные слова** | Эвристический анализ слов, которых нет в словаре. |
| 🗂️ **Memory mapping** | Бинарный словарь напрямую отображается в адресное пространство процесса. |
| 🌲 **Компактный trie** | Детерминированный поиск по плоскому префиксному дереву. |
| 🧩 **Компактные граммемы** | Грамматические свойства представлены через `set[Grammeme]`. |
| ⚡ **Нативный Nim** | Сам анализатор не требует Python или Cython во время работы. |

---

## 🚀 Быстрый старт

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

У одного слова может быть несколько корректных интерпретаций. Например, `стали` может соответствовать разным леммам и грамматическим разборам в зависимости от контекста.

---

## 🔄 Словоизменение

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

`inflect()` работает с результатом `Parse` и использует связанную с ним морфологическую парадигму для получения нужной формы.

---

## 🔢 Согласование с числительными

Форма русского существительного зависит от числа. `nimorphy` предоставляет готовую функцию для распространённых правил согласования:

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

Особенно удобно это для:

- игр;
- RPG и MUD;
- чат-ботов;
- интерфейсов;
- генераторов текста;
- процедурных систем.

---

## 🧠 Неизвестные слова

Ни один словарь не может содержать все возможные будущие слова. Если слово не найдено напрямую, `nimorphy` может использовать эвристический предиктор.

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

Предиктор является эвристическим и не использует статистическую или нейросетевую модель. Поэтому его результат следует воспринимать как предположение, а не как гарантированно правильный разбор.

Он особенно полезен для:

- технических терминов;
- слов из мира программирования и технологий;
- сленга;
- игровых терминов;
- пользовательской лексики;
- новых слов.

---

## 🏗️ Архитектура

Runtime построен вокруг заранее скомпилированного бинарного словаря.

```text
                    OpenCorpora XML
                           │
                           ▼
                    Сборщик словаря
                           │
              ┌────────────┴────────────┐
              │                         │
        обработка парадигм        построение trie
              │                         │
              └────────────┬────────────┘
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
                 ┌─────────┴─────────┐
                 ▼                   ▼
              анализ            парадигма
```

### 🗂️ Memory mapping

Runtime-словарь хранится в `dict.bin` и используется через memory mapping.

Вместо загрузки всего словаря в большое количество runtime-объектов анализатор работает непосредственно с отображённым бинарным представлением. Это уменьшает объём работы при запуске и не требует полного дублирования словаря в heap-структурах.

### 🌲 Trie

Известные слова хранятся в компактном плоском trie:

```text
м
└── е
    └── ч
        └── terminal
            └── payload
```

Для хранения и доступа используются компактные смещения и упакованное представление узлов.

### 🧬 Морфологические парадигмы

Словоформы не хранятся как полностью независимые записи.

Они группируются в парадигмы, содержащие информацию, необходимую для восстановления форм и их грамматических признаков. Идентичные парадигмы могут переиспользоваться, уменьшая дублирование данных.

### 🏷️ Граммемы

Грамматические свойства представлены через компактный тип:

```nim
set[Grammeme]
```

Это позволяет проверять и комбинировать грамматические признаки без хранения большого количества строк.

---

## 🛠️ Сборка словаря

Обычному пользователю собирать словарь вручную не требуется.

В репозитории есть отдельный сборщик, который преобразует XML-данные OpenCorpora в бинарный словарь runtime.

```bash
nim c -r -d:release --mm:orc -d:danger tools/build_dict.nim
```

Pipeline:

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

---

## 📦 Бинарный словарь

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

Runtime проверяет структуру словаря до использования внутренних смещений и счётчиков, поэтому повреждённые или несовместимые файлы могут быть отклонены.

---

## 📚 Управление словарём

Анализатор умеет автоматически находить и обслуживать словарь:

```nim
import nimorphy

let morph = newMorphAnalyzer()

echo morph.parse("дом")[0].normalForm

morph.close()
```

Готовый словарь может сохраняться в локальном кеше и повторно использоваться при последующих запусках.

Для контролируемых окружений можно использовать конкретный файл словаря вместо автоматического получения.

---

## ⚡ Производительность

`nimorphy` изначально проектируется для приложений, где важны скорость работы и небольшой runtime overhead.

Используются:

- memory-mapped dictionary;
- компактный trie;
- фиксированные целочисленные смещения;
- дедупликация парадигм;
- компактное хранение грамматических признаков;
- отсутствие необходимости в Python runtime.

В репозитории есть отдельные тесты, выполняющие большое число повторных разборов.

Результаты benchmark зависят от:

- процессора;
- версии Nim;
- параметров компиляции;
- memory manager;
- версии словаря;
- входных данных;
- методики измерения.

Поэтому конкретные числа benchmark следует рассматривать как результаты конкретного окружения, а не как универсальную гарантию производительности.

---

## 🎮 Для чего подходит

`nimorphy` может использоваться для:

- нормализации русского текста;
- полнотекстового поиска;
- индексации;
- NLP-инструментов;
- чат-ботов;
- обработки документов;
- анализа корпусов;
- процедурной генерации текста;
- игровых диалогов;
- RPG и MUD;
- генераторов текста;
- автоматического согласования.

Особенно полезно сочетание морфологии и динамической генерации текста:

```text
1 найденный меч
2 найденных меча
5 найденных мечей
21 найденный меч
```

Библиотека предоставляет базовые морфологические данные, необходимые приложениям, которые строят русский текст во время работы.

---

## 📁 Структура проекта

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

| Модуль | Назначение |
|---|---|
| `analyzer.nim` | Морфологический анализ, словоизменение, согласование с числами и обработка неизвестных слов. |
| `dict.nim` | Бинарный словарь, загрузка, проверка и доступ к данным. |
| `dict_manager.nim` | Поиск, загрузка, кеширование и управление словарём. |
| `tag.nim` | Грамматические теги и граммемы. |
| `trie.nim` | Структуры trie и поиск. |
| `nimorphy.nim` | Публичный интерфейс библиотеки. |

### Инструменты

| Инструмент | Назначение |
|---|---|
| `build_dict.nim` | Сборка `dict.bin` из данных OpenCorpora. |
| `test_parse.nim` | Тесты анализа и эксперименты с производительностью. |
| `test_features.nim` | Функциональные тесты. |

---

## 📋 Требования

Для runtime необходимы:

- Nim 2.x;
- поддерживаемая операционная система;
- доступ к файловой системе для кеша словаря.

Для release-сборки:

```bash
nim c -d:release --mm:orc your_app.nim
```

---

## 🎯 Основные принципы

### Низкий runtime overhead

Словарь остаётся компактным бинарным ресурсом, а не превращается в большое количество runtime-объектов.

### Предсказуемый поиск

Поиск известного слова выполняется по детерминированному пути trie с последующим доступом к payload и парадигме.

### Нативный Nim

Основная логика анализатора реализована непосредственно на Nim и не требует Python runtime.

### Практическая морфология

Цель проекта — не создать универсальную лингвистическую платформу, а дать Nim-приложениям удобный и быстрый инструмент для работы с русской морфологией.

### Разделение build-time и runtime

Сложная работа по построению словаря выполняется отдельно. Runtime-приложению нужен только готовый бинарный словарь.

---

## ⚠️ Ограничения

`nimorphy` сфокусирован на русском языке.

Важно учитывать:

- анализ неизвестных слов является эвристическим;
- у слова может существовать несколько корректных разборов;
- `parse()` возвращает варианты, а выбор подходящего в зависимости от контекста может потребовать дополнительной логики приложения;
- benchmark зависит от окружения;
- качество покрытия определяется исходными лингвистическими данными;
- runtime требует совместимый бинарный словарь.

---

## 📄 Лицензия

### Библиотека

Исходный код `nimorphy` распространяется под **MIT License**.

### Данные словаря

Словарь построен на основе данных OpenCorpora.

Данные OpenCorpora распространяются на условиях **Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)**.

Для конкретной версии распространения необходимо учитывать условия лицензии как самого кода, так и используемых словарных данных.

---

## 🤝 Участие в разработке

Приветствуются:

- исправления ошибок;
- новые тесты морфологии;
- улучшения анализа;
- развитие predictor неизвестных слов;
- развитие инструментов сборки словаря;
- оптимизации;
- улучшения API;
- документация;
- воспроизводимые benchmark.

Для крупных изменений желательно сначала открыть issue с описанием предложения.

---

## 🚧 Статус проекта

`nimorphy` находится в активной разработке.

Базовый поиск по словарю и основные операции морфологии уже реализованы. Более высокоуровневые части, особенно эвристический анализ неизвестных слов и ранжирование вариантов разбора, продолжают развиваться.

---

<div align="center">

**nimorphy — Russian morphology, written in Nim.**

[⬆ Back to top](#nimorphy)

</div>
