import SwiftUI

/// App-wide visual tokens. Pure namespaces of constants — no runtime state.
/// Everything that draws chrome (cards, chips, sections, dividers) should pull
/// its spacing/radius/color from here so the look stays coherent as the visual
/// layer grows. Colors lean on dynamic system colors (`.secondary`,
/// `.accentColor`) so they adapt to light/dark automatically.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Layout {
        /// Max width for the brief reading column — caps line length to a
        /// comfortable measure on wide windows; narrower windows fill available
        /// space (the value is a max, not a fixed width).
        static let readingMeasure: CGFloat = 720
    }

    enum Radius {
        /// Small chips / inner callouts.
        static let sm: CGFloat = 6
        /// Standard card corner — matches the legacy card look.
        static let card: CGFloat = 8
        /// Larger hero surfaces.
        static let lg: CGFloat = 12
    }

    enum Colors {
        /// Subtle fill for a card sitting on the window background.
        static let cardFill = Color.secondary.opacity(0.06)
        /// A slightly stronger fill for elevated / hovered surfaces.
        static let cardFillElevated = Color.secondary.opacity(0.11)
        /// Hairline border for cards and dividers.
        static let hairline = Color.secondary.opacity(0.16)
        /// Faint accent wash for highlighted callouts (TL;DR hero, etc.).
        static let accentSoft = Color.accentColor.opacity(0.12)
    }

    /// Standard easing for the app's micro-interactions (used from V10 on).
    enum Motion {
        static let quick: Animation = .easeOut(duration: 0.18)
        static let reveal: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    }
}
