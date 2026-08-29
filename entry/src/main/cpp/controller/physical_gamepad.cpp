#include "physical_gamepad.h"

#include "controller_hub.h"
#include "controller_runtime.h"
#include "controller_types.h"

namespace winehua {
namespace controller {
namespace {

LogicalButton MapOhButton(int code)
{
    switch (code) {
        case 2301: return LogicalButton::A;
        case 2302: return LogicalButton::B;
        case 2304: return LogicalButton::X;
        case 2305: return LogicalButton::Y;
        case 2307: return LogicalButton::LB;
        case 2308: return LogicalButton::RB;
        case 2309: return LogicalButton::LB; // L2 button → also drive LT via SetAxis below
        case 2310: return LogicalButton::RB;
        case 2311: return LogicalButton::Back;
        case 2312: return LogicalButton::Start;
        case 2313: return LogicalButton::L3;
        case 2314: return LogicalButton::R3;
        case 2315: return LogicalButton::Guide;
        case 2012: return LogicalButton::DpadUp;
        case 2013: return LogicalButton::DpadDown;
        case 2014: return LogicalButton::DpadLeft;
        case 2015: return LogicalButton::DpadRight;
        default: return LogicalButton::Count;
    }
}

}  // namespace

void PhysicalFeedButton(int ohButtonCode, bool pressed)
{
    if (!ControllerHub::Instance().IsEnabled()) return;
    // Trigger buttons: prefer axis; also set axis 1.0/0 as fallback.
    if (ohButtonCode == 2309) {
        ControllerHub::Instance().SetAxis(ControllerSourceId::Physical, 0, LogicalAxis::LT,
                                          pressed ? 1.f : 0.f);
        return;
    }
    if (ohButtonCode == 2310) {
        ControllerHub::Instance().SetAxis(ControllerSourceId::Physical, 0, LogicalAxis::RT,
                                          pressed ? 1.f : 0.f);
        return;
    }
    const LogicalButton btn = MapOhButton(ohButtonCode);
    if (btn == LogicalButton::Count) return;
    ControllerHub::Instance().SetButton(ControllerSourceId::Physical, 0, btn, pressed);
}

void PhysicalFeedAxis(int axisType, double x, double y)
{
    if (!ControllerHub::Instance().IsEnabled()) return;
    auto& hub = ControllerHub::Instance();
    // Kit: +Y often Down; Hub wants +Y=Up — flip once here.
    const float fx = static_cast<float>(x);
    const float fy = static_cast<float>(-y);
    switch (axisType) {
        case 0: // left stick
            hub.SetAxis(ControllerSourceId::Physical, 0, LogicalAxis::LX, fx);
            hub.SetAxis(ControllerSourceId::Physical, 0, LogicalAxis::LY, fy);
            break;
        case 1: // right stick
            hub.SetAxis(ControllerSourceId::Physical, 0, LogicalAxis::RX, fx);
            hub.SetAxis(ControllerSourceId::Physical, 0, LogicalAxis::RY, fy);
            break;
        case 2: { // hat / dpad axis — values typically -1..1
            const int8_t hx = (x < -0.5) ? -1 : (x > 0.5 ? 1 : 0);
            // Kit Y: down positive → Hub up positive after flip
            const int8_t hy = (fy < -0.5f) ? -1 : (fy > 0.5f ? 1 : 0);
            hub.SetHat(ControllerSourceId::Physical, 0, hx, hy);
            break;
        }
        case 3: // LT brake [0,1]
            hub.SetAxis(ControllerSourceId::Physical, 0, LogicalAxis::LT, static_cast<float>(x));
            break;
        case 4: // RT gas
            hub.SetAxis(ControllerSourceId::Physical, 0, LogicalAxis::RT, static_cast<float>(x));
            break;
        default:
            break;
    }
}

void PhysicalFeedDevice(bool connected)
{
    if (!connected) {
        ControllerHub::Instance().ResetSource(ControllerSourceId::Physical);
    }
}

}  // namespace controller
}  // namespace winehua
