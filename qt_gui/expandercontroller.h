/*
 * expandercontroller.h  --  Logica di test dell'I/O expander esposta a QML.
 *
 * Parla il protocollo descritto in doc/protocol.md (frame standard 2.0A,
 * ID = FUNC(3) & NODE(4) & SUB(4)) tramite PEAK PCAN-USB.
 */
#pragma once

#include "pcanbasic.h"

#include <QList>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

class ExpanderController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(int node READ node WRITE setNode NOTIFY nodeChanged)
    Q_PROPERTY(QStringList channelNames READ channelNames CONSTANT)
    Q_PROPERTY(QStringList baudNames READ baudNames CONSTANT)
    Q_PROPERTY(QList<bool> pinStates READ pinStates NOTIFY pinStatesChanged)
    Q_PROPERTY(QList<int> encValues READ encValues NOTIFY encValuesChanged)
    Q_PROPERTY(QList<int> adcValues READ adcValues NOTIFY adcValuesChanged)
    Q_PROPERTY(int adcOver READ adcOver NOTIFY adcOverChanged)

public:
    explicit ExpanderController(QObject *parent = nullptr);
    ~ExpanderController() override;

    bool connected() const { return m_connected; }
    int node() const { return m_node; }
    void setNode(int node);
    QStringList channelNames() const;
    QStringList baudNames() const;
    QList<bool> pinStates() const { return m_pinStates; }
    QList<int> encValues() const { return m_encValues; }
    QList<int> adcValues() const { return m_adcValues; }   // -1 = nessuna lettura
    int adcOver() const { return m_adcOver; }

    Q_INVOKABLE void toggleConnection(int channelIndex, int baudIndex);
    Q_INVOKABLE void disconnectBus();

    Q_INVOKABLE bool setDirection(const QString &hexMask);
    Q_INVOKABLE void writeOutputs(const QList<bool> &bits);
    Q_INVOKABLE void requestStatus();
    Q_INVOKABLE bool setEncPeriod(const QString &ms);
    Q_INVOKABLE void resetEncoders();
    Q_INVOKABLE void setThresholds(const QStringList &hexValues);

signals:
    void connectedChanged();
    void nodeChanged();
    void pinStatesChanged();
    void encValuesChanged();
    void adcValuesChanged();
    void adcOverChanged();
    void logLine(const QString &line);
    void errorOccurred(const QString &message);

private:
    void connectBus(int channelIndex, int baudIndex);
    void sendRaw(int func, int sub, const uint8_t *data, int len, const QString &tag);
    void sendPinWord(int func, uint32_t word, const QString &tag);
    void pollRx();
    void process(const pcan::Msg &msg);
    void log(const QString &s);

    static bool parseHex(const QString &s, uint32_t *val);
    static QString hexNum(uint32_t v, int digits);
    static QString hexBytes(const uint8_t *d, int len);

    pcan::Api    m_api;
    pcan::Handle m_channel = pcan::USBBUS1;
    bool         m_connected = false;
    int          m_node = 1;
    QTimer       m_rxTimer;

    QList<bool> m_pinStates = QList<bool>(32, false);
    QList<int>  m_encValues = QList<int>(8, 0);
    QList<int>  m_adcValues = QList<int>(8, -1);
    int         m_adcOver = 0;
};
