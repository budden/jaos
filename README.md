﻿# ЯОС - форк A2 OS, сделан 2017-04-27 вечером

A2 OS - это операционная система, написанная на языке Active Oberon. Может работать на железе x86, в т.ч. в вирт. машинах, 
а также как приложение под Windows, Linux и другими ОС. Содержит оконный менеджер и ряд приложений. 

Цели форка:

- использование русского как приоритетного языка, планируется русификация исходных текстов
- документирование на русском языке
- минимизация
- модернизация


См. [Вики](http://вики-ч115.программирование-по-русски.рф/Ч115/Ч115)


# Related documents
2002: [Pieter Muller. The active object system design and multiprocessor implementation](https://www.research-collection.ethz.ch/handle/20.500.11850/147091) [PDF](Docs/2002_ActiveObjectSystemDesign.pdf)

2003: [Patrik Reali. Using Oberon’s active objects for language interoperability and compilation](https://www.research-collection.ethz.ch/handle/20.500.11850/72831) [PDF](Docs/2003_ActiveObjectsLanguageInteroperability.pdf)

2004: [Patrik Reali. Active Oberon Language Report](https://oberoncore.ru/_media/wiki/lang/reali_p.active_oberon_language_report.en.pdf) [PDF](Docs/2004_ActiveOberonLanguageReport.pdf)

2005: [Thomas Frey. Bluebottle: A Thread-safe Multimedia and GUI Framework for Active Oberon](https://www.research-collection.ethz.ch/handle/20.500.11850/72739) [PDF](Docs/2005_Bluebottle.pdf)

2006: [Felix Friedrich, Jürg Gutknecht. Array-structured object types for mathematical programming](http://people.inf.ethz.ch/felixf/pdfs/2006_ArrayStructuredOT.pdf) [PDF](Docs/2006_ArrayStructuredObjectTypes.pdf)

2007: [Felix Friedrich, Jürg Gutknecht, Oleksii Morozov, Patrick Hunziker. A Mathematical Programming Language Extension for Multilinear Algebra](http://people.inf.ethz.ch/felixf/pdfs/2007_ProgrammingMultilinearAlgebra.pdf) [PDF](Docs/2007_ProgrammingMultilinearAlgebra.pdf)

2011: [Olivier Clerc, Felix Friedrich. Dynamic Operator Overloading in a Statically Typed Language](http://people.inf.ethz.ch/felixf/pdfs/2011_DynamicOperatorOverloading.pdf) [PDF](Docs/2011_DynamicOperatorOverloading.pdf)

2011: [Felix Friedrich, Florian Negele. A Compiler-Supported Unification of Static and Dynamic Loading](http://people.inf.ethz.ch/felixf/pdfs/2011_UnifiedStaticDynamicLoading.pdf) [PDF](Docs/2011_UnifiedStaticDynamicLoading.pdf)

2014: [Florian Negele. Combining Lock-Free Programming with Cooperative Multitasking for a Portable Multiprocessor Runtime System](https://www.research-collection.ethz.ch/handle/20.500.11850/154828) [PDF](Docs/2014_LockFreeProgramming.pdf)

2016: [Florian Negele, Felix Friedrich, Suwon Oh, Bernhard Egger. On the Design and Implementation of an Efficient Lock-Free Scheduler](http://people.inf.ethz.ch/felixf/pdfs/2016_JSSP_OnTheDesignOfALockFreeScheduler.pdf) [PDF](Docs/2016_OnTheDesignOfALockFreeScheduler.pdf)

# How to build
1. Create NewAos folder in Work folder;
2. Open Builds.Tool from file manager;
3. Follow instructions;
4. Run corresponding commands.

# Programming tutorials
[Felix Friedrich, Ulrike Glavitsch, Florian Negele, Sven Stauber. A2 Programming Quick Start Guide](Docs/A2%20Programming%20Quick%20Start%20Guide.pdf)

[Sven Stauber. A2 Component Framework](Docs/A2%20Component%20Framework.pdf)

# Known issues
1. Steps to reproduce: Set backdrop "Saas Fee". Save desktop. Shutdown A2. Try to start A2 and immediately shutdown, and repeat it several times. Sometimes on startup hangup happens. Only with "Saas Fee" backdrop, which is the only in JPEG format. Seems like some problem with JPEG decoder.


