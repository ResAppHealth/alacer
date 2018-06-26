//
//  ViewController.swift
//  Alacer
//
//  Created by Ryan Booker on 15/2/18.
//  Copyright © 2018 ResApp Health. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
    let engine = AVAudioEngine()
    let queue = DispatchQueue(label: "au.com.resapphealth.alacer", qos: .background)
    var converter: AVAudioConverter!
    var microphone: AVAudioInputNode!

    let sampleRate = 44100.0

    let commonFormat: AVAudioCommonFormat = .pcmFormatInt16

    var flacFile: AVAudioFile?
    var pcmFile: AVAudioFile?

    override func viewDidLoad() {
        super.viewDidLoad()

        configure()

        // Set up the microphone
        microphone = engine.inputNode

        // Converter
        let cf = AVAudioFormat(commonFormat: commonFormat, sampleRate: sampleRate, channels: 1, interleaved: true)!
        converter = AVAudioConverter(from: microphone.inputFormat(forBus: 0), to: cf)

        // File for writing
        let url = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("flac")

        let pcmURL = url.deletingPathExtension().appendingPathExtension("caf")

        flacFile = try! AVAudioFile(forWriting: url, settings: flacFileFormat, commonFormat: commonFormat, interleaved: true)
        pcmFile = try! AVAudioFile(forWriting: pcmURL, settings: pcmFileFormat, commonFormat: commonFormat, interleaved: true)

        // Tap the microphone and write the output
        let size = AVAudioFrameCount(microphone.inputFormat(forBus: 0).sampleRate / 10)
        microphone.installTap(onBus: 0, bufferSize: size, format: nil) { buffer, time in
            guard let b = buffer.copy() as? AVAudioPCMBuffer else { return }
            self.queue.async {
                let bb = self.convert(buffer: b)
                try! self.flacFile?.write(from: bb)
                try! self.pcmFile?.write(from: bb)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Record for 3 seconds
        try! engine.start()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 3) {
            self.engine.stop()
            self.microphone.removeTap(onBus: 0)
            self.flacFile = nil
            self.pcmFile = nil
            print("done")
        }
    }

    var flacFileFormat: [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatFLAC,
            AVAudioFileTypeKey: kAudioFileFLACType,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
    }

    var pcmFileFormat: [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
    }

}

extension ViewController {
    func configure() {
        let session = AVAudioSession.sharedInstance()
        try! session.setCategory(AVAudioSessionCategoryPlayAndRecord,
                                 mode: AVAudioSessionModeMeasurement,
                                 options: .defaultToSpeaker)
        try! session.setActive(true)

        // Set the preferred sample rate and channel count
        // NB: These are required to set the hardware to a mono only mose
        // that doesn't engage the noise cancelling system if the ear piece
        // mic is coverred—even though AVAudioEngine still delivers a stereo
        // input.
        try! session.setPreferredSampleRate(44100)
        try! session.setPreferredInputNumberOfChannels(1)

        // Enforce the the built-in bottom mic, in case other inputs have
        // been added or are active.
        // NB: The built in bottom mic does not have/support data sources,
        // so there is no need/way to filter and set a preferred data
        // source.
        try! session.availableInputs?
            .filter { $0.portType == AVAudioSessionPortBuiltInMic }
            .forEach(session.setPreferredInput)
    }

    func convert(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let converter = converter else { return buffer }

        let sampleRateIn = converter.inputFormat.sampleRate
        let sampleRateOut = converter.outputFormat.sampleRate
        guard sampleRateOut > 0 else { return buffer }

        let sampleRateConversionRatio: Double = sampleRateIn/sampleRateOut
        let capacity = UInt32(Double(buffer.frameCapacity) / sampleRateConversionRatio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            return buffer
        }

        var processed = false
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            guard !processed else {
                outStatus.pointee = AVAudioConverterInputStatus.noDataNow
                return nil
            }
            processed = true
            outStatus.pointee = AVAudioConverterInputStatus.haveData
            return buffer
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if let error = error, status == .error {
            print(error.localizedDescription)
        }

        return outputBuffer
    }
}
