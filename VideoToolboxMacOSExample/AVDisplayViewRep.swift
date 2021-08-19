//
//  AVDisplayViewRep.swift
//  VideoToolboxMacOSExample
//
//  Created by Eyevinn on 2021-08-18.
//

import AVFoundation
import Cocoa
import SwiftUI

final class AVDisplayViewRep: NSViewRepresentable {

    typealias NSViewType = AVDisplayView

    var view: AVDisplayView!

    func makeNSView(context: Context) -> AVDisplayView {
        let view = AVDisplayView()
        self.view = view
        return view
    }

    func updateNSView(_ nsView: AVDisplayView, context: Context) {
        print("updateNSView AVDisplayView")
    }

    func render(_ sampleBuffer: CMSampleBuffer) {
        view?.render(sampleBuffer)
    }

}

class AVDisplayView: NSView {

    // MARK: - Properties

    var videoLayer: AVSampleBufferDisplayLayer?

    // MARK: - Life Cycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override var wantsUpdateLayer: Bool {
        return true
    }

    override func layout() {
        super.layout()
        videoLayer?.removeFromSuperlayer()
        let videoLayer = AVSampleBufferDisplayLayer()
        videoLayer.backgroundColor = .white
        videoLayer.frame = bounds
        videoLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(videoLayer)
        self.videoLayer = videoLayer
        print("layout, layer: \(videoLayer.frame)")
    }

    func render(_ sampleBuffer: CMSampleBuffer) {
        guard let videoLayer = videoLayer else {
            return
        }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)
        let numValues = CFArrayGetCount(attachments)
        for i in 0..<numValues {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, i), to: CFMutableDictionary.self)
            let key = Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque()
            let value = Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            CFDictionaryAddValue(dict, key, value)
        }
        DispatchQueue.main.async {
            videoLayer.flush()
            guard videoLayer.isReadyForMoreMediaData else {
                print("is NOT ready", sampleBuffer)
                return
            }
            videoLayer.displayIfNeeded()
            videoLayer.enqueue(sampleBuffer)
            videoLayer.setNeedsDisplay()
        }
    }

}

