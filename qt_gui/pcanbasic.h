/*
 * pcanbasic.h  --  Wrapper MINIMALE per l'API PCAN-Basic di PEAK.
 *
 * PCANBasic.dll viene caricato a runtime (QLibrary): l'applicazione parte anche
 * senza il DLL e segnala l'errore solo alla connessione. Copre solo cio' che
 * serve alla GUI di test (Initialize/Uninitialize/Read/Write/GetErrorText).
 *
 * Richiede PCANBasic.dll (pacchetto/driver PCAN-Basic di PEAK) accanto
 * all'eseguibile o nel PATH; bitness del DLL = bitness dell'app (qui x64).
 */
#pragma once

#include <QLibrary>
#include <QString>
#include <cstdint>

#ifdef _WIN32
#define PCAN_API __stdcall
#else
#define PCAN_API
#endif

namespace pcan {

using Handle = uint16_t;
using Status = uint32_t;

constexpr Status ERROR_OK        = 0x00000;
constexpr Status ERROR_QRCVEMPTY = 0x00020;

// Canali PCAN-USB (PCAN_USBBUS1..8 = 0x51..0x58)
constexpr Handle USBBUS1 = 0x51;

// Bitrate (codici Btr0Btr1)
constexpr uint16_t BAUD_1M   = 0x0014;
constexpr uint16_t BAUD_500K = 0x001C;
constexpr uint16_t BAUD_250K = 0x011C;
constexpr uint16_t BAUD_125K = 0x031C;

constexpr uint8_t MESSAGE_STANDARD = 0x00;
constexpr uint8_t MESSAGE_RTR      = 0x01;
constexpr uint8_t MESSAGE_EXTENDED = 0x02;

struct Msg {
    uint32_t ID;
    uint8_t  MSGTYPE;
    uint8_t  LEN;
    uint8_t  DATA[8];
};

struct Timestamp {
    uint32_t millis;
    uint16_t millis_overflow;
    uint16_t micros;
};

class Api
{
public:
    // Carica il DLL e risolve i simboli; false (con messaggio) se non disponibile.
    bool load(QString *error);
    bool isLoaded() const { return m_initialize != nullptr; }

    Status initialize(Handle channel, uint16_t btr0btr1);
    Status uninitialize(Handle channel);
    Status read(Handle channel, Msg *msg, Timestamp *ts);
    Status write(Handle channel, Msg *msg);
    QString errorText(Status st);

private:
    using InitializeFn   = Status (PCAN_API *)(Handle, uint16_t, uint8_t, uint32_t, uint16_t);
    using UninitializeFn = Status (PCAN_API *)(Handle);
    using ReadFn         = Status (PCAN_API *)(Handle, Msg *, Timestamp *);
    using WriteFn        = Status (PCAN_API *)(Handle, Msg *);
    using ErrorTextFn    = Status (PCAN_API *)(Status, uint16_t, char *);

    QLibrary       m_lib{QStringLiteral("PCANBasic")};
    InitializeFn   m_initialize   = nullptr;
    UninitializeFn m_uninitialize = nullptr;
    ReadFn         m_read         = nullptr;
    WriteFn        m_write        = nullptr;
    ErrorTextFn    m_errorText    = nullptr;
};

} // namespace pcan
