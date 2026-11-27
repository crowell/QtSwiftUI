import QtBridge
@_spi(Reflection) import Swift
@_exported import Observation

enum Part: Hashable {
    case type(ObjectIdentifier), position(Int), id(AnyHashable), property(String), widget(UInt32)
}

@MainActor struct Context {
    let host: Host
    var path: [Part] = []
    var parent: UnsafeMutableRawPointer?
    var verticalViewport: UnsafeMutableRawPointer?
    var presentation: PresentationInteraction?
    var registerScrollArea: [(ScrollAreaTargets) -> Void] = []
    var scrollTargets: ScrollAreaTargets?
    var isScrollTargetLayout = false
    var scrollConfiguration = ScrollConfiguration()
    var collectingPickerLabels = false
    var defaultFocusRegions: [DefaultFocusRegion] = []
    var menuEntries: MenuEntries?
    var windowValue: Binding<AnyHashable?>?
    @EnvironmentSnapshot var environment = EnvironmentValues()
    var preferences: [ObjectIdentifier: any PreferenceScope] = [:]
    var transaction = Transaction()
    var animation: Animation? {
        get { transaction.animation }
        set { transaction.animation = newValue }
    }
    var spaces: [AnyHashable: NamedOrigin] = [:]
    var windowOffset: CGPoint {
        guard let parent else { return .zero }
        let position = qs_origin(parent)
        return CGPoint(x: position.width, y: position.height)
    }
    func descending(_ part: Part) -> Self {
        var result = self
        result.path.append(part)
        return result
    }
    func preparing<Owner>(_ original: Owner) -> Owner {
        var owner = original
        func update<P: DynamicProperty>(_ property: P, at name: String) -> P {
            let child = descending(.property(name))
            var result = property
            if var builtIn = result as? any MountedProperty {
                builtIn.install(in: child)
                result = builtIn as! P
            } else {
                result = child.preparing(result)
            }
            result.update()
            return result
        }
        // Stored-property key paths preserve value semantics when a custom
        // DynamicProperty's mutating update() changes its own fields.
        // Swift 6.2 declares the ignoreUnknown flag as mutable global state.
        // Skip closure fields so the remaining property wrappers still get writable key paths.
        let ignoreUnknown = _EachFieldOptions(rawValue: 1 << 1)
        let enumerated = _forEachFieldWithKeyPath(of: Owner.self, options: ignoreUnknown) { name, key in
            if let property = owner[keyPath: key] as? any DynamicProperty {
                @MainActor func assign<P: DynamicProperty>(_ property: P) {
                    let updated = update(property, at: String(cString: name))
                    if let writable = key as? WritableKeyPath<Owner, P> { owner[keyPath: writable] = updated }
                }
                assign(property)
            }
            return true
        }
        if !enumerated {
            for (name, value) in Mirror(reflecting: owner).children {
                if let name, let property = value as? any DynamicProperty { _ = update(property, at: name) }
            }
        }
        return owner
    }
    func widget(_ kind: QSKind, pressed: ((Bool) -> Void)? = nil, exitCommand: (() -> Void)? = nil,
                cursorChanged: ((UnsafeMutableRawPointer) -> Void)? = nil,
                tap: ((UnsafeMutableRawPointer) -> Void)? = nil, transfer: TransferAction? = nil,
                adjustment: ((AccessibilityAdjustmentDirection) -> Void)? = nil,
                drag: ((QSDragSample, UnsafeMutableRawPointer) -> Void)? = nil,
                magnify: ((QSMagnifySample) -> Void)? = nil,
                accessibilityAction: ((String) -> Void)? = nil, cancelGesture: (() -> Void)? = nil, hover: ((Bool) -> Void)? = nil,
                continuousHover: ((UnsafeMutableRawPointer, Bool) -> Void)? = nil, action: ((String) -> Void)? = nil) -> UnsafeMutableRawPointer {
        let entry = host.mount(path: path + [.widget(kind.rawValue)], kind: kind, parent: parent)
        switch kind {
        case QSEdit, QSSecureEdit, QSMultilineField, QSTextEditor, QSRichEditor:
            qs_submit_label(entry.widget, environment.submitLabel?.key ?? QSEnterDefault)
            qs_autocorrection(entry.widget, environment.autocorrectionDisabled ? 1 : 0)
        default: break
        }
        host.keys.install(environment.keyPressHandlers, for: entry.id)
        host.transfers[entry.id] = transfer
        if let drag { host.drags[entry.id] = { drag($0, entry.widget) } }
        else { host.drags[entry.id] = nil }
        if !host.isMeasuringAlternative { host.focusScopes.include(entry.widget, environment: environment) }
        let focus = environment.focus
        if !host.isMeasuringAlternative { host.defaultFocus.include(id: entry.id, widget: entry.widget, regions: defaultFocusRegions, focus: focus) }
        let submit = environment.submit
        host.events[entry.id] = { [weak host] kind, value in
            switch kind {
            case QSActivate:
                tap?(entry.widget)
                action?(value)
            case QSCursorChanged: cursorChanged?(entry.widget)
            case QSAccessibilityAction: accessibilityAction?(value)
            case QSIncrement: adjustment?(.increment)
            case QSDecrement: adjustment?(.decrement)
            case QSFocusChanged:
                if value != "0", let host, host.defaultFocus.entered(id: entry.id, reason: value) { host.update() }
                focus?.change(value != "0")
            case QSSubmit: submit?(.text)
            case QSMagnified: magnify?(qs_magnify_sample(entry.widget))
            case QSGestureCancelled: cancelGesture?()
            case QSExitCommand: exitCommand?()
            case QSHoverChanged: hover?(value == "1")
            case QSContinuousHover: continuousHover?(entry.widget, value == "1")
            case QSPressedChanged: pressed?(value == "1")
            default: break
            }
        }
        if kind != QSSurface && kind != QSCanvas && kind != QSRaster { qs_hit_testing(entry.widget, environment.allowsHits ? 1 : 0) }
        qs_direction(entry.widget, environment.layoutDirection == .rightToLeft ? 1 : 0)
        qs_enabled(entry.widget, environment.isEnabled ? 1 : 0)
        qs_accessibility(entry.widget, environment.label, environment.identifier, environment.accessibleHint,
                         environment.accessibilityTraits.contains(.isSearchField) ? 1 : 0)
        if kind == QSGroup || kind == QSButton || kind == QSMenuButton || kind == QSLink {
            let traits = environment.accessibilityTraits
            if kind == QSGroup { qs_direct_touch(entry.widget, traits.contains(.allowsDirectInteraction) ? 1 : 0) }
            qs_accessible_control(entry.widget, traits.contains(.isSelected) ? 1 : 0,
                                  traits.contains(.isButton) ? 1 : 0, traits.contains(.isToggle) ? 1 : 0,
                                  traits.contains(.isLink) || (kind == QSLink && !environment.removedAccessibilityTraits.contains(.isLink)) ? 1 : 0,
                                  traits.contains(.startsMediaSession) ? 1 : 0)
        }
        qs_help(entry.widget, environment.helpText)
        qs_focus_effect(entry.widget, environment.isFocusEffectEnabled ? 1 : 0)
        if let focus { host.afterLayout { qs_focus(entry.widget, focus.active() ? 1 : 0) } }
        return entry.widget
    }
}

@Observable private final class ObservationPass { var revision = 0 }

@MainActor final class Host {
    private let observationPass = ObservationPass()
    struct Mount {
        let widget: UnsafeMutableRawPointer
        let id: Int32
    }
    private var mounts: [[Part]: Mount] = [:]
    private var liveMounts = Set<[Part]>()
    private var nextID: Int32 = 0
    var storage: [[Part]: AnyObject] = [:]
    var liveStorage = Set<[Part]>()
    private var disappear: [[Part]: () -> Void] = [:]
    private var nextDisappear: [[Part]: () -> Void] = [:]
    let matches = GeometryMatches()
    let transitions = ViewTransitions()
    private var pendingTransaction: Transaction?
    var hasMaterial = false
    var resizability: WindowResizability?
    private var afterRender: [() -> Void] = []
    // Fitting a candidate may need Qt font and control metrics. Only the chosen
    // branch keeps its widgets and receives focus, lifecycle and layout callbacks.
    private(set) var isMeasuringAlternative = false
    func measuringAlternative<T>(_ measure: () -> T) -> T {
        let previous = isMeasuringAlternative
        isMeasuringAlternative = true
        defer { isMeasuringAlternative = previous }
        return measure()
    }
    func afterLayout(_ action: @escaping () -> Void) {
        if !isMeasuringAlternative { afterRender.append(action) }
    }
    func lifetime(at path: [Part], appear: @escaping () -> Void, disappear action: @escaping () -> Void) {
        guard !isMeasuringAlternative else { return }
        if disappear[path] == nil && nextDisappear[path] == nil { afterRender.append(appear) }
        nextDisappear[path] = action
    }
    let subscriptions = ViewSubscriptions()
    let focusScopes = WindowFocusScopes()
    let defaultFocus = WindowDefaultFocus()
    let keys = WindowKeyPresses()
    var transfers: [Int32: TransferAction] = [:]
    var drags: [Int32: (QSDragSample) -> Void] = [:]
    var events: [Int32: (QSEventKind, String) -> Void] = [:]
    private let content: (Context) -> [Element]
    private(set) var window: OpaquePointer!

    private let animationClock: () -> TimeInterval
    private(set) var frameTime: TimeInterval = 0

    /// App-scoped dynamic properties persist independently of native window render passes.
    init() {
        content = { _ in [] }
        animationClock = { ProcessInfo.processInfo.systemUptime }
    }

    init(title: String, animationClock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         content: @escaping (Context) -> [Element]) {
        self.animationClock = animationClock
        self.content = content
        window = qs_window(title, Unmanaged.passUnretained(self).toOpaque(), { pointer, width, height in
            MainActor.assumeIsolated {
                Unmanaged<Host>.fromOpaque(pointer!).takeUnretainedValue().render(width: Int(width), height: Int(height))
            }
        }, { pointer, id, kind, value in
            let string = value.map { String(cString: $0) } ?? ""
            MainActor.assumeIsolated { Unmanaged<Host>.fromOpaque(pointer!).takeUnretainedValue().events[id]?(kind, string) }
        })
        qs_set_key_handler(window) { pointer, id, phase, chars, modifiers in
            let characters = String(cString: chars!)
            guard let first = characters.first else { return 0 }
            let key = KeyPress(phase: .init(rawValue: Int(phase)), key: KeyEquivalent(first),
                               characters: characters, modifiers: .init(rawValue: Int(modifiers)))
            return MainActor.assumeIsolated {
                Unmanaged<Host>.fromOpaque(pointer!).takeUnretainedValue().keys.dispatch(key, to: id) == .handled ? 1 : 0
            }
        }
        qs_transfer_handler(window) { pointer, id, phase, mime, x, y in
            MainActor.assumeIsolated {
                let host = Unmanaged<Host>.fromOpaque(pointer!).takeUnretainedValue()
                return host.transfers[id]?.handle(phase, mime: mime, point: CGPoint(x: x, y: y)) == true ? 1 : 0
            }
        }
        qs_set_drag_handler(window) { pointer, id, sample in
            MainActor.assumeIsolated { Unmanaged<Host>.fromOpaque(pointer!).takeUnretainedValue().drags[id]?(sample) }
        }
    }
    private var didClose: (() -> Void)?
    func observeClose(_ callback: @escaping () -> Void) {
        didClose = callback
        qs_observe_close(window) { pointer in
            guard let pointer else { return }
            let host = Unmanaged<Host>.fromOpaque(pointer).takeUnretainedValue()
            Task { @MainActor in host.didClose?() }
        }
    }

    func open(width: Int, height: Int) { qs_open(window, Int32(width), Int32(height)) }
    func close() {
        didClose = nil
        focusScopes.begin()
        if let window { qs_close(window); self.window = nil }
        subscriptions.close()
        for stop in disappear.values { stop() }
        disappear.removeAll()
        observationPass.revision += 1
        mounts.removeAll()
        events.removeAll()
        drags.removeAll()
        transfers.removeAll()
        keys.reset()
        storage.removeAll()
    }
    var onUpdate: ((Transaction?) -> Void)?
    func update(transaction: Transaction? = nil) {
        if let onUpdate { onUpdate(transaction); return }
        if let transaction { pendingTransaction = transaction }
        if let window { qs_update(window) }
    }
    func mount(path: [Part], kind: QSKind, parent: UnsafeMutableRawPointer?) -> Mount {
        if !isMeasuringAlternative { liveMounts.insert(path) }
        if let entry = mounts[path] { return entry }
        nextID += 1
        let entry = Mount(widget: qs_create(window, parent, kind, nextID)!, id: nextID)
        mounts[path] = entry
        return entry
    }
    private func render(width: Int, height: Int) {
        let viewport = CGSize(width: width, height: height)
        _ = render(proposal: ProposedViewSize(viewport), viewport: viewport, scale: qs_window_scale(window))
    }

    func render(proposal: ProposedViewSize, viewport: CGSize?, scale: CGFloat) -> CGSize {
        frameTime = animationClock()
        transitions.begin()
        defaultFocus.begin()
        focusScopes.begin()
        liveMounts.removeAll(keepingCapacity: true)
        liveStorage.removeAll(keepingCapacity: true)
        nextDisappear.removeAll(keepingCapacity: true)
        // Changing this tracked value releases the previous pass’s one-shot observation.
        observationPass.revision += 1
        let revision = observationPass.revision
        var size = CGSize.zero
        withObservationTracking {
            _ = observationPass.revision
            size = layout(proposal: proposal, viewport: viewport, scale: scale)
        } onChange: { [weak self] in
            let transaction = Transaction.current
            Task { @MainActor in
                guard let self, self.observationPass.revision == revision else { return }
                self.update(transaction: transaction)
            }
        }
        subscriptions.commit()
        let ended = disappear.filter { nextDisappear[$0.key] == nil }
        disappear = nextDisappear
        for action in ended.values { action() }
        if viewport != nil {
            focusScopes.finish(window: window)
            defaultFocus.finish(window: window)
        }
        let pending = afterRender
        afterRender.removeAll(keepingCapacity: true)
        for action in pending { action() }
        return size
    }

    private func layout(proposal: ProposedViewSize, viewport: CGSize?, scale: CGFloat) -> CGSize {
        var context = Context(host: self)
        context.environment.focusReset = ResetFocusAction { [weak focusScopes] namespace in
            if Thread.isMainThread { MainActor.assumeIsolated { focusScopes?.reset(in: namespace) } }
            else { Task { @MainActor [weak focusScopes] in focusScopes?.reset(in: namespace) } }
        }
        context.environment.colorScheme = qs_dark_appearance() != 0 ? .dark : .light
        context.transaction = pendingTransaction ?? Transaction()
        pendingTransaction = nil
        switch qs_scene_phase(window) {
        case 2: context.environment.scenePhase = .active
        case 1: context.environment.scenePhase = .inactive
        default: context.environment.scenePhase = .background
        }
        if viewport != nil {
            switch qs_control_active_state(window) {
            case 2: context.environment.controlActiveState = .key
            case 1: context.environment.controlActiveState = .active
            default: context.environment.controlActiveState = .inactive
            }
        }
        context.environment.isPresented = viewport != nil
        context.environment.displayScale = scale
        context.environment.accessibilityReduceMotion = qs_reduce_motion(window) != 0
        context.environment.closePresentation = { [weak self] in
            if let window = self?.window { qs_request_close(window) }
        }
        hasMaterial = false
        qs_shortcut_begin(window)
        let windowControls = viewport == nil ? nil : context.readPreference(WindowControls.self)
        let roots = content(context)
        let root = stacked(roots, axis: .vertical, alignment: .center, spacing: 8)
        if let resizability, let viewport {
            let minimum = CGSize(width: root.measure(.init(width: 0, height: viewport.height)).width,
                                 height: root.measure(.init(width: viewport.width, height: 0)).height)
            let maximum = resizability.restrictMaximum ? root.measure(.infinity) : CGSize(width: CGFloat.infinity, height: .infinity)
            qs_window_limits(window, minimum.width, minimum.height, maximum.width, maximum.height)
        }
        let size = root.measure(proposal)
        let extent = viewport ?? size
        let drawable = viewport != nil || qs_snapshot_size(window, size.width, size.height) != 0
        if drawable {
            root.place(CGRect(x: (extent.width - size.width) / 2, y: (extent.height - size.height) / 2,
                              width: size.width, height: size.height), proposal)
            matches.place(at: frameTime, window: window)
        }
        transitions.finish(host: self, transaction: context.transaction)
        // Qt owns descendant widgets. Release stale descendants before their scroll area.
        for path in mounts.keys.filter({ !liveMounts.contains($0) }).sorted(by: { $0.count > $1.count }) {
            if let mount = mounts.removeValue(forKey: path) {
                events[mount.id] = nil
                drags[mount.id] = nil
                transfers[mount.id] = nil
                keys.install([], for: mount.id)
                qs_destroy(mount.widget)
            }
        }
        if hasMaterial && drawable { qs_window_materials(window) }
        windowControls?().apply(to: window)
        qs_shortcut_finish(window)
        storage = storage.filter { liveStorage.contains($0.key) }
        return drawable ? size : .zero
    }
}

public protocol DynamicProperty {
    mutating func update()
}
extension DynamicProperty {
    public mutating func update() {}
}

protocol MountedProperty: DynamicProperty {
    @MainActor mutating func install(in context: Context)
}

@propertyWrapper @dynamicMemberLookup public struct Binding<Value>: DynamicProperty {
    private let get: () -> Value
    private let set: (Value, Transaction) -> Void
    private var assignedTransaction: Transaction?
    public var transaction: Transaction {
        get { assignedTransaction ?? Transaction() }
        set { assignedTransaction = newValue }
    }
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = { value, _ in set(value) }
    }
    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
        self.get = get
        self.set = set
    }
    public static func constant(_ value: Value) -> Self { Self(get: { value }, set: { _ in }) }
    public var wrappedValue: Value {
        get { get() }
        nonmutating set {
            if let assignedTransaction {
                withTransaction(assignedTransaction) { set(newValue, assignedTransaction) }
            } else {
                set(newValue, Transaction())
            }
        }
    }
    public var projectedValue: Self { self }
    public subscript<T>(dynamicMember path: WritableKeyPath<Value, T>) -> Binding<T> {
        var derived = Binding<T>(get: { get()[keyPath: path] }, set: { value, transaction in
            var root = get()
            root[keyPath: path] = value
            set(root, transaction)
        })
        derived.assignedTransaction = assignedTransaction
        return derived
    }
}
@propertyWrapper public struct State<Value>: MountedProperty {
    private final class Cell {
        private let lock = NSLock()
        private var stored: Value
        private weak var host: Host?
        init(_ value: Value) { stored = value }
        var value: Value {
            get { lock.withLock { stored } }
            set {
                let target = lock.withLock {
                    stored = newValue
                    return host
                }
                guard let target else { return }
                let transaction = Transaction.current ?? Transaction()
                if Thread.isMainThread {
                    MainActor.assumeIsolated { target.update(transaction: transaction) }
                } else {
                    Task { @MainActor [weak target] in target?.update(transaction: transaction) }
                }
            }
        }
        func attach(to host: Host) { lock.withLock { self.host = host } }
    }
    private var cell: Cell
    var identity: ObjectIdentifier { ObjectIdentifier(cell) }
    public init(wrappedValue: Value) { cell = Cell(wrappedValue) }
    public init(initialValue: Value) { self.init(wrappedValue: initialValue) }
    public var wrappedValue: Value {
        get { cell.value }
        nonmutating set { cell.value = newValue }
    }
    public var projectedValue: Binding<Value> { Binding(get: { wrappedValue }, set: { wrappedValue = $0 }) }
    mutating func install(in context: Context) {
        let host = context.host
        host.liveStorage.insert(context.path)
        if let existing = host.storage[context.path] as? Cell { cell = existing }
        else {
            cell = Cell(cell.value)
            host.storage[context.path] = cell
            cell.attach(to: host)
        }
    }
}

extension State where Value: ExpressibleByNilLiteral {
    public init() { self.init(wrappedValue: nil) }
}
