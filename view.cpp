/*
    SPDX-FileCopyrightText: 2014 Marco Martin <mart@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "view.h"

#include <QAction>
#include <QClipboard>
#include <QDebug>
#include <QGuiApplication>
#include <QPlatformSurfaceEvent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QScreen>
#include <QPainterPath>
#include <QStandardPaths>
#include <QTimer>
#include <QImage>
#ifdef KRUNNER_SPOTLIGHT_DEVELOPER_PREVIEW
#include <QKeyEvent>
#include <QDir>
#endif

#include <KAuthorized>
#include <KCrash>
#include <KIO/CommandLauncherJob>
#include <KLocalizedString>
#include <KService>
#include <KWindowEffects>
#include <KWindowSystem>
#include <KX11Extras>

#include <LayerShellQt/Window>
#include <algorithm>
#include <qnamespace.h>

#include "appadaptor.h"
#include "x11windowscreenrelativepositioner.h"

KCONFIGGROUP_DECLARE_ENUM_QOBJECT(View, HistoryBehavior)

View::View(PlasmaQuick::SharedQmlEngine *engine, QWindow *)
    : QQuickWindow()
    , m_engine(engine)
    , m_floating(false)
{
    KCrash::initialize();
    setColor(Qt::transparent);
    setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::Tool);

    if (KWindowSystem::isPlatformX11()) {
        m_x11Positioner = new X11WindowScreenRelativePositioner(this);
    }

    // used only by screen readers
    setTitle(i18n("Spotlight"));

    m_config = KConfigGroup(KSharedConfig::openConfig(), u"General"_s);
    m_stateData = KSharedConfig::openConfig(u"krunnerstaterc"_s, //
                                            KConfig::NoGlobals,
                                            QStandardPaths::GenericDataLocation)
                      ->group(u"General"_s);
    m_configWatcher = KConfigWatcher::create(KSharedConfig::openConfig());
    connect(m_configWatcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &group) {
        const QLatin1String pluginsGrp("Plugins");
        if (group.name() == QLatin1String("General")) {
            loadConfig();
        } else if (group.name() == pluginsGrp) {
            Q_EMIT helpEnabledChanged();
        }
    });
    connect(&m_consumer, &KActivities::Consumer::currentActivityChanged, this, &View::activityChanged);
    Q_EMIT activityChanged(m_consumer.currentActivity());

    loadConfig();

    new AppAdaptor(this);
    QDBusConnection::sessionBus().registerObject(u"/App"_s, this);

    connect(m_engine, &PlasmaQuick::SharedQmlEngine::finished, this, &View::objectIncubated);
    m_engine->setSourceFromModule("org.kde.krunner.private.view", "RunCommand");
    m_engine->completeInitialization({
        {u"runnerWindow"_s, QVariant::fromValue(this)},
    });

    auto screenRemoved = [this](QScreen *screen) {
        if (screen == this->screen()) {
            setScreen(qGuiApp->primaryScreen());
            hide();
        }
    };

    connect(qGuiApp, &QGuiApplication::screenRemoved, this, screenRemoved);
    connect(qGuiApp, &QGuiApplication::focusWindowChanged, this, &View::slotFocusWindowChanged);
}

View::~View() = default;

void View::setMainItem(QQuickItem *item)
{
    m_mainItem = item;
    item->setParentItem(contentItem());
    connect(this, &QQuickWindow::widthChanged, item, [this]() { m_mainItem->setWidth(width()); });
    connect(this, &QQuickWindow::heightChanged, item, [this]() { m_mainItem->setHeight(height()); });
}

void View::refreshGlassRegion()
{
    if (!m_mainItem || m_glassUpdatePending) return;
    m_glassUpdatePending = true;
    QTimer::singleShot(16, this, [this]() {
        m_glassUpdatePending = false;
        updateGlassRegion();
    });
}

// Match GlassPanel.qml's continuous cubic geometry rather than approximating
// the surface with Qt's circular rounded rectangles. The blur and input masks
// should follow the actual QML path, particularly around 30.75pt corners.
static QPainterPath glassPath(const QRectF &bounds, qreal requestedRadius, qreal cornerFactor, qreal pathInset)
{
    // These are deliberately the exact path coordinates in GlassPanel.qml.
    // QML uses an inset left edge but the top starts at r (not inset + r);
    // don't substitute QPainterPath::addRoundedRect or shift raster edges.
    const qreal inset = std::max<qreal>(0, pathInset);
    const qreal x = bounds.left(), y = bounds.top();
    const qreal w = bounds.width() - inset * 2;
    const qreal h = bounds.height() - inset * 2;
    QPainterPath path;
    if (w <= 0 || h <= 0) return path;
    const qreal r = std::min(std::max<qreal>(0, requestedRadius), h / 2);
    const qreal c = r * std::clamp(cornerFactor, qreal(0), qreal(1));
    path.moveTo(x + r, y + inset);
    path.lineTo(x + w - r, y + inset);
    path.cubicTo(x + w - r + c, y + inset, x + w, y + r - c, x + w, y + r);
    path.lineTo(x + w, y + h - r);
    path.cubicTo(x + w, y + h - r + c, x + w - r + c, y + h, x + w - r, y + h);
    path.lineTo(x + r, y + h);
    path.cubicTo(x + r - c, y + h, x + inset, y + h - r + c, x + inset, y + h - r);
    path.lineTo(x + inset, y + r);
    path.cubicTo(x + inset, y + r - c, x + r - c, y + inset, x + r, y + inset);
    path.closeSubpath();
    return path;
}

void View::updateGlassRegion()
{
    if (!mainItem()) return;
    QRegion region;
    for (auto *item : mainItem()->findChildren<QQuickItem *>()) {
        if (item->objectName() != QStringLiteral("spotlightGlass") || !item->isVisible()) continue;
        const auto topLeft = item->mapToItem(contentItem(), QPointF(0, 0));
        const QRectF bounds(topLeft, item->size());
        const bool continuous = item->property("cornerFactor").isValid();
        QPainterPath path;
        if (continuous) {
            path = glassPath(bounds, item->property("radius").toReal(),
                             item->property("cornerFactor").toReal(),
                             item->property("pathInset").toReal());
        } else {
            path.addRoundedRect(bounds, item->property("radius").toReal(), item->property("radius").toReal());
        }
        region += QRegion(path.toFillPolygon().toPolygon());
    }
    setMask(region); // Reserved transparent space must not intercept desktop input.
    KWindowEffects::enableBlurBehind(this, true, region);
}


QMargins View::margins()
{
    if (m_floating) {
        const QRect r = screen()->availableGeometry();
        return QMargins({0, r.height() / 3, 0, 0});
    } else {
        return {}; // Zeros
    }
}

void View::objectIncubated()
{
    auto item = qobject_cast<QQuickItem *>(m_engine->rootObject());
    if (!item) { qCritical() << "Custom Spotlight QML failed to load"; QCoreApplication::quit(); return; }
    setMainItem(item);

    auto updateSize = [this]() {
        resize(QSize(mainItem()->implicitWidth(), mainItem()->implicitHeight()).boundedTo(screen()->availableSize().shrunkBy(margins())));
        refreshGlassRegion();
    };

    connect(item, &QQuickItem::implicitHeightChanged, this, updateSize);
    connect(item, &QQuickItem::implicitWidthChanged, this, updateSize);
    updateSize();
#ifdef KRUNNER_SPOTLIGHT_DEVELOPER_PREVIEW
    // Developer-only; excludes screenshots and synthetic keyboard events from release binaries.
    if (qEnvironmentVariableIsSet("KRUNNER_SPOTLIGHT_MORPH_TEST")) {
        QTimer::singleShot(800, this, [this]() {
            querySingleRunner(QStringLiteral("krunner_services"), QStringLiteral("k"));
            QTimer::singleShot(1100, this, [this]() { mainItem()->setProperty("query", QString()); });
            for (int delay : {0, 80, 160, 260, 400, 800, 1150, 1250, 1450}) {
                QTimer::singleShot(delay, this, [this, delay]() {
                    auto *surface = mainItem()->findChild<QQuickItem *>(QStringLiteral("spotlightGlass"));
                    auto *field = mainItem()->findChild<QQuickItem *>(QStringLiteral("spotlightQuery"));
                    qInfo() << "Morph sample" << delay << "surface" << surface << "height" << surface->height()
                            << "query position" << field->mapToItem(contentItem(), QPointF()) << "native height" << height();
                    const QString previewDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
                    grabWindow().save(QDir(previewDir).filePath(QStringLiteral("spotlight-morph-%1.png").arg(delay)));
                });
            }
        });
    }
    const QString preview = qEnvironmentVariable("KRUNNER_SPOTLIGHT_PREVIEW");
    if (!preview.isEmpty()) {
        if (qEnvironmentVariableIsSet("KRUNNER_SPOTLIGHT_REVEAL_PREVIEW")) {
            QTimer::singleShot(1500, this, [this]() { mainItem()->setProperty("railActive", true); });
        }
        if (qEnvironmentVariableIsSet("KRUNNER_SPOTLIGHT_TRACE_ROWS")) {
            auto *probe = new QTimer(this);
            connect(probe, &QTimer::timeout, this, [this]() {
                auto walk = [this](auto &&self, QQuickItem *item) -> void {
                    if (item->objectName() == QStringLiteral("spotlightResult")) {
                        qInfo() << "Result geometry" << item->property("index") << item->property("debugTitle")
                                << "position" << item->mapToItem(mainItem(), QPointF())
                                << "size" << item->size() << "visible" << item->isVisible();
                    }
                    for (auto *child : item->childItems()) self(self, child);
                };
                walk(walk, mainItem());
            });
            probe->start(1000);
            QTimer::singleShot(30000, probe, &QObject::deleteLater);
        }
        const QString previewQuery = qEnvironmentVariable("KRUNNER_SPOTLIGHT_PREVIEW_QUERY");
        if (!previewQuery.isEmpty()) {
            QTimer::singleShot(500, this, [this, previewQuery]() {
                if (qEnvironmentVariable("KRUNNER_SPOTLIGHT_PREVIEW_RUNNER") == QStringLiteral("all")) {
                    query(previewQuery);
                } else {
                    querySingleRunner(QStringLiteral("krunner_services"), previewQuery);
                }
            });
        }
        if (qEnvironmentVariableIsSet("KRUNNER_SPOTLIGHT_PREVIEW_DOWN")) {
            QTimer::singleShot(6000, this, [this]() {
                const int presses = std::clamp(qEnvironmentVariableIntValue("KRUNNER_SPOTLIGHT_PREVIEW_DOWN"), 1, 15);
                auto *target = mainItem()->findChild<QQuickItem *>(QStringLiteral("spotlightQuery"));
                if (!target) return;
                target->forceActiveFocus();
                for (int i = 0; i < presses; ++i) {
                    QKeyEvent press(QEvent::KeyPress, Qt::Key_Down, Qt::NoModifier);
                    QCoreApplication::sendEvent(target, &press);
                    QKeyEvent release(QEvent::KeyRelease, Qt::Key_Down, Qt::NoModifier);
                    QCoreApplication::sendEvent(target, &release);
                }
                qInfo() << "Preview Arrow Down presses:" << presses << "keyboard selection:" << mainItem()->property("highlightSelection");
            });
        }
        QTimer::singleShot(previewQuery.isEmpty() ? 2500 : 8000, this, [this, preview]() {
            const auto image = grabWindow();
            qInfo() << "Spotlight preview saved:" << image.save(preview) << "results:" << mainItem()->property("resultCount") << "rail:" << mainItem()->property("railActive") << "capsule:" << mainItem()->property("capsuleWidth");
        });
    }
#endif
}

void View::slotFocusWindowChanged()
{
    if (QGuiApplication::focusWindow() && m_requestedClipboardSelection) {
        displayWithClipboardContents();
    }

    if (!QGuiApplication::focusWindow() && !m_pinned) {
        setVisible(false);
    }
}

bool View::freeFloating() const
{
    return m_floating;
}

void View::setFreeFloating(bool floating)
{
    m_floating = floating;
    if (m_floating) {
        KWindowEffects::slideWindow(this, KWindowEffects::NoEdge);

    } else {
        KWindowEffects::slideWindow(this, KWindowEffects::TopEdge);

    }

    positionOnScreen();
}

void View::loadConfig()
{
    setFreeFloating(m_config.readEntry("FreeFloating", true));
    setRetainPriorSearch(m_config.readEntry("RetainPriorSearch", true));
    setPinned(m_stateData.readEntry("Pinned", false));
    setHistoryBehavior(m_config.readEntry("historyBehavior", m_historyBehavior));
}

void View::showEvent(QShowEvent *event)
{
    if (KWindowSystem::isPlatformX11()) {
        KX11Extras::setOnAllDesktops(winId(), true);
    }
    QQuickWindow::showEvent(event);
    updateGlassRegion();
    requestActivate();
    if (KWindowSystem::isPlatformX11()) {
        KX11Extras::forceActiveWindow(winId());
    }
}

void View::positionOnScreen()
{
    const auto screens = QGuiApplication::screens();
    auto screenIt = screens.cend();
    if (KWindowSystem::isPlatformWayland() && m_floating) {
        auto message = QDBusMessage::createMethodCall(u"org.kde.KWin"_s, u"/KWin"_s, u"org.kde.KWin"_s, u"activeOutputName"_s);
        QDBusReply<QString> reply = QDBusConnection::sessionBus().call(message);
        if (reply.isValid()) {
            const QString activeOutputName = reply.value();
            screenIt = std::ranges::find_if(screens, [&activeOutputName](QScreen *screen) {
                return screen->name() == activeOutputName;
            });
        }
    } else if (KWindowSystem::isPlatformX11()) {
        screenIt = std::ranges::find_if(screens, [](QScreen *screen) {
            return screen->geometry().contains(QCursor::pos(screen));
        });
    }

    QScreen *const shownOnScreen = screenIt != screens.cend() ? *screenIt : QGuiApplication::primaryScreen();
    setScreen(shownOnScreen);

    if (KWindowSystem::isPlatformWayland()) {
        auto layerWindow = LayerShellQt::Window::get(this);
        layerWindow->setAnchors(LayerShellQt::Window::AnchorTop);
        layerWindow->setLayer(LayerShellQt::Window::LayerTop);
        layerWindow->setScope(u"krunner"_s);
        layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        layerWindow->setMargins(margins());
        if (m_floating) {
            layerWindow->setScreen(shownOnScreen);
        } else {
            layerWindow->setWantsToBeOnActiveScreen(true);
        }
    } else if (KWindowSystem::isPlatformX11()) {
        m_x11Positioner->setAnchors(Qt::TopEdge);
        m_x11Positioner->setMargins(margins());
        if (m_floating) {
            KX11Extras::setOnDesktop(winId(), KX11Extras::currentDesktop());
        } else {
            KX11Extras::setOnAllDesktops(winId(), true);
        }
        KX11Extras::setState(winId(), NET::SkipTaskbar | NET::SkipPager);
    }
}

void View::toggleDisplay()
{
    if (isVisible() && !QGuiApplication::focusWindow() && KWindowSystem::isPlatformX11()) {
        KX11Extras::forceActiveWindow(winId());
        return;
    }
    if (isVisible()) {
        setVisible(false);
    } else {
        display();
    }
}

void View::openClipboardHistory()
{
    auto message = QDBusMessage::createMethodCall(u"org.kde.klipper"_s, u"/klipper"_s,
                                                 u"org.kde.klipper.klipper"_s, u"showKlipperPopupMenu"_s);
    QDBusConnection::sessionBus().asyncCall(message);
}

void View::display()
{
    positionOnScreen();
    setVisible(true);
}

void View::displaySingleRunner(const QString &runnerName)
{
    display();

    m_engine->rootObject()->setProperty("singleRunner", runnerName);
    m_engine->rootObject()->setProperty("query", QString());
}

void View::displayWithClipboardContents()
{
    display();

    // On Wayland we cannot retrieve the clipboard selection until we get the focus
    if (QGuiApplication::focusWindow()) {
        m_requestedClipboardSelection = false;
        m_engine->rootObject()->setProperty("singleRunner", QString());
        m_engine->rootObject()->setProperty("query", QGuiApplication::clipboard()->text(QClipboard::Selection));
    } else {
        m_requestedClipboardSelection = true;
    }
}

void View::query(const QString &term)
{
    display();

    m_engine->rootObject()->setProperty("singleRunner", QString());
    m_engine->rootObject()->setProperty("query", term);
}

void View::querySingleRunner(const QString &runnerName, const QString &term)
{
    display();

    m_engine->rootObject()->setProperty("singleRunner", runnerName);
    m_engine->rootObject()->setProperty("query", term);
}

bool View::pinned() const
{
    return m_pinned;
}

void View::setPinned(bool pinned)
{
    if (m_pinned != pinned) {
        m_pinned = pinned;
        m_stateData.writeEntry("Pinned", pinned);
        Q_EMIT pinnedChanged();
    }
}

#include "moc_view.cpp"
