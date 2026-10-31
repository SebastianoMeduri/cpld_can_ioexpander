/*
 * expandercontroller.cpp  --  Comandi e ricezione CAN dell'I/O expander.
 */
#include "expandercontroller.h"

#include <QTime>

namespace {

// Codici FUNC del protocollo (vedi doc/protocol.md)
constexpr int FUNC_ENCPER  = 0;
constexpr int FUNC_OUTPUT  = 1;
constexpr int FUNC_CONFIG  = 2;
constexpr int FUNC_REQUEST = 3;
constexpr int FUNC_STATUS  = 4;
constexpr int FUNC_ENCRST  = 5;
constexpr int FUNC_ENC     = 6;
constexpr int FUNC_ANALOG  = 7;

constexpr uint16_t kBaudCodes[] = {pcan::BAUD_500K, pcan::BAUD_250K, pcan::BAUD_125K, pcan::BAUD_1M};

} // namespace

ExpanderController::ExpanderController(QObject *parent)
    : QObject(parent)
{
    m_rxTimer.setInterval(20);
    connect(&m_rxTimer, &QTimer::timeout, this, &ExpanderController::pollRx);
}

ExpanderController::~ExpanderController()
{
    disconnectBus();
}

void ExpanderController::setNode(int node)
{
    node = qBound(0, node, 15);
    if (node == m_node)
        return;
    m_node = node;
    emit nodeChanged();
}

QStringList ExpanderController::channelNames() const
{
    QStringList names;
    for (int i = 1; i <= 8; i++)
        names << QStringLiteral("PCAN-USB %1").arg(i);
    return names;
}

QStringList ExpanderController::baudNames() const
{
    return {QStringLiteral("500 kbit/s"), QStringLiteral("250 kbit/s"),
            QStringLiteral("125 kbit/s"), QStringLiteral("1 Mbit/s")};
}

// ------------------------------------------------------------ connessione
void ExpanderController::toggleConnection(int channelIndex, int baudIndex)
{
    if (m_connected)
        disconnectBus();
    else
        connectBus(channelIndex, baudIndex);
}

void ExpanderController::connectBus(int channelIndex, int baudIndex)
{
    QString err;
    if (!m_api.load(&err)) {
        emit errorOccurred(err);
        return;
    }

    channelIndex = qBound(0, channelIndex, 7);
    baudIndex = qBound(0, baudIndex, 3);
    m_channel = static_cast<pcan::Handle>(pcan::USBBUS1 + channelIndex);

    pcan::Status st = m_api.initialize(m_channel, kBaudCodes[baudIndex]);
    if (st != pcan::ERROR_OK) {
        log(QStringLiteral("Errore init: ") + m_api.errorText(st));
        emit errorOccurred(QStringLiteral("Inizializzazione fallita: ") + m_api.errorText(st));
        return;
    }

    m_connected = true;
    emit connectedChanged();
    m_rxTimer.start();
    log(QStringLiteral("Connesso su %1 a %2").arg(channelNames().at(channelIndex), baudNames().at(baudIndex)));
}

void ExpanderController::disconnectBus()
{
    if (!m_connected)
        return;
    m_rxTimer.stop();
    m_api.uninitialize(m_channel);
    m_connected = false;
    emit connectedChanged();
    log(QStringLiteral("Disconnesso"));
}

// ------------------------------------------------------------- invio CAN
void ExpanderController::sendRaw(int func, int sub, const uint8_t *data, int len, const QString &tag)
{
    if (!m_connected) {
        log(QStringLiteral("Non connesso"));
        return;
    }
    pcan::Msg msg = {};
    msg.ID = static_cast<uint32_t>(((func & 0x7) << 8) | ((m_node & 0xF) << 4) | (sub & 0xF));
    msg.MSGTYPE = pcan::MESSAGE_STANDARD;
    msg.LEN = static_cast<uint8_t>(len);
    for (int i = 0; i < len && i < 8; i++)
        msg.DATA[i] = data[i];

    pcan::Status st = m_api.write(m_channel, &msg);
    QString line = QStringLiteral("TX 0x%1 [%2] %3  %4")
                       .arg(hexNum(msg.ID, 3)).arg(len).arg(hexBytes(msg.DATA, len), tag);
    if (st != pcan::ERROR_OK)
        line += QStringLiteral("  ERR: ") + m_api.errorText(st);
    log(line);
}

void ExpanderController::sendPinWord(int func, uint32_t word, const QString &tag)
{
    const uint8_t d[4] = {static_cast<uint8_t>(word >> 24), static_cast<uint8_t>(word >> 16),
                          static_cast<uint8_t>(word >> 8),  static_cast<uint8_t>(word)};
    sendRaw(func, 0, d, 4, tag + QStringLiteral(" 0x") + hexNum(word, 8));
}

bool ExpanderController::setDirection(const QString &hexMask)
{
    uint32_t mask;
    if (!parseHex(hexMask, &mask)) {
        log(QStringLiteral("Maschera di direzione non valida"));
        return false;
    }
    sendPinWord(FUNC_CONFIG, mask, QStringLiteral("CONFIG dir"));
    return true;
}

void ExpanderController::writeOutputs(const QList<bool> &bits)
{
    uint32_t w = 0;
    for (int i = 0; i < 32 && i < bits.size(); i++)
        if (bits.at(i))
            w |= (1u << i);
    sendPinWord(FUNC_OUTPUT, w, QStringLiteral("OUTPUT"));
}

void ExpanderController::requestStatus()
{
    sendRaw(FUNC_REQUEST, 0, nullptr, 0, QStringLiteral("REQUEST"));
}

bool ExpanderController::setEncPeriod(const QString &ms)
{
    bool ok = false;
    uint v = ms.trimmed().toUInt(&ok);
    if (!ok || v > 0xFFFF) {
        log(QStringLiteral("Periodo non valido"));
        return false;
    }
    const uint8_t d[2] = {static_cast<uint8_t>(v >> 8), static_cast<uint8_t>(v)};
    sendRaw(FUNC_ENCPER, 0, d, 2, QStringLiteral("ENC_PERIOD %1 ms").arg(v));
    return true;
}

void ExpanderController::resetEncoders()
{
    // maschera di reset letta dall'expander in data[7:0] = byte 7 -> DLC 8
    const uint8_t d[8] = {0, 0, 0, 0, 0, 0, 0, 0xFF};
    sendRaw(FUNC_ENCRST, 0, d, 8, QStringLiteral("ENC_RESET"));
}

// Invia le 8 soglie ADC con due trame CONFIG (SUB=1 ch0..3, SUB=2 ch4..7).
void ExpanderController::setThresholds(const QStringList &hexValues)
{
    for (int blk = 0; blk < 2; blk++) {
        uint8_t d[8];
        for (int i = 0; i < 4; i++) {
            uint32_t v = 0;
            const int idx = blk * 4 + i;
            if (idx < hexValues.size())
                parseHex(hexValues.at(idx), &v);
            v &= 0x0FFF;                                    // 12 bit utili
            d[2 * i]     = static_cast<uint8_t>(v >> 8);    // canale piu' basso nei byte alti
            d[2 * i + 1] = static_cast<uint8_t>(v);
        }
        sendRaw(FUNC_CONFIG, blk + 1, d, 8,
                QStringLiteral("CONFIG soglie ch%1..%2").arg(blk * 4).arg(blk * 4 + 3));
    }
}

// --------------------------------------------------------- ricezione CAN
void ExpanderController::pollRx()
{
    if (!m_connected)
        return;
    pcan::Msg msg;
    pcan::Timestamp ts;
    for (int guard = 0; guard < 200; guard++) {
        if (m_api.read(m_channel, &msg, &ts) != pcan::ERROR_OK)
            break;
        process(msg);
    }
}

void ExpanderController::process(const pcan::Msg &msg)
{
    const bool ext = (msg.MSGTYPE & pcan::MESSAGE_EXTENDED) != 0;
    log(QStringLiteral("RX 0x%1 [%2] %3%4")
            .arg(hexNum(msg.ID, 3)).arg(msg.LEN)
            .arg(hexBytes(msg.DATA, msg.LEN), ext ? QStringLiteral(" (ext)") : QString()));
    if (ext)
        return;

    const int nd   = static_cast<int>((msg.ID >> 4) & 0xF);
    const int func = static_cast<int>((msg.ID >> 8) & 0x7);
    const int sub  = static_cast<int>(msg.ID & 0xF);
    if (nd != m_node)
        return;

    if (func == FUNC_STATUS && msg.LEN >= 4) {
        const uint32_t inputs = (uint32_t(msg.DATA[0]) << 24) | (uint32_t(msg.DATA[1]) << 16)
                              | (uint32_t(msg.DATA[2]) << 8)  |  uint32_t(msg.DATA[3]);
        for (int i = 0; i < 32; i++)
            m_pinStates[i] = ((inputs >> i) & 1) != 0;
        emit pinStatesChanged();
    } else if (func == FUNC_ENC && msg.LEN >= 8) {
        const int base = (sub == 1) ? 4 : 0;
        for (int i = 0; i < 4; i++)
            m_encValues[base + i] = static_cast<int16_t>((msg.DATA[2 * i] << 8) | msg.DATA[2 * i + 1]);
        emit encValuesChanged();
    } else if (func == FUNC_ANALOG) {
        if (sub <= 1 && msg.LEN >= 8) {            // letture: 0 -> ch0..3, 1 -> ch4..7
            const int base = (sub == 1) ? 4 : 0;
            for (int i = 0; i < 4; i++)
                m_adcValues[base + i] = ((msg.DATA[2 * i] << 8) | msg.DATA[2 * i + 1]) & 0x0FFF;
            emit adcValuesChanged();
        } else if (sub == 2 && msg.LEN >= 1) {     // bitmap confronto soglie
            m_adcOver = msg.DATA[0];
            emit adcOverChanged();
        }
    }
}

// ---------------------------------------------------------------- utilita'
bool ExpanderController::parseHex(const QString &s, uint32_t *val)
{
    QString t = s.trimmed();
    if (t.startsWith(QLatin1String("0x"), Qt::CaseInsensitive))
        t = t.mid(2);
    bool ok = false;
    const uint v = t.toUInt(&ok, 16);
    if (ok)
        *val = v;
    return ok;
}

QString ExpanderController::hexNum(uint32_t v, int digits)
{
    return QStringLiteral("%1").arg(v, digits, 16, QLatin1Char('0')).toUpper();
}

QString ExpanderController::hexBytes(const uint8_t *d, int len)
{
    QString s;
    for (int i = 0; i < len && i < 8; i++)
        s += hexNum(d[i], 2) + QLatin1Char(' ');
    return s.leftJustified(24);
}

void ExpanderController::log(const QString &s)
{
    emit logLine(QTime::currentTime().toString(QStringLiteral("HH:mm:ss.zzz")) + QStringLiteral("  ") + s);
}
