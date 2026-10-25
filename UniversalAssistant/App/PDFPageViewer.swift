import SwiftUI
import PDFKit

/// PDF viewer that can jump to a page, used to navigate OCR search results.
struct PDFPageViewer: View {
    let url: URL
    let pageIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url, pageIndex: pageIndex)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Сторінка \(pageIndex + 1)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                    }
                }
        }
        .interactiveDismissDisabled(false)
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL
    let pageIndex: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        if let page = view.document?.page(at: pageIndex) {
            view.go(to: page)
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard let page = view.document?.page(at: pageIndex) else { return }
        view.go(to: page)
    }
}
