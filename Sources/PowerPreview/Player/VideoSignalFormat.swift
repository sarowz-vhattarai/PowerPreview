import SwiftUI

enum VideoSignalFormat: Equatable, Sendable {
    case dolbyVision
    case hdr10
    case hlg
    case hdr
    case sdr

    var badgeTitle: String? {
        switch self {
        case .dolbyVision: return "Dolby Vision"
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        case .hdr: return "HDR"
        case .sdr: return nil
        }
    }

    var tint: Color {
        switch self {
        case .dolbyVision:
            return Color(red: 0.12, green: 0.18, blue: 0.32)
        case .hdr10, .hdr:
            return Color(red: 0.82, green: 0.42, blue: 0.08)
        case .hlg:
            return Color(red: 0.10, green: 0.45, blue: 0.48)
        case .sdr:
            return .gray
        }
    }

    var helpText: String {
        switch self {
        case .dolbyVision: return "Dolby Vision content detected"
        case .hdr10: return "HDR10 (PQ) content detected"
        case .hlg: return "HLG HDR content detected"
        case .hdr: return "HDR content detected"
        case .sdr: return "Standard dynamic range"
        }
    }

    static func detect(
        gamma: String?,
        primaries: String?,
        sigPeak: Double,
        isDolbyVision: Bool
    ) -> VideoSignalFormat {
        if isDolbyVision {
            return .dolbyVision
        }

        let gammaValue = (gamma ?? "").lowercased()
        if gammaValue.contains("pq") || gammaValue.contains("smpte2084") {
            return .hdr10
        }
        if gammaValue.contains("hlg") || gammaValue.contains("arib-std-b67") {
            return .hlg
        }

        // Peak > 1.0 means brighter than SDR reference white.
        if sigPeak > 1.0 {
            return .hdr
        }

        let primariesValue = (primaries ?? "").lowercased()
        if primariesValue.contains("bt.2020") || primariesValue.contains("bt2020") {
            // BT.2020 without PQ/HLG metadata — treat as HDR-capable wide gamut.
            return .hdr
        }

        return .sdr
    }
}

struct MediaFormatBadge: View {
    let title: String
    let tint: Color
    var compact: Bool = false

    var body: some View {
        Text(title)
            .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
            .tracking(0.3)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 2 : 3)
            .foregroundStyle(.white)
            .background(tint.opacity(0.92), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .accessibilityLabel(title)
    }
}
