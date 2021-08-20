//
//  H264Encoder.swift
//  VideoToolboxMacOSExample
//
//  Created by Eyevinn on 2021-08-18.
//

import AVFoundation
import CoreFoundation
import CoreMedia
import VideoToolbox

class H264Encoder {

    var session: VTCompressionSession?
    let callback: (CMSampleBuffer) -> Void

    var array = [CMSampleBuffer]()

    let outputCallback: VTCompressionOutputCallback = { refcon, sourceFrameRefCon, status, infoFlags, sampleBuffer in
        guard let refcon = refcon,
              status == noErr,
              let sampleBuffer = sampleBuffer else {
            print("H264Coder outputCallback sampleBuffer NULL or status: \(status)")
            return
        }

        let encoder: H264Encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.processSample(sampleBuffer)
    }

    func processSample(_ sampleBuffer: CMSampleBuffer) {
        guard nil != CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("H264Coder outputCallback dataBuffer NIL")
            return
        }

        guard let copiedSampleBuffer = copySB(sampleBuffer) else { return }

        // trying to store sample buffers in queue. it kind of works, but the video is distorted. getting lots of: GVA error: scheduleDecodeFrame kVTVideoDecoderBadDataErr nal_size err : nal_size = 2787177045, acc_size = 2787283463, datasize = 110145, video_nal_count = 1, length_offset = 4, nal_unit_type  = 9...

        array += [copiedSampleBuffer]
        if array.count < 20 {
            callback(copiedSampleBuffer)
        } else {
            let element = array.removeFirst()
            callback(element)
        }
    }

    private func copySB(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
        let formatDescriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer)  else { return nil }

        let copiedSampleBuffer: UnsafeMutablePointer<CMSampleBuffer?> = .allocate(capacity: 1)
        let copiedDataBuffer: UnsafeMutablePointer<CMBlockBuffer?> = .allocate(capacity: 1)

        let (data, length) = H264Encoder.getDataFrom(blockBuffer)
        print("retainedData", data)
        let nsData = NSMutableData(data: data)
        CMBlockBufferCreateEmpty (allocator: nil,capacity: 0,flags: kCMBlockBufferAlwaysCopyDataFlag, blockBufferOut: copiedDataBuffer)
        CMBlockBufferAppendMemoryBlock(copiedDataBuffer.pointee!,
                                       memoryBlock: nsData.mutableBytes,
                                       length: length,
                                       blockAllocator: nil,
                                       customBlockSource: nil,
                                       offsetToData: 0,
                                       dataLength: length,
                                       flags: kCMBlockBufferAlwaysCopyDataFlag);

        let (timingInfo, timingInfoCount) = H264Encoder.getTimingArray(sampleBuffer)
        let (sizeArray, sizeArrayCount) = H264Encoder.getSizeArray(sampleBuffer)
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)

        let retainedDataBuffer = Unmanaged.passRetained(copiedDataBuffer.pointee!)
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, // allocator
            dataBuffer: retainedDataBuffer.takeRetainedValue(),
            dataReady: true, // dataReady
            makeDataReadyCallback: nil, // makeDataReadyCallback
            refcon: nil, // makeDataReadyRefcon
            formatDescription: formatDescriptionRef, // formatDescription
            sampleCount: sampleCount, // sampleCount
            sampleTimingEntryCount: timingInfoCount, // sampleTimingEntryCount
            sampleTimingArray: timingInfo, // sampleTimingArray
            sampleSizeEntryCount: sizeArrayCount, // sampleSizeEntryCount
            sampleSizeArray: sizeArray, // sampleSizeArray
            sampleBufferOut: copiedSampleBuffer // sampleBufferOut
        )
        timingInfo.deallocate()
        sizeArray.deallocate()
        H264Encoder.copyAttachments(from: sampleBuffer, to: copiedSampleBuffer.pointee!)
//        print(blockBuffer, "copied", copiedDataBuffer.pointee!)
//        print(sampleBuffer, "copied", copiedSampleBuffer.pointee!)
        return copiedSampleBuffer.pointee!

    }

    init(width: Int32, height: Int32, callback: @escaping (CMSampleBuffer) -> Void) {
        self.callback = callback
        let encoderSpecification = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true as CFBoolean
        ] as CFDictionary
        var status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: width, height: height, codecType: kCMVideoCodecType_H264, encoderSpecification: encoderSpecification, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: outputCallback, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &session)
        print("H264Coder init \(status == noErr) \(status)")
        // This demonstrates setting a property after the session has been created
        guard let compressionSession = session else { return }
        status = VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    }

    func encode(_ sampleBuffer: CMSampleBuffer) {
        guard let compressionSession = session,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let _ = VTCompressionSessionEncodeFrame(compressionSession, imageBuffer: imageBuffer, presentationTimeStamp: timestamp, duration: .invalid, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
    }

    func stop() {
        guard let session = session else { return }
        VTCompressionSessionInvalidate(session)
    }

    deinit {
        print("deinited H264Coder")
    }


    static func getDataFrom(_ buffer: CMBlockBuffer) -> (Data, Int) {
        var totalLength = Int()
        var length = Int()
        var dataPointer: UnsafeMutablePointer<Int8>?
        let _ = CMBlockBufferGetDataPointer(buffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

//        if state == noErr {
//            var bufferOffset = 0;
//            let AVCCHeaderLength = 4
//
//            while bufferOffset < totalLength - AVCCHeaderLength {
//                var NALUnitLength:UInt32 = 0
//                memcpy(&NALUnitLength, dataPointer! + bufferOffset, AVCCHeaderLength)
//                NALUnitLength = CFSwapInt32BigToHost(NALUnitLength)
//
//                var naluStart:[UInt8] = [0,0,0,1]
//                data.append(&naluStart, length: naluStart.count)
//                data.append(dataPointer! + bufferOffset + AVCCHeaderLength, length: Int(NALUnitLength))
//                bufferOffset += (AVCCHeaderLength + Int(NALUnitLength))
//            }
//        }

//        print("dataPointer", dataPointer)
        return (Data(bytes: dataPointer!, count: length), length)
    }

    static func copyAttachments(from sampleBuffer: CMSampleBuffer, to output: CMSampleBuffer) {
        attachments(from: sampleBuffer)
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) else { return }
        let newAttachments = CMSampleBufferGetSampleAttachmentsArray(output, createIfNecessary: true)!
        let numValues = CFArrayGetCount(attachmentsArray)
        for i in 0..<numValues {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, i), to: CFDictionary.self)
            let newDict = unsafeBitCast(CFArrayGetValueAtIndex(newAttachments, i), to: CFMutableDictionary.self)

            let dictCount = CFDictionaryGetCount(dict)
            let keys = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: dictCount)
            let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: dictCount)

            CFDictionaryGetKeysAndValues(dict, keys, values)

            for j in 0..<dictCount {
                CFDictionarySetValue(newDict, keys[j], values[j])
            }
            let key = Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque()
            let value = Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            CFDictionaryAddValue(newDict, key, value)
            keys.deallocate()
            values.deallocate()
        }
    }

    static func attachments(from sampleBuffer: CMSampleBuffer) {
        let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)!
        let numValues = CFArrayGetCount(attachmentsArray)
        
        for i in 0..<numValues {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, i), to: CFDictionary.self) as NSDictionary
            let _ = dict.allKeys as! [CFString]
            let _ = dict.allValues as! [CFBoolean]
        }
    }

    static func getTimingArray(_ sampleBuffer: CMSampleBuffer) -> (pointer: UnsafeMutablePointer<CMSampleTimingInfo>, count: CMItemCount) {
        var entriesCount: CMItemCount = 0
        _ = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &entriesCount)
        let timingArray = UnsafeMutablePointer<CMSampleTimingInfo>.allocate(capacity: entriesCount)
        _ = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: entriesCount, arrayToFill: timingArray, entriesNeededOut: &entriesCount)
        return (timingArray, entriesCount)
    }

    static func getSizeArray(_ sampleBuffer: CMSampleBuffer) -> (pointer: UnsafeMutablePointer<Int>, count: CMItemCount) {
        var entriesCount: CMItemCount = 0
        _ =  CMSampleBufferGetSampleSizeArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &entriesCount)
        let sizeArray = UnsafeMutablePointer<Int>.allocate(capacity: entriesCount)
        _ = CMSampleBufferGetSampleSizeArray(sampleBuffer, entryCount: entriesCount, arrayToFill: sizeArray, entriesNeededOut: &entriesCount)
        return (sizeArray, entriesCount)
    }

}

// not used in current demo:
struct EncodedSampleBuffer {
    let formatDescription: CMFormatDescription
    let sampleCount: CMItemCount
    let bufferData: Data
    let bufferDataLenght: Int
    let timingInfo: CMSampleTimingInfo
    let timingInfoCount: CMItemCount
    let sizeArray: [Int]
}

extension EncodedSampleBuffer {

    init(with sampleBuffer: CMSampleBuffer) {
        formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)!
        sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)!
        let (data, bufferDataLenght) = H264Encoder.getDataFrom(blockBuffer)
        self.bufferDataLenght = bufferDataLenght
        bufferData = data as Data
        let (timingInfoPtr, timingInfoCount) = H264Encoder.getTimingArray(sampleBuffer)
        timingInfo = timingInfoPtr.pointee
        self.timingInfoCount = timingInfoCount
        let (sizeArrayPtr, sizeArrayCount) = H264Encoder.getSizeArray(sampleBuffer)
        let a = UnsafeMutableBufferPointer(start: sizeArrayPtr, count: sizeArrayCount)
        sizeArray = Array(a)
    }

}


