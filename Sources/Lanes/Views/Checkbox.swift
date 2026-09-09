import SwiftUI

/// A checkbox drawn by SwiftUI. The AppKit-backed `Toggle(.checkbox)` makes every List row's
/// automatic height go through the Auto Layout engine, which costs several milliseconds per row.
struct Checkbox: View {
  @Binding var isOn: Bool
  let label: String
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      Image(systemName: isOn ? "checkmark.square.fill" : "square")
        .font(.system(size: 14))
        .foregroundStyle(isOn && isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(width: 16, height: 16)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityAddTraits(.isToggle)
    .accessibilityValue(isOn ? "1" : "0")
  }
}
