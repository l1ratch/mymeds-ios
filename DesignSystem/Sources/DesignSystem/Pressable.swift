import SwiftUI

/// Фидбек нажатия без сдвига layout (pro-rules: stable interaction states):
/// только прозрачность, тайминг — токен Motion.press.
public struct PressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
