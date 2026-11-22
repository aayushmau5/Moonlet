import AppKit
import Metal
import MetalKit

@MainActor
final class MetalRenderer: NSObject, WallpaperRenderer {
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm
    static let framesPerSecond = 30

    var onProblem: ((String?) -> Void)?
    private(set) var pipeline: MTLRenderPipelineState?
    private(set) var image: MTLTexture?

    private let sourceURL: URL
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue?
    private let watchesSource: Bool
    private let renderScale: Double
    private let imageURL: URL?
    private var loadedSource: String?
    private var loadedImageDate: Date?
    private var views: [CGDirectDisplayID: MTKView] = [:]
    private var clock = ShaderClock()
    private var isPlaying = false
    private var pausedDisplays: Set<CGDirectDisplayID> = []
    private var hasDrawnFrame = false
    private var watcher: FolderWatcher?

    var attachedDisplayIDs: [CGDirectDisplayID] {
        Array(views.keys)
    }

    var isClockRunning: Bool {
        clock.isRunning
    }

    init(
        sourceURL: URL,
        device: MTLDevice,
        renderScale: Double = 1,
        imageURL: URL? = nil,
        watchesSource: Bool = true
    ) {
        self.sourceURL = sourceURL
        self.device = device
        self.renderScale = renderScale
        self.imageURL = imageURL
        self.commandQueue = device.makeCommandQueue()
        self.watchesSource = watchesSource
        super.init()
    }

    func load() async throws {
        let source = try readSource()
        pipeline = try await makePipeline(source: source)
        loadedSource = source
        if let imageURL {
            loadedImageDate = modificationDate(of: imageURL)
            image = try await loadImage(from: imageURL)
        }
        if watchesSource {
            startWatching()
        }
    }

    func reloadIfChanged() async {
        await reloadImageIfChanged()
        guard let source = try? readSource(), source != loadedSource else { return }
        loadedSource = source
        do {
            let newPipeline = try await makePipeline(source: source)
            guard loadedSource == source, pipeline != nil else { return }
            pipeline = newPipeline
            onProblem?(nil)
        } catch {
            guard loadedSource == source else { return }
            onProblem?(error.localizedDescription)
        }
    }

    private func reloadImageIfChanged() async {
        guard let imageURL, image != nil else { return }
        let date = modificationDate(of: imageURL)
        guard date != loadedImageDate else { return }
        loadedImageDate = date
        do {
            let newImage = try await loadImage(from: imageURL)
            guard loadedImageDate == date, self.image != nil else { return }
            self.image = newImage
            onProblem?(nil)
        } catch {
            guard loadedImageDate == date else { return }
            onProblem?(error.localizedDescription)
        }
    }

    private func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func loadImage(from url: URL) async throws -> MTLTexture {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .origin: MTKTextureLoader.Origin.bottomLeft,
            .SRGB: false,
            .generateMipmaps: true,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
        ]
        do {
            return try await loader.newTexture(URL: url, options: options)
        } catch {
            throw ShaderError(message: "Could not load image \(url.lastPathComponent)")
        }
    }

    func attach(to display: DisplayInfo) -> NSView {
        let view = ScaledMetalView(frame: NSRect(origin: .zero, size: display.frame.size), device: device)
        view.renderScale = renderScale
        view.colorPixelFormat = Self.pixelFormat
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = Self.framesPerSecond
        view.enableSetNeedsDisplay = false
        view.isPaused = !isPlaying || pausedDisplays.contains(display.id)
        view.delegate = self
        views[display.id] = view
        return view
    }

    func detach(from displayID: CGDirectDisplayID) {
        guard let view = views.removeValue(forKey: displayID) else { return }
        view.isPaused = true
        view.delegate = nil
        view.releaseDrawables()
    }

    func waitUntilReady() async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !views.isEmpty, isPlaying, !hasDrawnFrame, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    func play() {
        isPlaying = true
        applyRunState()
    }

    func pause() {
        isPlaying = false
        applyRunState()
    }

    func setPausedDisplays(_ displays: Set<CGDirectDisplayID>) {
        pausedDisplays = displays
        applyRunState()
    }

    private func applyRunState() {
        for (id, view) in views {
            view.isPaused = !isPlaying || pausedDisplays.contains(id)
        }
        let anyScreenRunning = views.isEmpty || views.keys.contains { !pausedDisplays.contains($0) }
        if isPlaying && anyScreenRunning {
            clock.resume(at: .now)
        } else {
            clock.pause(at: .now)
        }
    }

    func tearDown() {
        watcher?.stop()
        watcher = nil
        pause()
        for id in views.keys {
            detach(from: id)
        }
        pipeline = nil
        image = nil
    }

    func snapshot(width: Int, height: Int, time: Float) throws -> CGImage {
        guard let pipeline, let commandQueue else {
            throw ShaderError(message: "Shader is not loaded")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor),
              let buffer = commandQueue.makeCommandBuffer() else {
            throw ShaderError(message: "Could not allocate a snapshot texture")
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        var uniforms = ShaderUniforms(time: time, resolution: SIMD2(Float(width), Float(height)))
        encode(into: buffer, pass: pass, pipeline: pipeline, uniforms: &uniforms)
        buffer.commit()
        buffer.waitUntilCompleted()

        return try makeImage(from: texture)
    }

    private func readSource() throws -> String {
        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            throw ShaderError(message: "Could not read \(sourceURL.lastPathComponent)")
        }
    }

    private func makePipeline(source: String) async throws -> MTLRenderPipelineState {
        let combined = ShaderSource.combined(source, fileName: sourceURL.lastPathComponent)
        let library: MTLLibrary
        do {
            library = try await device.makeLibrary(source: combined, options: nil)
        } catch {
            throw ShaderError(message: ShaderSource.describeCompileLog(error.localizedDescription))
        }

        guard let fragment = library.makeFunction(name: ShaderSource.fragmentFunctionName) else {
            throw ShaderError(message: #"Missing a fragment function named "wallpaper""#)
        }
        guard let vertex = library.makeFunction(name: ShaderSource.vertexFunctionName) else {
            throw ShaderError(message: "Missing the built-in vertex function")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
        do {
            return try await device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw ShaderError(message: ShaderSource.describeCompileLog(error.localizedDescription))
        }
    }

    private func encode(
        into buffer: MTLCommandBuffer,
        pass: MTLRenderPassDescriptor,
        pipeline: MTLRenderPipelineState,
        uniforms: inout ShaderUniforms
    ) {
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        if let image {
            encoder.setFragmentTexture(image, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func makeImage(from texture: MTLTexture) throws -> CGImage {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: texture.width,
                  height: texture.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw ShaderError(message: "Could not build the snapshot image")
        }
        return image
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let watcher = FolderWatcher(url: sourceURL.deletingLastPathComponent(), latency: 0.3) { [weak self] in
            Task { @MainActor in
                await self?.reloadIfChanged()
            }
        }
        watcher.start()
        self.watcher = watcher
    }
}

extension MetalRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline,
              let commandQueue,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = commandQueue.makeCommandBuffer() else { return }

        let size = view.drawableSize
        var uniforms = ShaderUniforms(
            time: Float(clock.elapsed(at: .now)),
            resolution: SIMD2(Float(size.width), Float(size.height))
        )
        encode(into: buffer, pass: pass, pipeline: pipeline, uniforms: &uniforms)
        buffer.present(drawable)
        buffer.commit()
        hasDrawnFrame = true
    }
}

final class ScaledMetalView: MTKView {
    var renderScale: Double = 1 {
        didSet {
            autoResizeDrawable = renderScale >= 1
            updateDrawableSize()
        }
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        guard renderScale < 1 else { return }
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let scale = backing * renderScale
        drawableSize = CGSize(
            width: (bounds.width * scale).rounded(),
            height: (bounds.height * scale).rounded()
        )
    }
}
