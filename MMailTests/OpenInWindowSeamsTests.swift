import Testing
@testable import MMail

/// Unit tests for the two pure open-in-window seams on `AppModel` (SC-009):
/// the lookup-by-id seam `email(withId:in:)` (INV-1/INV-3) and the close-decision
/// predicate `shouldCloseDetached(id:openerFolder:in:)` (INV-9). Both are static and
/// pure, so no `AppModel` instantiation is required.
@Suite struct OpenInWindowSeams {

    /// Minimal `Email` constructor varying only id and folder.
    private func email(_ id: String, folder: String) -> Email {
        Email(id: id, account: "A", from: "f", subject: "s",
              preview: "", body: "", time: "", day: "today", folder: folder)
    }

    // MARK: - Lookup-by-id seam (INV-1/INV-3)

    @Test func presentIdReturnsTheEmail() {
        let emails = [email("a1", folder: "inbox"), email("a2", folder: "inbox")]
        let found = AppModel.email(withId: "a2", in: emails)
        #expect(found?.id == "a2")
    }

    @Test func absentIdReturnsNil() {
        let emails = [email("a1", folder: "inbox")]
        #expect(AppModel.email(withId: "missing", in: emails) == nil)
    }

    // MARK: - Close-decision predicate (INV-9)

    @Test func folderChangeAwayFromOpenerClosesTrue() {
        // Row present but its folder mutated away from the opener folder → close (local triage).
        let emails = [email("a1", folder: "archive")]
        #expect(AppModel.shouldCloseDetached(id: "a1", openerFolder: "inbox", in: emails) == true)
    }

    @Test func absentRowClosesTrue() {
        // Row expunged (absent from the model entirely) → close.
        let emails = [email("a2", folder: "inbox")]
        #expect(AppModel.shouldCloseDetached(id: "a1", openerFolder: "inbox", in: emails) == true)
    }

    @Test func presentAndSameFolderStaysOpenFalse() {
        // Row present and still in its opener folder → keep open.
        let emails = [email("a1", folder: "inbox")]
        #expect(AppModel.shouldCloseDetached(id: "a1", openerFolder: "inbox", in: emails) == false)
    }
}
