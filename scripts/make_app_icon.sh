#!/usr/bin/env bash

# Generates Resources/AppIcon.icns for the ACP app. Renders each icon size with
# CoreGraphics (offscreen bitmap context — no window server required) and packs
# them into an .icns with iconutil. Run manually when the icon design changes;
# the resulting AppIcon.icns is committed and consumed by build_mac_app.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
work="$(mktemp -d)"
iconset="${work}/AppIcon.iconset"
mkdir -p "${iconset}"
swift_src="${work}/render.swift"

cat > "${swift_src}" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let red     = CGColor(red: 0.86, green: 0.16, blue: 0.24, alpha: 1)
let redLite = CGColor(red: 1.00, green: 0.38, blue: 0.40, alpha: 1)
let white   = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

func drawIcon(size: Int, to url: URL) {
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    // Rounded-rect background with a vertical gradient (macOS squircle radius).
    let radius = s * 0.2237
    let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                    cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bg); ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [redLite, red] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // White calendar page.
    let inset = s * 0.24
    let page = CGRect(x: inset, y: inset * 0.85, width: s - inset * 2, height: s - inset * 1.7)
    let pr = s * 0.055
    let pagePath = CGPath(roundedRect: page, cornerWidth: pr, cornerHeight: pr, transform: nil)
    ctx.addPath(pagePath); ctx.setFillColor(white); ctx.fillPath()

    // Red header band (clipped to the page's rounded top).
    let bandH = page.height * 0.24
    ctx.saveGState()
    ctx.addPath(pagePath); ctx.clip()
    ctx.setFillColor(red)
    ctx.fill(CGRect(x: page.minX, y: page.maxY - bandH, width: page.width, height: bandH))
    ctx.restoreGState()

    // Two dot rows suggesting calendar days.
    let dotR = s * 0.032
    let startX = page.minX + page.width * 0.22
    let stepX = page.width * 0.28
    let topY = page.maxY - bandH - s * 0.10
    let stepY = s * 0.12
    ctx.setFillColor(CGColor(red: 0.86, green: 0.16, blue: 0.24, alpha: 0.82))
    for row in 0..<2 {
        for col in 0..<3 {
            let cx = startX + CGFloat(col) * stepX
            let cy = topY - CGFloat(row) * stepY
            ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))
        }
    }

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let targets: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, size) in targets {
    drawIcon(size: size, to: outDir.appendingPathComponent(name))
}
SWIFT

swift "${swift_src}" "${iconset}"
mkdir -p "${project_root}/Resources"
iconutil -c icns "${iconset}" -o "${project_root}/Resources/AppIcon.icns"
rm -rf "${work}"
echo "✅ Wrote ${project_root}/Resources/AppIcon.icns"
