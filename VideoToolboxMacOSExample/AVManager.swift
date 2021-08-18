//
//  AVManager.swift
//  VideoToolboxMacOSExample
//
//  Created by Eyevinn on 2021-08-18.
//

import AVFoundation

protocol AVManagerDelegate: AnyObject {

    func onSampleBuffer(_ sampleBuffer: CMSampleBuffer)

}

class AVManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Properties

    weak var delegate: AVManagerDelegate?

    var session: AVCaptureSession!

    private let sessionQueue = DispatchQueue(label:"se.eyevinn.sessionQueue")

    private let videoQueue = DispatchQueue(label: "videoQueue")

    private var connection: AVCaptureConnection!

    private var camera: AVCaptureDevice?

    func start() {
        requestCameraPermission { [weak self] granted in
            guard granted else {
                print("no camera access")
                return
            }
            self?.setupCaptureSession()
        }
    }

    private func setupCaptureSession() {
        sessionQueue.async {
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInWideAngleCamera
            ]
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .front)
            let session = AVCaptureSession()
            session.sessionPreset = .vga640x480

            guard let camera = discoverySession.devices.first,
                  let format = camera.formats.first(where: {
                    let dimens = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                    return dimens.width * dimens.height == 640 * 480
                  }) else { fatalError("no camera of camera format") }

            do {
                try camera.lockForConfiguration()
                camera.activeFormat = format
                camera.unlockForConfiguration()
            } catch {
                print("failed to set up format")
            }
            self.camera = camera

            session.beginConfiguration()
            do {
                let videoIn = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(videoIn) {
                    session.addInput(videoIn)
                } else {
                    print("failed to add video input")
                    return
                }
            } catch {
                print("failed to initialized video input")
                return
            }

            let videoOut = AVCaptureVideoDataOutput()
            videoOut.videoSettings = [ kCVPixelBufferPixelFormatTypeKey as String:  Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            ]
            videoOut.alwaysDiscardsLateVideoFrames = true
            videoOut.setSampleBufferDelegate(self, queue: self.videoQueue)
            if session.canAddOutput(videoOut) {
                session.addOutput(videoOut)
            } else {
                print("failed to add video output")
                return
            }
            session.commitConfiguration()
            session.startRunning()
            self.session = session
        }
    }

    private func requestCameraPermission(handler: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: // The user has previously granted access to the camera.
                handler(true)

            case .notDetermined: // The user has not yet been asked for camera access.
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    handler(granted)
                }

            case .denied, .restricted: // The user can't grant access due to restrictions.
                handler(false)
        @unknown default:
            fatalError()
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        delegate?.onSampleBuffer(sampleBuffer)
    }

    // MARK: - Types

    enum AVError: Error {

        case noCamera
        case cameraAccess

    }
}
