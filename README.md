# nimorphy ⚡

[![Nim](https://img.shields.io/badge/Language-Nim-yellow.svg)](https://nim-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Speed](https://img.shields.io/badge/Speed-%3E1.15M%20words%2Fsec-brightgreen.svg)]()
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)]()

> **Ultra-fast Russian morphological analysis and synthesis in pure Nim.**

**nimorphy** is a high-performance morphological analyzer and synthesizer for the Russian language, written entirely in Nim.

It is designed as a fast and lightweight alternative to Python libraries such as [`pymorphy2`](https://github.com/pymorphy2/pymorphy2) and [`pymorphy3`](https://github.com/nozavroni/pymorphy3), with a strong focus on speed, low memory overhead, fast startup, and efficient dictionary access.

> 🚀 **~1.16M parses/sec** on a single CPU core  
> ⚡ **15–20× faster than Cython-based Pymorphy2**  
> 💾 **< 1 ms dictionary startup** with `mmap`  
> 🧠 Heuristic analysis of unknown words  
> 📦 Pure Nim — no Python or Cython required

---

# 🇬🇧 English

## ✨ Features

- 🚀 **Extreme Performance** — over **1,150,000 parses/sec** on a single CPU core.
- 🧠 **Automatic Dictionary Management** — automatically downloads and caches precompiled dictionaries from GitHub Releases.
- 💾 **Memory Mapping (`mmap`)** — dictionary data is accessed directly from a memory-mapped binary file.
- ⚡ **Low Allocation Design** — dictionary lookup is designed to avoid unnecessary heap allocations.
- 🏷️ **Grammeme Bitmasks** — grammatical properties are represented using compact `set[Grammeme]` bitmasks.
- 🔄 **Inflection** — generate required grammatical forms for case, number, gender, tense, and other supported categories.
- 🔢 **Numeric Agreement** — automatically select grammatically correct forms for numbers.
- 🔮 **Unknown Word Prediction** — analyze slang, technical terms, neologisms, and other words missing from the dictionary.
- 📦 **ARC / ORC Compatible** — designed to work with modern Nim memory management models.

---

## ⚡ Benchmark

Single-threaded morphological parsing:

| Library | Language | Speed | Startup |
| :--- | :--- | ---: | ---: |
| **nimorphy** | **Nim** | **~1,160,000 words/sec** | **< 1 ms** |
| Pymorphy2 (Fast / DAWG) | Python + Cython | ~180,000 words/sec | ~300 ms |
| Pymorphy2 (Pure) | Python | ~15,000 words/sec | ~1,200 ms |

> Benchmark results depend on CPU, compiler version, build configuration, dictionary version, and input data.

---

## 📦 Installation

Install with Nimble:

    nimble install nimorphy

Then import the library:

    import nimorphy

No manual dictionary installation is required.

The dictionary is automatically resolved and downloaded when necessary.

---

## 🚀 Quick Start

    import nimorphy

    # Initialize analyzer.
    # Dictionary is automatically resolved or downloaded.
    let morph = newMorphAnalyzer()

    # Morphological analysis
    let parses = morph.parse("стали")

    for p in parses:
      echo p.normalForm, " -> ", p.tag

    # Example output:
    # сталь -> NOUN,inan,femn,sing,gent
    # стать -> VERB,plur,perf,intr,past,indc


    # Inflection
    let sword = morph.parse("меч")[0]

    echo morph.inflect(sword, {ablt}).word
    # мечом

    echo morph.inflect(sword, {plur, gent}).word
    # мечей


    # Numeric agreement
    let coin = morph.parse("монета")[0]

    echo morph.agreeWithNumber(coin, 1).word
    # монета

    echo morph.agreeWithNumber(coin, 4).word
    # монеты

    echo morph.agreeWithNumber(coin, 10).word
    # монет


    # Unknown word heuristics
    let unknown = morph.parse("байткодом")[0]

    echo unknown.normalForm
    # байткод

    echo unknown.tag
    # NOUN,inan,masc,sing,ablt


    morph.close()

---

## 🔄 Morphological Operations

### Analysis

Parse a word and obtain all available morphological interpretations:

    let parses = morph.parse("стали")

    for p in parses:
      echo p.normalForm, " -> ", p.tag

Example:

    сталь -> NOUN,inan,femn,sing,gent
    стать -> VERB,plur,perf,intr,past,indc

### Inflection

Generate a requested grammatical form:

    let sword = morph.parse("меч")[0]

    echo morph.inflect(sword, {ablt}).word
    # мечом

    echo morph.inflect(sword, {plur, gent}).word
    # мечей

### Numeric Agreement

Automatically select a form that agrees with a number:

    let coin = morph.parse("монета")[0]

    echo morph.agreeWithNumber(coin, 1).word
    # монета

    echo morph.agreeWithNumber(coin, 2).word
    # монеты

    echo morph.agreeWithNumber(coin, 5).word
    # монет

    echo morph.agreeWithNumber(coin, 21).word
    # монета

---

## 🧠 Unknown Words

Not every possible Russian word can exist in a dictionary.

For unknown words, `nimorphy` uses a heuristic predictor that analyzes suffixes, endings, and morphological patterns.

Example:

    байткодом
        │
        ├── normal form: байткод
        ├── POS: NOUN
        ├── gender: MASC
        ├── number: SING
        └── case: ABLT

This is useful for:

- technical terminology;
- technology names;
- slang;
- game terminology;
- neologisms;
- user-generated words.

---

## ⚙️ Architecture

### 1. Memory Mapping

The binary dictionary `dict.bin` is mapped directly into the process address space using `mmap`.

Traditional approach:

    dict.bin
       ↓
      read
       ↓
      parse
       ↓
    allocate
       ↓
   build objects
       ↓
     lookup

`nimorphy` approach:

    dict.bin
       ↓
      mmap
       ↓
  mapped dictionary
       ↓
     lookup

This avoids parsing and rebuilding the entire dictionary during every startup.

### 2. Compact Trie

Dictionary lookup is based on a compact prefix tree:

    "м"
     │
     └── "е"
          │
          └── "ч"
               │
               └── terminal
                    │
                    └── paradigm

Trie nodes are stored in a compact binary representation designed for efficient memory access.

### 3. Paradigm Compression

Word forms are not stored as completely independent strings.

Instead, compact structures can represent:

    stem
    +
    ending
    +
    paradigm
    +
    grammatical metadata

Example:

    мечом
     │
     ├── stem: меч
     └── ending: ом

This reduces duplication inside the dictionary.

### 4. Grammeme Bitmasks

Grammatical properties are represented using:

    set[Grammeme]

This allows fast checks using compact bit operations instead of repeated string comparisons or heavyweight runtime structures.

---

## 🗃️ Dictionary

The main runtime dictionary file is:

    dict.bin

A simplified representation:

    dict.bin
    │
    ├── Header
    ├── Trie Nodes
    ├── UTF-8 Transitions
    ├── Paradigm References
    ├── Word Metadata
    ├── Endings
    └── Grammeme Data

The binary format is designed specifically for fast lookup and memory mapping.

---

## 🔨 Building the Dictionary

Manual dictionary compilation is normally unnecessary.

To build a dictionary from an OpenCorpora XML dump:

    nim c -r -d:release --mm:orc -d:danger tools/build_dict.nim

The builder performs the following pipeline:

    OpenCorpora XML
          │
          ▼
        Parse
          │
          ▼
    Paradigm Deduplication
          │
          ▼
      Compact Trie
          │
          ▼
    Binary Serialization
          │
          ▼
        dict.bin

---

## 🎮 Use Cases

`nimorphy` can be used for:

- 🔎 full-text search;
- 📚 NLP tools;
- 🤖 chatbots;
- 💬 Russian text processing;
- 🎮 game dialogue systems;
- 🧙 RPG and MUD projects;
- 📜 interactive fiction;
- 🗂️ document indexing;
- 📊 corpus analysis;
- ✍️ procedural text generation;
- 🔤 word normalization;
- 🧩 automatic grammatical agreement.

Example:

    1 найденный меч
    2 найденных меча
    5 найденных мечей
    21 найденный меч

---

## 🛠️ Requirements

Required:

- [Nim](https://nim-lang.org/)
- a supported operating system;
- filesystem access for dictionary caching.

Supported platforms:

    Windows
    Linux
    macOS

Recommended release build:

    nim c -d:release --mm:orc your_app.nim

---

## 🤝 Contributing

Contributions are welcome.

Useful contributions include:

- bug reports;
- tests;
- dictionary improvements;
- performance optimizations;
- new heuristic rules;
- API improvements;
- documentation.

For large changes, opening an issue before implementation is recommended.

---

## 📄 License & Credits

- **Library Code:** Distributed under the **[MIT License](LICENSE)** © 2026 framefrok.
- **Dictionary Data:** Based on data from the **[OpenCorpora](http://opencorpora.org/)** project, licensed under **[Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)](https://creativecommons.org/licenses/by-sa/3.0/)**.

---

## 🔗 Links

- [Nim](https://nim-lang.org/)
- [OpenCorpora](http://opencorpora.org/)
- [pymorphy2](https://github.com/pymorphy2/pymorphy2)
- [pymorphy3](https://github.com/nozavroni/pymorphy3)

---

# 🇷🇺 Русский

## ✨ Возможности

- 🚀 **Экстремальная производительность** — более **1 150 000 разборов/сек** на одном ядре CPU.
- 🧠 **Автоматическое управление словарём** — готовый словарь автоматически загружается из GitHub Releases и кэшируется локально.
- 💾 **Memory Mapping (`mmap`)** — бинарный словарь напрямую отображается в адресное пространство процесса.
- ⚡ **Минимум аллокаций** — поиск по словарю не требует лишних heap-аллокаций.
- 🏷️ **Битовые маски граммем** — грамматические признаки представлены компактными `set[Grammeme]`.
- 🔄 **Словоизменение** — получение нужных форм по падежу, числу, роду, времени и другим грамматическим признакам.
- 🔢 **Согласование с числительными** — автоматический выбор правильной формы слова.
- 🔮 **Предиктор неизвестных слов** — анализ сленга, технических терминов, неологизмов и других слов, отсутствующих в словаре.
- 📦 **Совместимость с ARC / ORC** — поддержка современных моделей управления памятью Nim.

---

## ⚡ Benchmark

Однопоточный морфологический анализ:

| Библиотека | Язык | Скорость | Запуск |
| :--- | :--- | ---: | ---: |
| **nimorphy** | **Nim** | **~1 160 000 слов/сек** | **< 1 мс** |
| Pymorphy2 (Fast / DAWG) | Python + Cython | ~180 000 слов/сек | ~300 мс |
| Pymorphy2 (Pure) | Python | ~15 000 слов/сек | ~1 200 мс |

> Результаты зависят от процессора, версии компилятора, параметров сборки, версии словаря и входных данных.

---

## 📦 Установка

Установка через Nimble:

    nimble install nimorphy

После установки:

    import nimorphy

Ручная установка словаря не требуется.

При необходимости библиотека автоматически найдёт или скачает готовый бинарный словарь и сохранит его в кэше.

---

## 🚀 Быстрый старт

    import nimorphy

    # Инициализация.
    # Словарь будет найден или загружен автоматически.
    let morph = newMorphAnalyzer()

    # Морфологический анализ
    let parses = morph.parse("стали")

    for p in parses:
      echo p.normalForm, " -> ", p.tag

    # Пример:
    # сталь -> NOUN,inan,femn,sing,gent
    # стать -> VERB,plur,perf,intr,past,indc


    # Склонение
    let sword = morph.parse("меч")[0]

    echo morph.inflect(sword, {ablt}).word
    # мечом

    echo morph.inflect(sword, {plur, gent}).word
    # мечей


    # Согласование с числительными
    let coin = morph.parse("монета")[0]

    echo morph.agreeWithNumber(coin, 1).word
    # монета

    echo morph.agreeWithNumber(coin, 4).word
    # монеты

    echo morph.agreeWithNumber(coin, 10).word
    # монет


    # Эвристический анализ неизвестного слова
    let unknown = morph.parse("байткодом")[0]

    echo unknown.normalForm
    # байткод

    echo unknown.tag
    # NOUN,inan,masc,sing,ablt


    morph.close()

---

## 🔄 Морфологические операции

### Анализ

Получение всех доступных морфологических разборов слова:

    let parses = morph.parse("стали")

    for p in parses:
      echo p.normalForm, " -> ", p.tag

Пример:

    сталь -> NOUN,inan,femn,sing,gent
    стать -> VERB,plur,perf,intr,past,indc

### Словоизменение

Получение нужной грамматической формы:

    let sword = morph.parse("меч")[0]

    echo morph.inflect(sword, {ablt}).word
    # мечом

    echo morph.inflect(sword, {plur, gent}).word
    # мечей

### Согласование с числительными

Автоматический выбор формы, соответствующей числу:

    let coin = morph.parse("монета")[0]

    echo morph.agreeWithNumber(coin, 1).word
    # монета

    echo morph.agreeWithNumber(coin, 2).word
    # монеты

    echo morph.agreeWithNumber(coin, 5).word
    # монет

    echo morph.agreeWithNumber(coin, 21).word
    # монета

---

## 🧠 Несловарные слова

Не каждое возможное русское слово может находиться в словаре.

Для неизвестных слов `nimorphy` использует эвристический предиктор, анализирующий суффиксы, окончания и характерные морфологические шаблоны.

Например:

    байткодом
        │
        ├── normal form: байткод
        ├── часть речи: NOUN
        ├── род: MASC
        ├── число: SING
        └── падеж: ABLT

Это особенно полезно для:

- технических терминов;
- названий технологий;
- сленга;
- игровых терминов;
- неологизмов;
- пользовательских слов.

---

## ⚙️ Архитектура

### 1. Memory Mapping

Бинарный словарь `dict.bin` напрямую отображается операционной системой в адресное пространство процесса через `mmap`.

Традиционный подход:

    dict.bin
       ↓
      read
       ↓
      parse
       ↓
    allocate
       ↓
   build objects
       ↓
     lookup

Подход `nimorphy`:

    dict.bin
       ↓
      mmap
       ↓
  mapped dictionary
       ↓
     lookup

Это позволяет избежать полного разбора словаря при каждом запуске.

### 2. Compact Trie

Для поиска используется компактное префиксное дерево:

    "м"
     │
     └── "е"
          │
          └── "ч"
               │
               └── terminal
                    │
                    └── paradigm

Узлы Trie хранятся в компактном бинарном представлении, рассчитанном на быстрый доступ к данным.

### 3. Сжатие парадигм

Словоформы не хранятся как полностью независимые строки.

Вместо этого используются компактные структуры:

    основа
    +
    окончание
    +
    парадигма
    +
    грамматические данные

Например:

    мечом
     │
     ├── основа: меч
     └── окончание: ом

Так уменьшается количество дублирующихся данных в словаре.

### 4. Битовые маски граммем

Грамматические признаки представлены через:

    set[Grammeme]

Это позволяет быстро выполнять проверки с помощью битовых операций вместо строковых сравнений и тяжёлых runtime-структур.

---

## 🗃️ Словарь

Основной runtime-файл:

    dict.bin

Упрощённая структура:

    dict.bin
    │
    ├── Header
    ├── Trie Nodes
    ├── UTF-8 Transitions
    ├── Paradigm References
    ├── Word Metadata
    ├── Endings
    └── Grammeme Data

Бинарный формат предназначен для быстрого поиска и эффективного использования через memory mapping.

---

## 🔨 Сборка словаря

В большинстве случаев ручная сборка не требуется.

Для сборки словаря из XML-дампа OpenCorpora:

    nim c -r -d:release --mm:orc -d:danger tools/build_dict.nim

Инструмент выполняет следующий процесс:

    OpenCorpora XML
          │
          ▼
        Parse
          │
          ▼
    Дедупликация парадигм
          │
          ▼
      Compact Trie
          │
          ▼
    Бинарная сериализация
          │
          ▼
        dict.bin

---

## 🎮 Применение

`nimorphy` подходит для:

- 🔎 полнотекстового поиска;
- 📚 NLP-инструментов;
- 🤖 чат-ботов;
- 💬 обработки русского текста;
- 🎮 игровых диалогов;
- 🧙 RPG и MUD;
- 📜 интерактивной литературы;
- 🗂️ индексации документов;
- 📊 анализа корпусов;
- ✍️ процедурной генерации текста;
- 🔤 нормализации слов;
- 🧩 автоматического согласования.

Например:

    1 найденный меч
    2 найденных меча
    5 найденных мечей
    21 найденный меч

---

## 🛠️ Требования

Необходимы:

- [Nim](https://nim-lang.org/)
- поддерживаемая операционная система;
- доступ к файловой системе для кэширования словаря.

Поддерживаемые платформы:

    Windows
    Linux
    macOS

Рекомендуемая release-сборка:

    nim c -d:release --mm:orc your_app.nim

---

## 🤝 Участие в разработке

Вклад в проект приветствуется.

Особенно полезны:

- bug reports;
- тесты;
- улучшения словаря;
- оптимизации;
- новые эвристические правила;
- улучшения API;
- документация.

Для крупных изменений рекомендуется предварительно открыть issue с описанием предложения.

---

## 📄 Лицензии и авторские права (License & Credits)

- **Код библиотеки (Code):** распространяется под лицензией [MIT](LICENSE) © 2026 framefrok.
- **Словарные данные (Dictionary Data):** используются данные проекта [OpenCorpora](http://opencorpora.org/), распространяемые по лицензии [Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)](https://creativecommons.org/licenses/by-sa/3.0/).

---

## 🔗 Ссылки

- [Nim](https://nim-lang.org/)
- [OpenCorpora](http://opencorpora.org/)
- [pymorphy2](https://github.com/pymorphy2/pymorphy2)
- [pymorphy3](https://github.com/nozavroni/pymorphy3)

---

<div align="center">

# nimorphy ⚡

### Fast Russian morphology in pure Nim

**Fast · Small · Native**

</div>
