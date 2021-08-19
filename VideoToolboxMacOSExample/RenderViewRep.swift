//
//  RenderViewRep.swift
//  VideoToolboxMacOSExample
//
//  Created by Eyevinn on 2021-08-18.
//

import AppKit
import AVFoundation
import MetalKit
import SwiftUI

final class RenderViewRep: NSViewRepresentable {

    typealias NSViewType = RenderView

    var view: RenderView!

    func makeNSView(context: Context) -> RenderView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError( "Failed to get the system's default Metal device." )
        }
        let view = RenderView(frame: .zero, device: device)
        self.view = view
        return view
    }

    func updateNSView(_ nsView: RenderView, context: Context) {
        print("updateNSView Metal")
    }

    func render(_ sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        view?.render(imageBuffer)
    }

}

class RenderView: MTKView, MTKViewDelegate {

    private var ciImage: CIImage? {
        didSet {
            draw()
        }
    }

    private lazy var commandQueue: MTLCommandQueue? = { [unowned self] in
        return self.device!.makeCommandQueue()
    }()

    private lazy var ciContext: CIContext = { [unowned self] in
        return CIContext(mtlDevice: self.device!)
    }()

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        if super.device == nil {
            fatalError("No metal")
        }
        enableSetNeedsDisplay = true
        framebufferOnly = false
        isPaused = true
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // disable error sound for key down events (space bar for play / pause)
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        return true
    }

    func render(_ pixelBuffer: CVImageBuffer) {
        ciImage = CIImage(cvImageBuffer: pixelBuffer)
        draw()
    }

    // MARK: - NSViewRepresentable

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

    func draw(in view: MTKView) {
        guard let ciImage = ciImage,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        ciContext.render(ciImage,
                         to: drawable.texture,
              commandBuffer: commandBuffer,
                     bounds: CGRect(origin: .zero, size: view.drawableSize),
                 colorSpace: CGColorSpaceCreateDeviceRGB())
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

}

