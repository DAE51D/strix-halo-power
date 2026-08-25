#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingReply>
#include <QEventLoop>
#include <QMetaType>
#include <QObject>
#include <QTimer>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QVariantList>

static const char *BRIDGE_SERVICE = "com.evox2.powermode";
static const char *BRIDGE_PATH = "/com/evox2/powermode";
static const char *BRIDGE_IFACE = "com.evox2.powermode";
static const char *BACKEND_SERVICE = "com.evox2.powermode.backend";
static const char *BACKEND_PATH = "/com/evox2/powermode";
static const char *BACKEND_IFACE = "com.evox2.powermode";

static QDBusConnection *g_backend = nullptr;

static QVariant callBackend(const QString &method, const QVariantList &args)
{
    QDBusMessage m = QDBusMessage::createMethodCall(BACKEND_SERVICE, BACKEND_PATH, BACKEND_IFACE, method);
    for (const QVariant &a : args)
        m << a;
    QDBusMessage reply = g_backend->call(m);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << "bridge: backend call" << method << "failed:" << reply.errorMessage();
        return QVariant();
    }
    const QVariantList ra = reply.arguments();
    return ra.isEmpty() ? QVariant() : ra.first();
}

// Fire-and-forget: send to the backend without blocking the event loop, so the
// bridge can reply to the caller immediately (the backend's void methods are slow
// to answer and a blocking call would stall our reply).
static void callBackendAsync(const QString &method, const QVariantList &args)
{
    QDBusMessage m = QDBusMessage::createMethodCall(BACKEND_SERVICE, BACKEND_PATH, BACKEND_IFACE, method);
    for (const QVariant &a : args)
        m << a;
    g_backend->asyncCall(m);
}

class Bridge : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "com.evox2.powermode")
public:
    explicit Bridge(QObject *parent = nullptr) : QObject(parent) {}

public slots:
    QString GetMode() { return callBackend("GetMode", {}).toString(); }
    void SetMode(const QString &mode) { callBackendAsync("SetMode", {mode}); }
    QString Cycle() { return callBackend("Cycle", {}).toString(); }
    void Log(const QString &message) { callBackendAsync("Log", {message}); }
    QString Ping() { return QStringLiteral("pong"); }
    void SetQuiet() { callBackendAsync("SetMode", {QStringLiteral("quiet")}); }
    void SetBalanced() { callBackendAsync("SetMode", {QStringLiteral("balanced")}); }
    void SetPerformance() { callBackendAsync("SetMode", {QStringLiteral("performance")}); }
};

// QDBusConnection::connect() (the only signal-subscription API in this Qt build)
// is unreliable, so the bridge polls the backend's Mode property on a short timer
// and re-emits ModeChanged when it detects a change. This keeps the button path
// fast (no 2s widget-poll fallback needed).
class SignalForwarder : public QObject
{
    Q_OBJECT
public:
    explicit SignalForwarder(QObject *parent = nullptr) : QObject(parent), _lastMode(_readMode()) {}

    // Start polling the backend's Mode on a short timer, re-emitting
    // ModeChanged on change. (QDBusConnection::connect() is unreliable in this
    // Qt build — it mis-parses the slot name and fails — so we poll instead.)
    void start(int intervalMs)
    {
        _timer.setInterval(intervalMs);
        connect(&_timer, &QTimer::timeout, this, &SignalForwarder::poll);
        _timer.start();
    }

private slots:
    void poll()
    {
        const QString m = _readMode();
        if (!m.isEmpty() && m != _lastMode) {
            _lastMode = m;
            QDBusMessage out = QDBusMessage::createSignal(BRIDGE_PATH, BRIDGE_IFACE, "ModeChanged");
            out << m << QStringLiteral("poll");
            QDBusConnection::sessionBus().send(out);
        }
    }

private:
    QString _readMode()
    {
        QDBusMessage m = QDBusMessage::createMethodCall(BACKEND_SERVICE, BACKEND_PATH, BACKEND_IFACE, "GetMode");
        QDBusMessage reply = g_backend->call(m, QDBus::Block, 500);
        if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty())
            return _lastMode;
        return reply.arguments().first().toString();
    }

    QString _lastMode;
    QTimer _timer;
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);

    static QDBusConnection backendConn =
        QDBusConnection::connectToBus(QDBusConnection::SessionBus, "pmode-bridge-backend");
    g_backend = &backendConn;
    if (!backendConn.isConnected()) {
        qWarning() << "bridge: could not connect backend to session bus";
        return 1;
    }
    QDBusConnection &backend = backendConn;

    QDBusConnection session = QDBusConnection::sessionBus();
    if (!session.registerService(BRIDGE_SERVICE)) {
        qWarning() << "bridge: failed to register" << BRIDGE_SERVICE;
        return 1;
    }

    Bridge bridge;
    session.registerObject(BRIDGE_PATH, &bridge, QDBusConnection::ExportAllSlots);

    SignalForwarder forwarder;
    forwarder.start(150);

    return app.exec();
}

#include "pmode-bridge.moc"
