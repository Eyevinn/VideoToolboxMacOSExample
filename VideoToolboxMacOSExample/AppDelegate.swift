//
//  AppDelegate.swift
//  VideoToolboxMacOSExample
//
//  Created by Eyevinn on 2021-08-17.
//

import AVFoundation
import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {

  var cameraWindow: NSWindow!
  var decompressedWindow: NSWindow!
  
  let cameraView = VideoView()
  let decoderView = VideoView()
  
  private var encoder: H264Encoder?
  private var decoder: H264Decoder?
  
  let avManager = AVManager()

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    // Create the windows and set the content view.
    cameraWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false)
    cameraWindow.isReleasedWhenClosed = false
    cameraWindow.center()
    cameraWindow.setTitleWithRepresentedFilename("Camera view")
    cameraWindow.contentView = NSHostingView(rootView: cameraView)
    cameraWindow.makeKeyAndOrderFront(nil)
    
    // To see the decompressed video, uncomment line 69
    decompressedWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    decompressedWindow.isReleasedWhenClosed = false
    decompressedWindow.center()
    decompressedWindow.setTitleWithRepresentedFilename("Decoded view")
    decompressedWindow.contentView = NSHostingView(rootView: decoderView)
    decompressedWindow.makeKeyAndOrderFront(nil)
    
    // Create encoder here (at the expense of dynamic setting of height and width)
    encoder = H264Encoder(width: 1280, height: 720, callback: { encodedBuffer in
      // self.sampleBufferNoOpProcessor(encodedBuffer) // Logs the buffers to the console for inspection
      self.decodeCompressedFrame(encodedBuffer) // uncomment to see decoded video
    })
    encoder?.delegate = self
    encoder?.fps = 15
    encoder?.prepareToEncodeFrames()
    
    
    
    avManager.delegate = self
    avManager.start()
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
    encoder?.stop()
  }

  private func sampleBufferNoOpProcessor(_ sampleBuffer: CMSampleBuffer) {
    print("Buffer received: \(sampleBuffer)")
  }
  
  private func decodeCompressedFrame(_ sampleBuffer: CMSampleBuffer) {
      if decoder == nil,
         let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
          decoder = H264Decoder(formatDescription: formatDescription) { decoded in
              self.decoderView.render(decoded)
          }
      }
      decoder?.decode(sampleBuffer)
  }
}

// MARK: - AVManagerDelegate
extension AppDelegate : AVManagerDelegate {
    func onSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        cameraView.render(sampleBuffer)
        encoder?.encodeBySampleBuffer(sampleBuffer)
    }
}
// MARK: - H264EncoderDelegate

extension AppDelegate : H264EncoderDelegate {
    func dataCallBack(_ data: Data!, frameType: FrameType) {
        let byteHeader:[UInt8] = [0,0,0,1]
        var byteHeaderData = Data(byteHeader)
        byteHeaderData.append(data)
        // Could decode here
        // H264Decoder.decode(byteHeaderData)
    }

    func spsppsDataCallBack(_ sps: Data!, pps: Data!) {
        let spsbyteHeader:[UInt8] = [0,0,0,1]
        var spsbyteHeaderData = Data(spsbyteHeader)
        var ppsbyteHeaderData = Data(spsbyteHeader)
        spsbyteHeaderData.append(sps)   
        ppsbyteHeaderData.append(pps)
        // Could decode here
        // H264Decoder.decode(spsbyteHeaderData)
        // H264Decoder.decode(ppsbyteHeaderData)
    }
}

