// Cross-platform shims so the receiver core (iOS/PhoneReceiver.swift) compiles
// for BOTH iOS and macOS. Keep this the only place that branches on toolkit.
//
// The iOS app already has its own `deviceKind` global and PeerUpdateSignal in
// iOS/VersionGate.swift, so everything macOS-only here is guarded to avoid
// colliding when this file is compiled into the iOS target.

import Foundation

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum ReceiverPlatform {
    /// Goes into `hello.device`. PROTOCOL.md section 6.1 declares this field
    /// free-form, so "Mac" needs no spec change and no sender change.
    static var deviceKind: String {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        return "Mac"
        #endif
    }

    /// Default Bonjour service name. iOS returns a generic "iPhone" from
    /// UIDevice (the real name is entitlement-gated); macOS hands over the
    /// actual computer name with no gate.
    static var defaultDeviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
}

#if !canImport(UIKit)

/// Mirrors the enum in iOS/VersionGate.swift, which cannot be compiled here
/// because it is a SwiftUI view file that calls UIApplication.
enum PeerUpdateSignal: Equatable {
    case updateIPhone(message: String, storeURL: URL)
    case updateMac(message: String)
}

/// The panel size the receiver announces in `hello`.
///
/// CRITICAL: the sender IGNORES `hello.scale`. `MacSender.swift:374` computes
/// `pointsWide = pixelsWide / 2` unconditionally and the virtual display is
/// always @2x. So the desktop you get is always **half** the announced pixels,
/// and the announced pixel size is the only lever on desktop size.
///
/// The sender then encodes at `points * 2 * quality.scale`, and H.264 hardware
/// encode is widely capped at 4096 wide — which is why 5120 is not the default.
enum PanelPreset: String, CaseIterable {
    case balanced      // 1920x1080 desktop, encodes 3840x2160 at any quality
    case moreSpace     // 2560x1440 desktop, needs sender on Balanced or Fast
    case largerText    // 1440x810 desktop

    var pixels: (w: Int, h: Int) {
        switch self {
        case .balanced:   return (3840, 2160)
        case .moreSpace:  return (5120, 2880)
        case .largerText: return (2880, 1620)
        }
    }

    var title: String {
        let d = pixels
        switch self {
        case .moreSpace:  return "Sharpest — \(d.w / 2)x\(d.h / 2) desktop (set Mac quality to Fast)"
        case .balanced:   return "Balanced — \(d.w / 2)x\(d.h / 2) desktop"
        case .largerText: return "Larger text — \(d.w / 2)x\(d.h / 2) desktop"
        }
    }

    /// Next smaller announcement, for automatic fallback when the receiving
    /// hardware cannot decode the stream the sender produces. Measured on an
    /// iMac 27" 2017 (Radeon Pro 575): 2880x1620 decodes, 3840x2160 does not.
    var smaller: PanelPreset? {
        switch self {
        case .moreSpace:  return .balanced
        case .balanced:   return .largerText
        case .largerText: return nil
        }
    }

    /// Defaults to `.moreSpace` — a 27" 5K panel wants a 2560x1440 desktop, and
    /// announcing 5120x2880 is the only way to get one (the sender halves the
    /// announced pixels to derive points). If the sender's encoder refuses
    /// 5120-wide, pick another entry from the Display menu to recover.
    static var current: PanelPreset {
        let raw = UserDefaults.standard.string(forKey: "panelPreset") ?? ""
        return PanelPreset(rawValue: raw) ?? .moreSpace
    }

    static func select(_ p: PanelPreset) {
        UserDefaults.standard.set(p.rawValue, forKey: "panelPreset")
    }
}

#endif
