//
//  VideoView.swift
//  VideoToolboxMacOSExample
//
//  Created by Eyevinn on 2021-08-18.
//

import AVFoundation
import SwiftUI

struct VideoView: View {

    let displayView = RenderViewRep() // metal or AVDisplayViewRep to use AVSampleBufferDisplayLayer
    // let displayView = AVDisplayViewRep()
    
    var body: some View {
        displayView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func render(_ sampleBuffer: CMSampleBuffer)  {
        displayView.render(sampleBuffer)
    }
}

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        VideoView()
    }
}
