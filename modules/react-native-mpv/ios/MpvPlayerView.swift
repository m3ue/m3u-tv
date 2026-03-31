import UIKit
import MPVKit
import Metal

class MpvPlayerView: UIView {
    private var mpv: OpaquePointer?
    private var metalView: MPVMetalView?
    private var progressTimer: Timer?
    private var isInitialized = false
    private var pendingUri: String?
    private var pendingPaused = false
    private var pendingSeek: Double = -1

    // RN event callbacks
    var onMpvLoad: (([String: Any]) -> Void)?
    var onMpvProgress: (([String: Any]) -> Void)?
    var onMpvBuffer: (([String: Any]) -> Void)?
    var onMpvError: (([String: Any]) -> Void)?
    var onMpvEnd: (([String: Any]) -> Void)?
    var onMpvTracksChanged: (([String: Any]) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        setupMpv()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        setupMpv()
    }

    deinit {
        destroy()
    }

    private func setupMpv() {
        mpv = mpv_create()
        guard let ctx = mpv else { return }

        // Core configuration — no vo/gpu-api needed; the SW render context handles output
        setMpvOption(ctx, "hwdec", "videotoolbox-copy")  // HW decode → CPU copy for SW renderer
        setMpvOption(ctx, "ao", "audiounit")
        setMpvOption(ctx, "demuxer-max-bytes", "150MiB")
        setMpvOption(ctx, "demuxer-max-back-bytes", "75MiB")
        setMpvOption(ctx, "cache", "yes")
        setMpvOption(ctx, "cache-secs", "120")
        setMpvOption(ctx, "network-timeout", "30")
        setMpvOption(ctx, "keep-open", "yes")
        setMpvOption(ctx, "profile", "fast")
        setMpvOption(ctx, "terminal", "no")
        setMpvOption(ctx, "msg-level", "all=warn")
        setMpvOption(ctx, "tls-verify", "no")
        setMpvOption(ctx, "ytdl", "no")

        let initResult = mpv_initialize(ctx)
        guard initResult == 0 else {
            onMpvError?(["error": "mpv_initialize failed: \(initResult)"])
            return
        }

        // Metal rendering view — must be created and attached before playback starts
        let mv = MPVMetalView(frame: bounds)
        mv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mv.initMpvRender(ctx)
        addSubview(mv)
        metalView = mv

        // Observe properties
        mpv_observe_property(ctx, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(ctx, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(ctx, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(ctx, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(ctx, 0, "track-list/count", MPV_FORMAT_INT64)
        mpv_observe_property(ctx, 0, "eof-reached", MPV_FORMAT_FLAG)

        // Event wakeup (separate from the render update callback set inside MPVMetalView)
        mpv_set_wakeup_callback(ctx, { pointer in
            guard let pointer else { return }
            let view = Unmanaged<MpvPlayerView>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { view.handleEvents() }
        }, Unmanaged.passUnretained(self).toOpaque())

        isInitialized = true

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.emitProgress()
        }

        if let uri = pendingUri {
            loadFile(uri)
            pendingUri = nil
        }
    }

    private func setMpvOption(_ ctx: OpaquePointer, _ name: String, _ value: String) {
        mpv_set_option_string(ctx, name, value)
    }

    // MARK: - Public API

    func setUri(_ uri: String?) {
        guard let uri = uri, !uri.isEmpty else { return }
        if isInitialized {
            loadFile(uri)
        } else {
            pendingUri = uri
        }
    }

    func setUserAgent(_ userAgent: String?) {
        guard let ctx = mpv, let ua = userAgent else { return }
        mpv_set_option_string(ctx, "user-agent", ua)
    }

    func setPaused(_ paused: Bool) {
        pendingPaused = paused
        guard let ctx = mpv, isInitialized else { return }
        var flag: Int32 = paused ? 1 : 0
        mpv_set_property(ctx, "pause", MPV_FORMAT_FLAG, &flag)
    }

    func setStartPosition(_ seconds: Double) {
        if seconds > 0 {
            pendingSeek = seconds
        }
    }

    func seekTo(_ seconds: Double) {
        guard let ctx = mpv, isInitialized, seconds >= 0 else { return }
        mpvCommand(ctx, "seek", [seconds.description, "absolute"])
    }

    func seekRelative(_ seconds: Double) {
        guard let ctx = mpv, isInitialized else { return }
        mpvCommand(ctx, "seek", [seconds.description, "relative"])
    }

    func setAudioTrack(_ trackId: Int) {
        guard let ctx = mpv, isInitialized else { return }
        if trackId < 0 {
            mpv_set_option_string(ctx, "aid", "no")
        } else {
            var id = Int64(trackId)
            mpv_set_property(ctx, "aid", MPV_FORMAT_INT64, &id)
        }
    }

    func setSubtitleTrack(_ trackId: Int) {
        guard let ctx = mpv, isInitialized else { return }
        if trackId < 0 {
            mpv_set_option_string(ctx, "sid", "no")
        } else {
            var id = Int64(trackId)
            mpv_set_property(ctx, "sid", MPV_FORMAT_INT64, &id)
        }
    }

    func stop() {
        guard let ctx = mpv, isInitialized else { return }
        mpvCommand(ctx, "stop", [])
    }

    func destroy() {
        progressTimer?.invalidate()
        progressTimer = nil

        // Render context must be freed before mpv_terminate_destroy
        metalView?.cleanup()
        metalView?.removeFromSuperview()
        metalView = nil

        if let ctx = mpv {
            mpv_set_wakeup_callback(ctx, nil, nil)
            mpvCommand(ctx, "quit", [])
            mpv_terminate_destroy(ctx)
            mpv = nil
        }
        isInitialized = false
    }

    // MARK: - Private helpers

    private func loadFile(_ url: String) {
        guard let ctx = mpv else { return }
        mpvCommand(ctx, "loadfile", [url])
    }

    private func mpvCommand(_ ctx: OpaquePointer, _ name: String, _ args: [String]) {
        var owned: [UnsafeMutablePointer<CChar>?] = [strdup(name)]
        for arg in args { owned.append(strdup(arg)) }
        owned.append(nil)
        var cArgs: [UnsafePointer<CChar>?] = owned.map { $0.map { UnsafePointer($0) } }
        mpv_command(ctx, &cArgs)
        owned.forEach { free($0) }
    }

    private func handleEvents() {
        guard let ctx = mpv else { return }
        while true {
            let event = mpv_wait_event(ctx, 0)
            guard let ev = event?.pointee else { break }
            if ev.event_id == MPV_EVENT_NONE { break }
            switch ev.event_id {
            case MPV_EVENT_FILE_LOADED:   handleFileLoaded()
            case MPV_EVENT_END_FILE:      handleEndFile(ev)
            case MPV_EVENT_PROPERTY_CHANGE: handlePropertyChange(ev)
            case MPV_EVENT_LOG_MESSAGE:
                if let msg = ev.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee,
                   msg.log_level.rawValue <= MPV_LOG_LEVEL_ERROR.rawValue {
                    onMpvError?(["error": String(cString: msg.text)])
                }
            default: break
            }
        }
    }

    private func handleFileLoaded() {
        guard let ctx = mpv else { return }
        var duration: Double = 0
        mpv_get_property(ctx, "duration", MPV_FORMAT_DOUBLE, &duration)
        let trackInfo = getTrackInfo()
        onMpvLoad?(["duration": duration, "audioTracks": trackInfo.audio, "textTracks": trackInfo.text])
        if pendingPaused {
            var flag: Int32 = 1
            mpv_set_property(ctx, "pause", MPV_FORMAT_FLAG, &flag)
        }
        if pendingSeek >= 0 {
            seekTo(pendingSeek)
            pendingSeek = -1
        }
    }

    private func handleEndFile(_ ev: mpv_event) {
        if let endFile = ev.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee {
            if endFile.error < 0 {
                onMpvError?(["error": "Playback error (code: \(endFile.error))"])
            } else {
                onMpvEnd?([:])
            }
        } else {
            onMpvEnd?([:])
        }
    }

    private func handlePropertyChange(_ ev: mpv_event) {
        guard let prop = ev.data?.assumingMemoryBound(to: mpv_event_property.self).pointee else { return }
        let name = String(cString: prop.name)
        switch name {
        case "paused-for-cache":
            if prop.format == MPV_FORMAT_FLAG, let data = prop.data {
                onMpvBuffer?(["isBuffering": data.assumingMemoryBound(to: Int32.self).pointee != 0])
            }
        case "eof-reached":
            if prop.format == MPV_FORMAT_FLAG, let data = prop.data,
               data.assumingMemoryBound(to: Int32.self).pointee != 0 {
                onMpvEnd?([:])
            }
        case "track-list/count":
            let info = getTrackInfo()
            onMpvTracksChanged?(["audioTracks": info.audio, "textTracks": info.text])
        default: break
        }
    }

    private func emitProgress() {
        guard let ctx = mpv, isInitialized else { return }
        var timePos: Double = 0
        var dur: Double = 0
        mpv_get_property(ctx, "time-pos", MPV_FORMAT_DOUBLE, &timePos)
        mpv_get_property(ctx, "duration", MPV_FORMAT_DOUBLE, &dur)
        if timePos > 0 || dur > 0 {
            onMpvProgress?(["currentTime": timePos, "duration": dur])
        }
    }

    private func getTrackInfo() -> (audio: [[String: Any]], text: [[String: Any]]) {
        guard let ctx = mpv else { return ([], []) }
        var count: Int64 = 0
        mpv_get_property(ctx, "track-list/count", MPV_FORMAT_INT64, &count)
        var audio: [[String: Any]] = []
        var text: [[String: Any]] = []
        for i in 0..<Int(count) {
            guard let typeStr = getPropertyString(ctx, "track-list/\(i)/type") else { continue }
            var id: Int64 = 0
            mpv_get_property(ctx, "track-list/\(i)/id", MPV_FORMAT_INT64, &id)
            let title = getPropertyString(ctx, "track-list/\(i)/title") ?? ""
            let lang  = getPropertyString(ctx, "track-list/\(i)/lang") ?? ""
            let name  = title.isEmpty ? (lang.isEmpty ? "Track \(id)" : lang) : title
            let track: [String: Any] = ["id": Int(id), "name": name, "language": lang]
            switch typeStr {
            case "audio": audio.append(track)
            case "sub":   text.append(track)
            default: break
            }
        }
        return (audio, text)
    }

    private func getPropertyString(_ ctx: OpaquePointer, _ name: String) -> String? {
        guard let cStr = mpv_get_property_string(ctx, name) else { return nil }
        defer { mpv_free(cStr) }
        return String(cString: cStr)
    }
}

// MARK: - MPVMetalView
//
// Renders libmpv frames via the SW render API (MPV_RENDER_API_TYPE_SW).
// mpv writes each decoded frame as BGRA pixels into a CPU buffer; we then
// upload those pixels to a MTLTexture and blit it to a CAMetalLayer drawable.
// This avoids the deprecated OpenGL ES path while being fully compatible with
// VideoToolbox hardware decode (via hwdec=videotoolbox-copy).

private class MPVMetalView: UIView {

    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?

    // Cached texture — reallocated only when frame dimensions change
    private var renderTexture: MTLTexture?
    private var renderTextureSize = CGSize.zero

    private(set) var renderCtx: OpaquePointer?
    private var displayLink: CADisplayLink?

    // Pixel buffer written by mpv on the display-link thread
    private var pixelData: [UInt8] = []

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupMetal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }

    /// Call before mpv_terminate_destroy to safely release the render context.
    func cleanup() {
        displayLink?.invalidate()
        displayLink = nil
        if let ctx = renderCtx {
            mpv_render_context_set_update_callback(ctx, nil, nil)
            mpv_render_context_free(ctx)
            renderCtx = nil
        }
    }

    deinit {
        cleanup()
    }

    // MARK: - Metal setup

    private func setupMetal() {
        guard let dev = MTLCreateSystemDefaultDevice() else { return }
        device = dev
        commandQueue = dev.makeCommandQueue()

        metalLayer.device = dev
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.contentsScale = UIScreen.main.scale

        buildPipeline(device: dev)

        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func buildPipeline(device: MTLDevice) {
        // Inline Metal shaders: fullscreen triangle-strip quad, textured blit.
        let src = """
        #include <metal_stdlib>
        using namespace metal;

        struct Vout { float4 pos [[position]]; float2 uv; };

        vertex Vout vtx(uint id [[vertex_id]]) {
            constexpr float2 p[4] = {{-1, 1}, {1, 1}, {-1, -1}, {1, -1}};
            constexpr float2 t[4] = {{ 0, 0}, {1, 0}, { 0,  1}, {1,  1}};
            return { float4(p[id], 0, 1), t[id] };
        }

        fragment float4 frg(Vout in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            sampler s           [[sampler(0)]]) {
            return tex.sample(s, in.uv);
        }
        """

        guard
            let lib    = try? device.makeLibrary(source: src, options: nil),
            let vtxFn  = lib.makeFunction(name: "vtx"),
            let frgFn  = lib.makeFunction(name: "frg")
        else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vtxFn
        desc.fragmentFunction = frgFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineState = try? device.makeRenderPipelineState(descriptor: desc)

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        samplerState = device.makeSamplerState(descriptor: sd)
    }

    // MARK: - mpv render context

    func initMpvRender(_ mpvCtx: OpaquePointer) {
        // SW render API — no platform-specific GL/Metal context required.
        // Use withCString to pin the API type string's lifetime across the context-create call.
        "sw".withCString { swPtr in
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                                 data: UnsafeMutableRawPointer(mutating: swPtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            var ctx: OpaquePointer?
            if mpv_render_context_create(&ctx, mpvCtx, &params) == 0, let ctx {
                renderCtx = ctx
            }
        }
        // No update callback needed — the display link polls mpv_render_context_update() each tick.
    }

    // MARK: - Render loop

    @objc private func tick() {
        guard
            let ctx      = renderCtx,
            let pipeline = pipelineState,
            let sampler  = samplerState
        else { return }

        // Only render when mpv has produced a new frame
        guard mpv_render_context_update(ctx) & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0
        else { return }

        let scale  = metalLayer.contentsScale
        let w = Int(bounds.width  * scale)
        let h = Int(bounds.height * scale)
        guard w > 0, h > 0 else { return }

        let targetSize = CGSize(width: w, height: h)
        if metalLayer.drawableSize != targetSize {
            metalLayer.drawableSize = targetSize
        }

        // Grow pixel buffer as needed (never shrink to avoid churn)
        let needed = w * h * 4
        if pixelData.count < needed {
            pixelData = [UInt8](repeating: 0, count: needed)
        }

        // Ask mpv to software-render the current frame into our pixel buffer
        pixelData.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            var size: [Int32]  = [Int32(w), Int32(h)]
            var stride: Int    = w * 4
            "bgra".withCString { fmtCStr in
                var fmtPtr: UnsafePointer<Int8> = fmtCStr
                withUnsafeMutablePointer(to: &fmtPtr) { fmtPtrPtr in
                    size.withUnsafeMutableBufferPointer { sizeBuf in
                        withUnsafeMutablePointer(to: &stride) { strideBuf in
                            var rp: [mpv_render_param] = [
                                mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE,    data: sizeBuf.baseAddress),
                                mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT,  data: fmtPtrPtr),
                                mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE,  data: strideBuf),
                                mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: base),
                                mpv_render_param(type: MPV_RENDER_PARAM_INVALID,    data: nil),
                            ]
                            mpv_render_context_render(ctx, &rp)
                        }
                    }
                }
            }
        }

        // Upload pixels to a cached MTLTexture (reallocate only on size change)
        if renderTexture == nil || renderTextureSize != targetSize {
            let td = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            td.usage = .shaderRead
            renderTexture     = device.makeTexture(descriptor: td)
            renderTextureSize = targetSize
        }
        guard let texture = renderTexture else { return }

        pixelData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(
                region:      MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                       size:   MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0,
                withBytes:   base,
                bytesPerRow: w * 4)
        }

        // Blit texture to the CAMetalLayer drawable
        guard
            let drawable  = metalLayer.nextDrawable(),
            let cmdBuf    = commandQueue.makeCommandBuffer()
        else { return }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture     = drawable.texture
        rpd.colorAttachments[0].loadAction  = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }
}
