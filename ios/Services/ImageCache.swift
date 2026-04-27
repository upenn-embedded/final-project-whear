import SwiftUI
import Combine

// MARK: - Image Cache

/// In-memory NSCache for decoded UIImages. Lives for the app session.
/// Once fetched, images are served instantly on every subsequent appearance.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024   // ~100 MB
    }

    func get(_ url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func set(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }
}

// MARK: - Cached Image Loader

/// ObservableObject that fetches and caches a single image URL.
/// @MainActor is intentionally NOT on the class — it conflicts with
/// ObservableObject's objectWillChange synthesis. Main-queue hops are
/// done manually before mutating @Published properties.
final class CachedImageLoader: ObservableObject {
    @Published var image: UIImage?   = nil
    @Published var isLoading: Bool   = false
    @Published var failed: Bool      = false

    private var loadedUrl: URL?
    private var task: URLSessionDataTask?

    func load(url: URL) {
        guard loadedUrl != url else { return }
        loadedUrl = url
        task?.cancel()

        // Cache hit — instant, no network
        if let cached = ImageCache.shared.get(url) {
            image = cached
            return
        }

        DispatchQueue.main.async { self.isLoading = true; self.failed = false }

        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let data, let uiImage = UIImage(data: data) {
                    ImageCache.shared.set(uiImage, for: url)
                    self.image = uiImage
                } else {
                    self.failed = true
                }
            }
        }
        task?.resume()
    }
}

// MARK: - CachedAsyncImage View

/// Drop-in for AsyncImage that keeps decoded images in ImageCache.
struct CachedAsyncImage<Content: View, Placeholder: View, Failure: View>: View {
    private let url: URL
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    private let failure: () -> Failure

    @StateObject private var loader = CachedImageLoader()

    init(
        url: URL,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            if let uiImage = loader.image {
                content(Image(uiImage: uiImage))
            } else if loader.failed {
                failure()
            } else {
                placeholder()
            }
        }
        .onAppear { loader.load(url: url) }
    }
}
