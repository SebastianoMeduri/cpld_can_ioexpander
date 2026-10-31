/*
 * pcanbasic.cpp  --  Caricamento a runtime di PCANBasic.dll. Vedi pcanbasic.h.
 */
#include "pcanbasic.h"

namespace pcan {

bool Api::load(QString *error)
{
    if (isLoaded())
        return true;

    if (!m_lib.load()) {
        if (error)
            *error = QStringLiteral("PCANBasic.dll non trovato. Installa PCAN-Basic (PEAK) "
                                    "e copia il DLL x64 accanto all'eseguibile.\n\n")
                     + m_lib.errorString();
        return false;
    }

    auto initialize   = reinterpret_cast<InitializeFn>(m_lib.resolve("CAN_Initialize"));
    auto uninitialize = reinterpret_cast<UninitializeFn>(m_lib.resolve("CAN_Uninitialize"));
    auto read         = reinterpret_cast<ReadFn>(m_lib.resolve("CAN_Read"));
    auto write        = reinterpret_cast<WriteFn>(m_lib.resolve("CAN_Write"));
    auto errorText    = reinterpret_cast<ErrorTextFn>(m_lib.resolve("CAN_GetErrorText"));

    if (!initialize || !uninitialize || !read || !write || !errorText) {
        if (error)
            *error = QStringLiteral("PCANBasic.dll non valido: funzioni dell'API mancanti.");
        m_lib.unload();
        return false;
    }

    m_initialize   = initialize;
    m_uninitialize = uninitialize;
    m_read         = read;
    m_write        = write;
    m_errorText    = errorText;
    return true;
}

Status Api::initialize(Handle channel, uint16_t btr0btr1)
{
    return m_initialize(channel, btr0btr1, 0, 0, 0);
}

Status Api::uninitialize(Handle channel)
{
    return m_uninitialize(channel);
}

Status Api::read(Handle channel, Msg *msg, Timestamp *ts)
{
    return m_read(channel, msg, ts);
}

Status Api::write(Handle channel, Msg *msg)
{
    return m_write(channel, msg);
}

QString Api::errorText(Status st)
{
    char buf[256] = {};
    if (isLoaded() && m_errorText(st, 0, buf) == ERROR_OK)
        return QString::fromLocal8Bit(buf);
    return QStringLiteral("0x%1").arg(st, 5, 16, QLatin1Char('0'));
}

} // namespace pcan
