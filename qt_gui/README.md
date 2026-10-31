# Tester GUI (Qt 6 / QML) — PEAK PCAN-USB

Versione Qt/QML della GUI di collaudo di [../csharp_gui](../csharp_gui): stesse
funzioni, stesso protocollo ([../doc/protocol.md](../doc/protocol.md), frame
standard 2.0A) e stesso convertitore **PEAK PCAN-USB** (API **PCAN-Basic**).

## Funzioni della GUI

- **Connessione**: scelta canale (PCAN-USB 1..8), bitrate, indirizzo nodo.
- **Direzione (CONFIG)**: maschera esadecimale + scorciatoie "tutte uscite / tutti ingressi".
- **Uscite (OUTPUT)**: 32 pulsanti a due stati + "Scrivi uscite" / "Azzera".
- **Stato (STATUS)**: 32 indicatori (verde = alto) aggiornati dalle trame STATUS;
  pulsante "Leggi stato" (REQUEST).
- **Encoder**: 8 conteggi (int16) dalle trame ENC_DATA; periodo di trasmissione,
  stop, azzeramento contatori.
- **Analogico (solo MAX 10)**: 8 letture ADC (12 bit) dalle trame ANALOG e 8 soglie
  (CONFIG SUB=1/2); riquadro **rosso** sopra soglia, **giallo** sotto.
- **Log**: traffico CAN TX/RX in tempo reale.

## Requisiti

1. **Qt 6.5+** con i moduli Qt Quick / Qt Quick Controls 2 (testato con
   Qt 6.12.0 MinGW 64 bit, toolchain MinGW 13.1, CMake + Ninja di Qt).
2. **PCANBasic.dll (x64)** di PEAK accanto all'eseguibile oppure nel PATH
   (l'installer del driver PEAK lo mette in `Windows\System32`). Il DLL e'
   caricato a runtime: senza, la GUI parte e segnala l'errore alla connessione.
3. Convertitore **PEAK PCAN-USB** sullo stesso bus dell'expander, **500 kbit/s**,
   terminazione **120 Ω**.

## Build & run

Da Qt Creator: apri `CMakeLists.txt`, scegli il kit *Desktop Qt 6.x MinGW 64-bit*
ed esegui.

Da PowerShell:

```powershell
$env:PATH = "C:\Qt\Tools\mingw1310_64\bin;C:\Qt\Tools\Ninja;C:\Qt\Tools\CMake_64\bin;C:\Qt\6.12.0\mingw_64\bin;$env:PATH"
cd qt_gui
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release `
      -DCMAKE_PREFIX_PATH=C:/Qt/6.12.0/mingw_64 `
      -DPCANBASIC_DLL=C:/percorso/PCAN-Basic/x64/PCANBasic.dll   # opzionale
cmake --build build
.\build\ExpanderTesterQt.exe
```

`PCANBASIC_DLL` (opzionale) copia il DLL accanto all'eseguibile ad ogni build.

### Distribuzione

```powershell
cmake --install build --prefix deploy
```

esegue `windeployqt` e copia in `deploy\bin` l'eseguibile con le librerie Qt,
i moduli QML e (se indicato) `PCANBasic.dll`.

## Struttura

```
qt_gui/
  CMakeLists.txt          progetto CMake (Qt 6, modulo QML "ExpanderTester")
  main.cpp                entry point (stile Fusion)
  Main.qml                interfaccia grafica
  expandercontroller.*    logica di test (comandi + ricezione), esposta a QML
  pcanbasic.*             wrapper minimale PCAN-Basic caricato a runtime (QLibrary)
```
