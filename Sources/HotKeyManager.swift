#if !TESTING
import Carbon
import AppKit

class HotKeyManager {
    private var playPauseHotKeyRef: EventHotKeyRef?
    private var nextTrackHotKeyRef: EventHotKeyRef?

    var onPlayPause: (() -> Void)?
    var onNextTrack: (() -> Void)?

    private static var shared: HotKeyManager?

    init() {
        HotKeyManager.shared = self
    }

    func register() {
        // Install Carbon event handler
        var eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            DispatchQueue.main.async {
                switch hotKeyID.id {
                case 1:
                    HotKeyManager.shared?.onPlayPause?()
                case 2:
                    HotKeyManager.shared?.onNextTrack?()
                default:
                    break
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventSpec,
            nil,
            nil
        )

        // Cmd+F8 for play/pause
        let playPauseID = EventHotKeyID(signature: OSType(0x53585448), id: 1) // "SXTH"
        RegisterEventHotKey(
            UInt32(kVK_F8),
            UInt32(cmdKey),
            playPauseID,
            GetApplicationEventTarget(),
            0,
            &playPauseHotKeyRef
        )

        // Cmd+F9 for next track
        let nextTrackID = EventHotKeyID(signature: OSType(0x53585448), id: 2)
        RegisterEventHotKey(
            UInt32(kVK_F9),
            UInt32(cmdKey),
            nextTrackID,
            GetApplicationEventTarget(),
            0,
            &nextTrackHotKeyRef
        )
    }

    func unregister() {
        if let ref = playPauseHotKeyRef {
            UnregisterEventHotKey(ref)
            playPauseHotKeyRef = nil
        }
        if let ref = nextTrackHotKeyRef {
            UnregisterEventHotKey(ref)
            nextTrackHotKeyRef = nil
        }
    }

    deinit {
        unregister()
    }
}
#endif
