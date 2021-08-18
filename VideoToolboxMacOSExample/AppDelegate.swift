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
class AppDelegate: NSObject, NSApplicationDelegate, AVManagerDelegate {

  var cameraWindow: NSWindow!
  var decompressedWindow: NSWindow!
  
  let cameraView = VideoView()
  let decoderView = VideoView()
  
  
  private var encoder: H264Coder?
  private var decoder: H264Decoder?
  
  let avManager = AVManager()

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    // Create the windows and set the content view.
    cameraWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
    cameraWindow.isReleasedWhenClosed = false
    cameraWindow.center()
    cameraWindow.setTitleWithRepresentedFilename("Camera view")
    cameraWindow.contentView = NSHostingView(rootView: cameraView)
    cameraWindow.makeKeyAndOrderFront(nil)
    
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
    
    avManager.delegate = self
    avManager.start()
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }

  // MARK: - AVManagerDelegate

  func onSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
      cameraView.render(sampleBuffer)
      // guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
      if encoder == nil,
         let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
          let dimens = formatDescription.dimensions
          encoder = H264Coder(width: dimens.width, height: dimens.height, callback: { encodedBuffer in
              // self.sampleBufferNoOpProcessor(encodedBuffer)
            self.decodeCompressedFrame(encodedBuffer)
          })
      }
      encoder?.encode(sampleBuffer)
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

