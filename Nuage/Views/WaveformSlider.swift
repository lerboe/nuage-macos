//
//  WaveformSlider.swift
//  Nuage
//
//  Created by Laurin Brandner on 12.10.22.
//

import SwiftUI
import SoundCloud

struct WaveformSlider<Value : BinaryFloatingPoint, MinValueLabel: View, MaxValueLabel: View>: View {
    
    var url: URL?
    @Binding private var value: Value
    @State private var updatingValue: Value?
    
    @GestureState private var highlighted = false
    
    private var range: ClosedRange<Value>
    
    private var minValueLabel: (Value) -> MinValueLabel
    private var maxValueLabel: (Value) -> MaxValueLabel
    
    private var knobColor: Color?
    private var knobBorderColor: Color
    private var waveformForegroundColor: Color
    private var waveformBackgroundColor: Color
    
    var body: some View {
        HStack {
            minValueLabel(updatingValue ?? value)
            slider()
            maxValueLabel(updatingValue ?? value)
        }
    }
    
    @ViewBuilder private func slider() -> some View {
        let knobDiameter: CGFloat = 13
        
        GeometryReader { geometry in
            let currentValue = updatingValue ?? value
            let rangeWidth = range.upperBound - range.lowerBound
            let relativeValue = rangeWidth > 0 ? CGFloat((currentValue - range.lowerBound)/rangeWidth) : CGFloat(0)
            let barValue = geometry.size.width * relativeValue
            let knobValue = geometry.size.width * relativeValue - knobDiameter/2.0
            
            let drag = DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { gesture in
                guard geometry.size.width > 0 else { return }
                var newValue = Value(gesture.location.x/geometry.size.width) * rangeWidth + range.lowerBound
                newValue = min(max(newValue, range.lowerBound), range.upperBound)
                
                withAnimation(.linear(duration: 0.01)) {
                    updatingValue = newValue
                }
            }.onEnded { gesture in
                value = updatingValue ?? value
                updatingValue = nil
            }
            .updating($highlighted) { _, highlighted, _ in
                highlighted = true
            }
            
            HStack(alignment: .center) {
                ZStack(alignment: Alignment(horizontal: .leading, vertical: .center)) {
                    HStack(spacing: 0) {
                        Rectangle()
                            .foregroundColor(waveformForegroundColor)
                            .frame(width: barValue)
                        Rectangle()
                            .foregroundColor(waveformBackgroundColor)
                            .frame(width: max(0, geometry.size.width-barValue))
                    }
                    .mask(WaveformView(url: url))
                    
                    knob()
                        .frame(width: knobDiameter, height: knobDiameter)
                        .offset(x: knobValue)
                }
            }.gesture(drag)
        }
    }
    
    @ViewBuilder private func knob() -> some View {
        let knob = Circle()
            .strokeBorder(knobBorderColor, lineWidth: 1)

        if let knobColor = knobColor {
            knob.background(Circle().foregroundColor(knobColor))
        }
        else {
            knob.background(.ultraThinMaterial, in: Circle())
        }
    }
    
    init(url: URL?, value: Binding<Value>, in range: ClosedRange<Value>, @ViewBuilder minValueLabel: @escaping (Value) -> MinValueLabel, @ViewBuilder maxValueLabel: @escaping (Value) -> MaxValueLabel, knobColor: Color? = nil, knobBorderColor: Color? = nil, waveformForegroundColor: Color? = nil, waveformBackgroundColor: Color? = nil) {
        self.url = url
        self._value = value
        self.range = range
        self.minValueLabel = minValueLabel
        self.maxValueLabel = maxValueLabel
        
        self.knobColor = knobColor
        self.knobBorderColor = knobBorderColor ?? .primary.opacity(0.4)
        self.waveformForegroundColor = waveformForegroundColor ?? .primary
        self.waveformBackgroundColor = waveformBackgroundColor ?? .primary.opacity(0.2)
    }
    
}

//struct WaveformSlider_Previews: PreviewProvider {
//    static var previews: some View {
//        let half = Array(1...50)
//        let samples = half.reversed() + half
//        let waveform = Waveform(width: 100, height: 50, samples: samples)
//        WaveformSlider(waveform: waveform)
//            .frame(width: 400, height: 100)
//    }
//}
