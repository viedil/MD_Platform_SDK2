# 06 UI and Workflow Engine Module

## 1. Purpose
Provides a declarative framework for building medical device user interfaces and managing clinical workflows (state machines) with strict usability compliance.

## 2. Safety Classification (IEC 62304)
- **Safety Class**: B (UI confusion could lead to operator error; workflow enforcement prevents unsafe states).
- **Critical Functions**: Alarm visibility, lockout prevention, workflow state transitions.

## 3. Architecture
- **Declarative UI**: QML-based or custom DSL for defining screens, bindings, and animations.
- **Workflow State Machine**: Centralized engine enforcing valid clinical sequences (e.g., Patient Check-in → Scan → Review → Save).
- **Theme Engine**: Supports high-contrast modes for OR environments and dark mode for ultrasound.

## 4. Usability Compliance (IEC 62366)
- **Alarm Prioritization**: Color/size coding per IEC 60601-1-8 (Red=Critical, Yellow=Warning).
- **Touch Targets**: Minimum 10mm touch area for sterile glove operation.
- **Undo/Confirm**: Destructive actions require explicit confirmation or support undo.

## 5. x86 Mock Strategy
- **Desktop Renderer**: Runs full UI on Qt/X11 or Wayland for development.
- **Workflow Simulator**: CLI tool to step through state machine transitions programmatically.
- **Input Mocking**: Simulates touch events from mouse clicks; simulates hardware knobs via keyboard.

## 6. API Specification
```cpp
class IWorkflowEngine {
public:
    virtual Result<void> transitionTo(const std::string& stateId, const Context& ctx) = 0;
    virtual void registerGuard(const std::string& transition, std::function<bool()> guard) = 0;
    virtual std::string getCurrentState() const = 0;
};
```

## 7. Verification Requirements
- [ ] Verify UI frame rate remains > 30fps during heavy data updates.
- [ ] Verify workflow guards prevent invalid state transitions 100% of the time.
- [ ] Verify alarm visibility meets contrast ratios per IEC 62366.
