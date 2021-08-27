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

enum FrameType : UInt {
    case FrameType_SPSPPS
    case FrameType_IFrame
    case FrameType_PFrame
}

protocol H264EncoderDelegate: AnyObject {
    func dataCallBack(_ data: Data!, frameType: FrameType)
    func spsppsDataCallBack(_ sps:Data!, pps: Data!)
}

class H264Encoder {

    // MARK: - Properties
    weak var delegate: H264EncoderDelegate?
    var session: VTCompressionSession?
    let callback: (CMSampleBuffer) -> Void
    var width: Int32
    var height: Int32
    var fps: Int32 = 10
    var frameCount: Int64
    var shouldUnpack: Bool

    var array = [CMSampleBuffer]()

    let outputCallback: VTCompressionOutputCallback = { refcon, sourceFrameRefCon, status, infoFlags, sampleBuffer in
        guard let refcon = refcon,
              status == noErr,
              let sampleBuffer = sampleBuffer else {
            print("H264Coder outputCallback sampleBuffer NULL or status: \(status)")
            return
        }
      
        if (!CMSampleBufferDataIsReady(sampleBuffer))
        {
            print("didCompressH264 data is not ready...");
            return;
        }
        let encoder: H264Encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
        if(encoder.shouldUnpack) {
            var isKeyFrame:Bool = false

    //      Attempting to get keyFrame
            guard let attachmentsArray:CFArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) else { return }
            if (CFArrayGetCount(attachmentsArray) > 0) {
                let cfDict = CFArrayGetValueAtIndex(attachmentsArray, 0)
                let dictRef: CFDictionary = unsafeBitCast(cfDict, to: CFDictionary.self)

                let value = CFDictionaryGetValue(dictRef, unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self))
                if(value == nil) {
                    isKeyFrame = true
                }
            }

            if(isKeyFrame) {
                var description: CMFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)!
                // First, get SPS
                var sparamSetCount: size_t = 0
                var sparamSetSize: size_t = 0
                var sparameterSetPointer: UnsafePointer<UInt8>?
                var statusCode: OSStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: &sparameterSetPointer, parameterSetSizeOut: &sparamSetSize, parameterSetCountOut: &sparamSetCount, nalUnitHeaderLengthOut: nil)
                
                if(statusCode == noErr) {
                    // Then, get PPS
                    var pparamSetCount: size_t = 0
                    var pparamSetSize: size_t = 0
                    var pparameterSetPointer: UnsafePointer<UInt8>?
                    var statusCode: OSStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: &pparameterSetPointer, parameterSetSizeOut: &pparamSetSize, parameterSetCountOut: &pparamSetCount, nalUnitHeaderLengthOut: nil)
                    if(statusCode == noErr) {
                        var sps = NSData(bytes: sparameterSetPointer, length: sparamSetSize)
                        var pps = NSData(bytes: pparameterSetPointer, length: pparamSetSize)
                        encoder.delegate?.spsppsDataCallBack(sps as Data, pps: pps as Data)
                    }
                }
            }
            
            var dataBuffer: CMBlockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)!
            var length: size_t = 0
            var totalLength: size_t = 0
            var bufferDataPointer: UnsafeMutablePointer<Int8>?
            var statusCodePtr: OSStatus = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: &totalLength, dataPointerOut: &bufferDataPointer)
            if(statusCodePtr == noErr) {
                var bufferOffset: size_t = 0
                let AVCCHeaderLength: Int = 4
                while(bufferOffset < totalLength - AVCCHeaderLength) {
                    // Read the NAL unit length
                    var NALUnitLength: UInt32 = 0
                    memcpy(&NALUnitLength, bufferDataPointer! + bufferOffset, AVCCHeaderLength)
                    //Big-Endian to Little-Endian
                    NALUnitLength = CFSwapInt32BigToHost(NALUnitLength)
                    
                    var data = NSData(bytes:(bufferDataPointer! + bufferOffset + AVCCHeaderLength), length: Int(Int32(NALUnitLength)))
                    var frameType: FrameType = .FrameType_PFrame
                    var dataBytes = Data(bytes: data.bytes, count: data.length)
                    if((dataBytes[0] & 0x1F) == 5) {
                        // I-Frame
                        print("is IFrame")
                        frameType = .FrameType_IFrame
                    }

                    encoder.delegate?.dataCallBack(data as Data, frameType: frameType)
                    // Move to the next NAL unit in the block buffer
                    bufferOffset += AVCCHeaderLength + size_t(NALUnitLength);
                }
            }
        }
 
        encoder.processSample(sampleBuffer)
    }

    private func processSample(_ sampleBuffer: CMSampleBuffer) {
        guard nil != CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("H264Coder outputCallback dataBuffer NIL")
            return
        }

        callback(sampleBuffer)
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
        self.width = width
        self.height = height
        self.frameCount = 0
        self.shouldUnpack = true
    }
  
    func prepareToEncodeFrames() {
        let encoderSpecification = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true as CFBoolean
        ] as CFDictionary
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: self.width, height: self.height, codecType: kCMVideoCodecType_H264, encoderSpecification: encoderSpecification, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: outputCallback, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &session)
        print("H264Coder init \(status == noErr) \(status)")
        // This demonstrates setting a property after the session has been created
        guard let compressionSession = session else { return }
        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &self.fps))
        VTCompressionSessionPrepareToEncodeFrames(compressionSession)
    }

    func encodeBySampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Get CV Image buffer
        let imageBuffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        encodeByPixelBuffer(imageBuffer)
    }
    
    func encodeByPixelBuffer(_ cvPixelBuffer: CVPixelBuffer) {
        frameCount += 1
        let imageBuffer: CVImageBuffer = cvPixelBuffer
        // Make properties
        let presentationTimeStamp = CMTimeMake(value: frameCount, timescale: 1000)
        var _: OSStatus = VTCompressionSessionEncodeFrame(session!, imageBuffer: imageBuffer, presentationTimeStamp: presentationTimeStamp, duration: .invalid, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
        
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
        frameCount = 0
        self.session = nil
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


