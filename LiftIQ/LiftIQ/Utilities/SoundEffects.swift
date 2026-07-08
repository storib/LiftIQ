import AudioToolbox

/// In-app sound cues. System sound IDs respect the ring/silent switch, so
/// these stay quiet when the phone is muted.
enum SoundEffects {
    /// Tri-tone chime for the rest countdown reaching zero. Only needed when
    /// the app is foregrounded — in the background the rest-end local
    /// notification carries the sound instead.
    static func restComplete() {
        AudioServicesPlaySystemSound(1007)
    }
}
