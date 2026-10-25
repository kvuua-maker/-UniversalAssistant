import SwiftUI
import UIKit

/// Finger-drawing surface for a signature; returns a rendered image.
struct SignaturePadView: View {
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void
    @State private var pad = SignaturePadController()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                SignatureCanvas(pad: pad)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                Text("Намалюйте підпис пальцем")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .navigationTitle("Підпис")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Скасувати") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        if let image = pad.render() { onSave(image) }
                    }
                }
            }
            .interactiveDismissDisabled(true)
        }
    }
}

final class SignaturePadController {
    var strokes: [[CGPoint]] = []
    var current: [CGPoint] = []

    func render(size: CGSize = CGSize(width: 600, height: 240)) -> UIImage? {
        guard !strokes.isEmpty else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(3)
            context.cgContext.setLineCap(.round)
            for stroke in strokes where stroke.count > 1 {
                context.cgContext.move(to: stroke[0])
                for point in stroke.dropFirst() { context.cgContext.addLine(to: point) }
                context.cgContext.strokePath()
            }
        }
    }
}

struct SignatureCanvas: UIViewRepresentable {
    let pad: SignaturePadController

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.pad = pad
        view.backgroundColor = .white
        view.isMultipleTouchEnabled = false
        return view
    }

    func updateUIView(_ view: CanvasView, context: Context) {}

    final class CanvasView: UIView {
        var pad: SignaturePadController?
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let point = touches.first?.location(in: self) else { return }
            pad?.current = [point]
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let point = touches.first?.location(in: self) else { return }
            pad?.current.append(point)
            setNeedsDisplay()
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let pad, !pad.current.isEmpty else { return }
            pad.strokes.append(pad.current)
            pad.current = []
            setNeedsDisplay()
        }
        override func draw(_ rect: CGRect) {
            guard let pad, let context = UIGraphicsGetCurrentContext() else { return }
            UIColor.black.setStroke()
            context.setLineWidth(3)
            context.setLineCap(.round)
            for stroke in pad.strokes + [pad.current] where stroke.count > 1 {
                context.move(to: stroke[0])
                for point in stroke.dropFirst() { context.addLine(to: point) }
                context.strokePath()
            }
        }
    }
}
