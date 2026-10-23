//
//  WaveformView.swift
//  Nuage
//
//  Created by Laurin Brandner on 14.01.21.
//

import SwiftUI
import Combine
import SoundCloud

private let spacing: CGFloat = 3
private let barWidth: CGFloat = 3
private let emptyWaveform = Waveform(samples: Array(repeating: 2, count: 100))

struct WaveformView: View {
    
    var url: URL?
    @State private var waveform = emptyWaveform
    
    @State private var subscriptions = Set<AnyCancellable>()
    
    var body: some View {
        GeometryReader { geometry in
            let numberOfBars = max(Int((geometry.size.width+spacing)/(spacing+barWidth)), 0)
            let bars = self.bars(count: numberOfBars)
            let maxBar = bars.max() ?? 0
            let shouldScale = (self.waveform != emptyWaveform) && maxBar > 0
            
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    let height = shouldScale ? (bar / maxBar) * geometry.size.height : bar
                    
                    Rectangle()
                        .frame(width: barWidth, height: height)
                        .cornerRadius(barWidth/2)
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            .animation(.spring(), value: waveform)
        }
        .onAppear {
            guard let url = url else { return }
            SoundCloud.shared.get(.waveform(url))
                .replaceError(with: emptyWaveform)
                .receive(on: RunLoop.main)
                .sink { waveform in
                    withAnimation {
                        self.waveform = waveform
                    }
                }
                .store(in: &subscriptions)
        }
    }
    
    /// Averages the samples into `count` bars, each normalized to 0...1.
    private func bars(count: Int) -> [CGFloat] {
        let samples = waveform.samples
        let maxHeight = CGFloat(waveform.maxHeight)
        guard count > 0, !samples.isEmpty, maxHeight > 0 else {
            return Array(repeating: 0, count: count)
        }
        
        let samplesPerBar = CGFloat(samples.count)/CGFloat(count)
        return (0..<count).map { bar in
            let lhs = Int(CGFloat(bar)*samplesPerBar)
            let rhs = max(lhs, min(Int(CGFloat(bar+1)*samplesPerBar)-1, samples.count-1))
            let mean = CGFloat(samples[lhs...rhs].reduce(0, +))/CGFloat(rhs-lhs+1)
            
            return pow(mean/maxHeight, 3)
        }
    }
    
}

//struct WaveformView_Previews: PreviewProvider {
//    static var previews: some View {
//        let half = Array(1...50)
//        let samples = half.reversed() + half
//        let waveform = Waveform(samples: samples)
//        WaveformView(with: waveform)
//            .frame(width: 400, height: 100)
//            .foregroundColor(.accentColor)
//    }
//}
