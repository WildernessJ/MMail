import Testing
import Foundation
@testable import MMail

/// Unit tests for the two pure Home-shell seams: `HomeWidgetVisibility` (additive,
/// absent-key-defaults-ON load/persist) and `InboxGlance.project` (read-only unread
/// projection over `[Email]`). Both are pure, so no `AppModel` instantiation is needed.
