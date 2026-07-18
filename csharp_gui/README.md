# Tester GUI (C# / WinForms) — PEAK PCAN-USB

Interfaccia grafica Windows per collaudare l'I/O expander CAN usando un
convertitore **PEAK PCAN-USB** (API **PCAN-Basic**). Parla il protocollo
descritto in [../doc/protocol.md](../doc/protocol.md): frame standard 2.0A.

![funzioni](https://img.shields.io/badge/CAN-2.0A-blue) 500 kbit/s (o 250/125k/1M)

## Funzioni della GUI

- **Connessione**: scelta canale (PCAN-USB 1..8), bitrate, indirizzo nodo.
- **Direzione (CONFIG)**: maschera esadecimale + scorciatoie "tutte uscite / tutti ingressi".
- **Uscite (OUTPUT)**: 32 pulsanti a due stati + "Scrivi uscite" / "Azzera".
- **Stato (STATUS)**: 32 indicatori (verde = alto), aggiornati in tempo reale dalle
  trame STATUS ricevute; pulsante "Leggi stato" (REQUEST).
- **Encoder**: 8 conteggi (int16) aggiornati dalle trame ENC_DATA; impostazione
  del periodo di trasmissione, stop, azzeramento contatori.
- **Log**: traffico CAN TX/RX in tempo reale.

## Requisiti

1. **.NET SDK 8** (o superiore con targeting pack Windows Desktop). Build testata
   con SDK 9.
2. **Driver + PCAN-Basic di PEAK** installati. Serve **`PCANBasic.dll` (x64)**
   accanto all'eseguibile oppure nel PATH di sistema (l'installer PCAN-Basic lo
   mette in `Windows\System32`).
3. Convertitore **PEAK PCAN-USB** collegato, sullo stesso bus dell'expander,
   **500 kbit/s**, terminazione **120 Ω**.

> Nota: `PCANBasic.cs` qui incluso è un wrapper P/Invoke minimale. Se preferisci,
> sostituiscilo con il `PCANBasic.cs` ufficiale di PEAK (stesso namespace) ed
> elimina quello incluso per evitare duplicati.

## Build & run

```powershell
cd csharp_gui
dotnet build -c Release
# copia PCANBasic.dll (x64) in bin\Release\net8.0-windows\  se non e' nel PATH
dotnet run -c Release
```

Oppure apri `ExpanderTester.csproj` in Visual Studio 2022 e premi F5.

## Uso rapido

1. Seleziona il canale **PCAN-USB**, bitrate **500 kbit/s**, **Nodo** = quello
   strappato sul CPLD (default 1) → **Connetti**.
2. Imposta la direzione (es. `FFFF0000` = pin 31..16 uscite).
3. Spunta le uscite desiderate → **Scrivi uscite**.
4. **Leggi stato** o osserva gli indicatori aggiornarsi automaticamente.
5. Imposta il periodo encoder (es. 50 ms) per vedere i conteggi in tempo reale.

## Struttura

```
csharp_gui/
  ExpanderTester.csproj   progetto .NET (net8.0-windows, x64, WinForms)
  Program.cs              entry point
  MainForm.cs             GUI + logica di test (comandi + ricezione)
  PCANBasic.cs            wrapper P/Invoke minimale per PCAN-Basic
```
