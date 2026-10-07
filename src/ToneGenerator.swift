// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

import AVFoundation
import Combine
import Foundation

final class ToneGenerator: ObservableObject {
    // The app's only gain stage. 0.11 full scale is the ceiling a studio ear tolerates.
    static let headroom = 0.11

    @Published private(set) var isRunning = false
    @Published var volume: Double = 0.5 {
        didSet { osc.targetGain = isRunning ? volume * Self.headroom : 0.0 }
    }

    private let engine = AVAudioEngine()
    private let osc = SineOscillator(sampleRate: 48000.0)
    private var source: AVAudioSourceNode?

    init() {
        buildGraph()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationChanged),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        engine.stop()
    }

    func start() {
        guard !isRunning else { return }
        if !engine.isRunning {
            do { try engine.start() } catch {
                NSLog("SA-Sur: audio engine failed to start: \(error)")
                return
            }
        }
        osc.targetGain = volume * Self.headroom
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        osc.targetGain = 0.0
        isRunning = false
    }

    func toggle() { isRunning ? stop() : start() }

    func setFrequency(_ hz: Double) { osc.frequency = hz }

    func shutdown() {
        osc.targetGain = 0.0
        isRunning = false
        engine.stop()
    }

    var engineIsRunning: Bool { engine.isRunning }
    var configuredSampleRate: Double { osc.sampleRate }

    func measureOffline(seconds: Double, gain: Double) -> (left: [Float], right: [Float], sampleRate: Double, channels: Int)? {
        stop()
        engine.stop()
        if let existing = source {
            engine.detach(existing)
            source = nil
        }

        let rate = hardwareSampleRate()
        osc.sampleRate = rate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return nil }
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        } catch {
            NSLog("SA-Sur: cannot enable offline rendering: \(error)")
            return nil
        }

        buildGraph()
        osc.targetGain = gain
        do {
            try engine.start()
        } catch {
            NSLog("SA-Sur: offline engine failed to start: \(error)")
            engine.disableManualRenderingMode()
            return nil
        }

        let channels = Int(engine.manualRenderingFormat.channelCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else {
            engine.stop()
            engine.disableManualRenderingMode()
            return nil
        }

        var left: [Float] = []
        var right: [Float] = []
        var remaining = Int(seconds * rate)
        while remaining > 0 {
            let frames = AVAudioFrameCount(min(4096, remaining))
            do {
                let status = try engine.renderOffline(frames, to: buffer)
                if status != .success { break }
                if let data = buffer.floatChannelData {
                    let count = Int(buffer.frameLength)
                    left.append(contentsOf: UnsafeBufferPointer(start: data[0], count: count))
                    right.append(contentsOf: UnsafeBufferPointer(start: data[1], count: count))
                }
            } catch {
                NSLog("SA-Sur: offline render failed: \(error)")
                break
            }
            remaining -= Int(frames)
        }

        engine.stop()
        engine.disableManualRenderingMode()
        return (left, right, rate, channels)
    }

    func resumeDeviceMode() {
        buildGraph()
    }

    private func hardwareSampleRate() -> Double {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        return rate > 0 ? rate : 48000.0
    }

    private func buildGraph() {
        osc.sampleRate = hardwareSampleRate()

        if let existing = source {
            engine.detach(existing)
            source = nil
        }

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, ablPointer -> OSStatus in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(ablPointer)
            guard let first = abl.first, let firstData = first.mData else { return noErr }
            let out = firstData.assumingMemoryBound(to: Float.self)
            self.osc.render(into: out, frameCount: Int(frameCount))
            if abl.count > 1 {
                for i in 1..<abl.count {
                    if let dst = abl[i].mData {
                        dst.copyMemory(from: firstData, byteCount: Int(frameCount) * MemoryLayout<Float>.size)
                    }
                }
            }
            return noErr
        }

        source = node
        engine.attach(node)
        if let format = AVAudioFormat(standardFormatWithSampleRate: osc.sampleRate, channels: 2) {
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        engine.prepare()
    }

    @objc private func configurationChanged() {
        let wasRunning = isRunning
        isRunning = false
        osc.targetGain = 0.0
        engine.stop()
        buildGraph()
        if wasRunning { start() }
    }
}
