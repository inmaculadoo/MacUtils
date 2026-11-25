/// When the Dock preview panel should stay on screen (SPEC §4.6).
public enum DockPreviewHover {
    /// True while the mouse is over the panel or the Dock's icon list, or in
    /// the small gap between them. Everything is in top-left coordinates.
    public static func keepsPreview(mouseX: Double, mouseY: Double, panel: LRect, dock: LRect?,
                                    margin: Double = 8) -> Bool {
        if panel.insetBy(-margin).contains(x: mouseX, y: mouseY) { return true }
        guard let dock else { return false }
        return dock.insetBy(-margin).contains(x: mouseX, y: mouseY)
    }
}
