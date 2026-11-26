@attached(accessor)
@attached(peer, names: prefixed(__Key_))
public macro Entry() = #externalMacro(module: "QtSwiftUIMacros", type: "EntryMacro")

@attached(accessor)
public macro __EntryDefaultValue() = #externalMacro(module: "QtSwiftUIMacros", type: "EntryDefaultValueMacro")
