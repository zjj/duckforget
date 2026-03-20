import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct LocationMarkerBadge: View {
    let title: String
    var noteCount: Int = 1
    var isSelected: Bool = false
    var accentColor: Color = .accentColor

    private var eyebrowText: String {
        noteCount > 1 ? "此处有 \(noteCount) 条笔记" : "位置笔记"
    }

    private var hintText: String {
        noteCount > 1 ? "再次轻点展开列表" : "再次轻点进入笔记"
    }

    private var compactTitle: String {
        if noteCount > 1 {
            return "\(noteCount) 条"
        }
        return title.count > 10 ? String(title.prefix(10)) + "…" : title
    }

    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(accentColor.opacity(0.16))
                    .frame(width: 164, height: 88)
                    .blur(radius: 14)
                    .offset(y: -12)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                if isSelected {
                    selectedCard
                } else {
                    compactBadge
                }

                Capsule()
                    .fill(accentColor)
                    .frame(width: 2, height: isSelected ? 8 : 6)

                ZStack {
                    if isSelected {
                        Circle()
                            .fill(accentColor.opacity(0.22))
                            .frame(width: 22, height: 22)
                    }

                    Circle()
                        .fill(accentColor)
                        .frame(width: isSelected ? 10 : 8, height: isSelected ? 10 : 8)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.95), lineWidth: 2)
                        }
                        .shadow(color: accentColor.opacity(isSelected ? 0.34 : 0.22), radius: isSelected ? 8 : 4, y: 2)
                }
            }
        }
    }

    private var compactBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: noteCount > 1 ? "square.stack.3d.up.fill" : "mappin.and.ellipse")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(accentColor)

            Text(compactTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(accentColor.opacity(0.16), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    private var selectedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: noteCount > 1 ? "square.stack.3d.up.fill" : "mappin.and.ellipse")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)

                Text(eyebrowText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)

            Text(hintText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 146, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accentColor.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
    }
}

enum LocationSnapshotRenderer {
    static func render(
        snapshot: MKMapSnapshotter.Snapshot,
        coordinate: CLLocationCoordinate2D,
        title: String,
        accentColor: UIColor
    ) -> UIImage {
        let point = snapshot.point(for: coordinate)
        let badgeTitle = truncated(title)
        let iconSize: CGFloat = 12
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 9
        let spacing: CGFloat = 6
        let dotSize: CGFloat = 10
        let connectorHeight: CGFloat = 8
        let maxWidth: CGFloat = 160

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        let titleWidth = min((badgeTitle as NSString).size(withAttributes: attrs).width, maxWidth - 44)
        let badgeWidth = max(74, min(maxWidth, horizontalPadding * 2 + iconSize + spacing + titleWidth))
        let badgeHeight: CGFloat = 34
        let badgeRect = CGRect(
            x: point.x - badgeWidth / 2,
            y: point.y - connectorHeight - dotSize - badgeHeight - 4,
            width: badgeWidth,
            height: badgeHeight
        )

        return UIGraphicsImageRenderer(size: snapshot.image.size).image { context in
            snapshot.image.draw(at: .zero)

            let cg = context.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: UIColor.black.withAlphaComponent(0.14).cgColor)
            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeHeight / 2)
            UIColor.systemBackground.withAlphaComponent(0.94).setFill()
            badgePath.fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)

            accentColor.withAlphaComponent(0.16).setStroke()
            badgePath.lineWidth = 1
            badgePath.stroke()

            let iconRect = CGRect(
                x: badgeRect.minX + horizontalPadding,
                y: badgeRect.midY - iconSize / 2,
                width: iconSize,
                height: iconSize
            )
            if let icon = UIImage(systemName: "mappin.and.ellipse")?.withTintColor(accentColor, renderingMode: .alwaysOriginal) {
                icon.draw(in: iconRect)
            }

            let textRect = CGRect(
                x: iconRect.maxX + spacing,
                y: badgeRect.minY + (badgeHeight - 16) / 2,
                width: badgeRect.width - (iconRect.maxX - badgeRect.minX) - spacing - horizontalPadding,
                height: 16
            )
            (badgeTitle as NSString).draw(in: textRect, withAttributes: attrs)

            let connectorRect = CGRect(
                x: point.x - 1,
                y: badgeRect.maxY,
                width: 2,
                height: connectorHeight
            )
            UIBezierPath(roundedRect: connectorRect, cornerRadius: 1).fill(with: .normal, alpha: 1)
            accentColor.setFill()
            UIBezierPath(roundedRect: connectorRect, cornerRadius: 1).fill()

            let dotRect = CGRect(
                x: point.x - dotSize / 2,
                y: point.y - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            let dotPath = UIBezierPath(ovalIn: dotRect)
            accentColor.setFill()
            dotPath.fill()
            UIColor.white.setStroke()
            dotPath.lineWidth = 2
            dotPath.stroke()
        }
    }

    private static func truncated(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "位置" }
        return trimmed.count > 16 ? String(trimmed.prefix(16)) + "…" : trimmed
    }
}