//
//  H264Decoder.swift
//  VideoToolboxMacOSExample
//
//  Created by Eyevinn on 2021-08-18.
//

import AVFoundation
import CoreFoundation
import CoreMedia
import VideoToolbox

class H264Decoder {

    var session: VTDecompressionSession?

    var callback: VTDecompressionOutputCallback = { refcon, sourceFrameRefCon, status, infoFlags, imageBuffer, time, duration in
        guard let refcon = refcon,
              status == noErr,
              let imageBuffer = imageBuffer else {
            print("VTDecompressionOutputCallback \(status)")
            return }
        let decoder: H264Decoder = Unmanaged<H264Decoder>.fromOpaque(refcon).takeUnretainedValue()
        decoder.processImage(imageBuffer, time: time, duration: duration)
    }

    let handler: (CMSampleBuffer) -> Void

    init(formatDescription: CMVideoFormatDescription, handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var callbackRecord = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: callback, decompressionOutputRefCon: refcon)

        let decoderSpecification = [
            kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: true as CFBoolean
        ] as CFDictionary

        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: formatDescription, decoderSpecification: decoderSpecification, imageBufferAttributes: nil, outputCallback: &callbackRecord, decompressionSessionOut: &session)
        print("H264Decoder init, status: \(status == noErr)")
    }

    func processImage(_ image: CVImageBuffer, time: CMTime, duration: CMTime) {
        var sampleBuffer: CMSampleBuffer?
        var sampleTiming = CMSampleTimingInfo(duration: duration, presentationTimeStamp: time, decodeTimeStamp: time)

        var formatDesc: CMFormatDescription? = nil
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescriptionOut: &formatDesc)
        guard let formatDescription = formatDesc else {
            fatalError("formatDescription")
        }

        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: image,
            formatDescription: formatDescription,
            sampleTiming: &sampleTiming,
            sampleBufferOut: &sampleBuffer)
        if status != noErr {
            print("CMSampleBufferCreateReadyWithImageBuffer failure \(status)")
        }
        if let sb = sampleBuffer {
            handler(sb)
        }
    }

    func decode(_ sampleBuffer: CMSampleBuffer) {
        guard let session = session else { return }
        let flags = VTDecodeFrameFlags._1xRealTimePlayback
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags: flags, frameRefcon: nil, infoFlagsOut: nil)
        print("H264Decoder decode, status: \(status)")
    }

    func stop() {
        guard let session = session else { return }
        VTDecompressionSessionInvalidate(session)
    }

    deinit {
        print("deinited H264Decoder")
    }

}
