//
//  PlayerSlider.swift
//  Nuage
//
//  Created by Laurin Brandner on 01.02.21.
//

import SwiftUI

struct PlayerSlider<Value : BinaryFloatingPoint, MinValueLabel: View, MaxValueLabel: View>: View {
    
    enum UpdateStrategy {
        case continuous
        case incremental(Value)
        case onCommit
    }
    
    private enum ValueLabel<Content: View> {
        case constant(Content)
        case variable((Value) -> Content)
    }
    
    @Binding private var value: Value
    @State private var updatingValue: Value?
    @GestureState private var highlighted = false
    private var range: ClosedRange<Value>
    private var updateStrategy: UpdateStrategy
    
    private var minValueLabel: ValueLabel<MinValueLabel>
    private var maxValueLabel: ValueLabel<MaxValueLabel>
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            valueLabel(for: minValueLabel)
            slider()
            valueLabel(for: maxValueLabel)
        }
    }
    
    @ViewBuilder private func slider() -> some View {
        let knobRadius: CGFloat = 13
        
        GeometryReader { geometry in
            let currentValue = updatingValue ?? value
            let rangeWidth = range.upperBound - range.lowerBound
            let relativeValue = rangeWidth > 0 ? CGFloat((currentValue - range.lowerBound)/rangeWidth) : CGFloat(0)
            let barValue = geometry.size.width * relativeValue
            let knobValue = (geometry.size.width - knobRadius) * relativeValue
            let currentKnobColor = highlighted ? highlightedKnobColor : knobColor
            
            let drag = DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { gesture in
                guard geometry.size.width > 0 else { return }
                var newValue = Value(gesture.location.x/geometry.size.width) * rangeWidth + range.lowerBound
                newValue = min(max(newValue, range.lowerBound), range.upperBound)
                
                withAnimation(.linear(duration: 0.01)) {
                    switch updateStrategy {
                    case .continuous: value = newValue
                    case .incremental(let delta):
                        updatingValue = newValue
                        value = round(newValue/delta)*delta
                    case .onCommit: updatingValue = newValue
                    }
                }
            }.onEnded { gesture in
                // With the incremental strategy, `value` already holds the rounded value
                if case .onCommit = updateStrategy, let updatingValue = updatingValue {
                    value = updatingValue
                }
                updatingValue = nil
            }
            .updating($highlighted) { _, highlighted, _ in
                highlighted = true
            }
            
            ZStack(alignment: Alignment(horizontal: .leading, vertical: .center)) {
                HStack(spacing: 0) {
                    Rectangle()
                        .foregroundColor(barForegroundColor)
                        .frame(width: barValue)
                    Rectangle()
                        .foregroundColor(barBackgroundColor)
                        .frame(width: max(0, geometry.size.width-barValue))
                }
                .cornerRadius(1.5)
                .frame(height: 3)
                Circle()
                    .strokeBorder(knobBorderColor, lineWidth: 1)
                    .background(Circle().foregroundColor(currentKnobColor))
                    .frame(width: knobRadius, height: knobRadius)
                    .offset(x: knobValue)
            }
            .contentShape(Rectangle())
            .gesture(drag)
        }.frame(height: knobRadius)
    }
    
    private func valueLabel<Content>(for label: ValueLabel<Content>) -> Content {
        switch label {
        case .constant(let content): return content
        case .variable(let buildContent): return buildContent(updatingValue ?? value)
        }
    }
    
    private var knobColor: Color { colorScheme == .light ? .white : Color(hex: 0x1A1A1A) }
    
    private var highlightedKnobColor: Color { colorScheme == .light ? Color(hex: 0xE5E5E5) : Color(hex: 0x3E3E3E) }
    
    private var knobBorderColor: Color { colorScheme == .light ? Color(hex: 0xBFBFBF) : Color(hex: 0x5A5A5A) }
    
    private var barForegroundColor: Color { colorScheme == .light ? Color(hex: 0xBFBFBF) : Color(hex: 0x5F5F5F) }
    
    private var barBackgroundColor: Color { colorScheme == .light ? Color(hex: 0xF2F2F2) : Color(hex: 0x2C2C2C) }

    init(value: Binding<Value>, in range: ClosedRange<Value>, updateStrategy: UpdateStrategy = .continuous) where MinValueLabel == EmptyView, MaxValueLabel == EmptyView {
        self.init(value: value, in: range, updateStrategy: updateStrategy, minValueLabel: .constant(EmptyView()), maxValueLabel: .constant(EmptyView()))
    }
    
    init(value: Binding<Value>, in range: ClosedRange<Value>, updateStrategy: UpdateStrategy = .continuous, @ViewBuilder minValueLabel: () -> MinValueLabel, @ViewBuilder maxValueLabel: () -> MaxValueLabel) {
        self.init(value: value, in: range, updateStrategy: updateStrategy, minValueLabel: .constant(minValueLabel()), maxValueLabel: .constant(maxValueLabel()))
    }
    
    init(value: Binding<Value>, in range: ClosedRange<Value>, updateStrategy: UpdateStrategy = .continuous, @ViewBuilder minValueLabel: @escaping (Value) -> MinValueLabel, @ViewBuilder maxValueLabel: () -> MaxValueLabel) {
        self.init(value: value, in: range, updateStrategy: updateStrategy, minValueLabel: .variable(minValueLabel), maxValueLabel: .constant(maxValueLabel()))
    }
    
    private init(value: Binding<Value>, in range: ClosedRange<Value>, updateStrategy: UpdateStrategy, minValueLabel: ValueLabel<MinValueLabel>, maxValueLabel: ValueLabel<MaxValueLabel>) {
        self._value = value
        self.range = range
        self.updateStrategy = updateStrategy
        self.minValueLabel = minValueLabel
        self.maxValueLabel = maxValueLabel
        
        if case let .incremental(delta) = updateStrategy {
            assert(delta > 0, "The delta must be strictly larger than 0")
        }
    }
    
//    func minValueLabel<Content: View>(@ViewBuilder view: @escaping (Value) -> Content) -> PlayerSlider<Value, Content, MaxValueLabel> {
//        return PlayerSlider<Value, Content, MaxValueLabel>(value: $value, in: range, updateStrategy: updateStrategy, minValueLabel: .variable(view), maxValueLabel: maxValueLabel)
//    }

}

struct PlayerSlider_Previews: PreviewProvider {
    
    static var previews: some View {
        let value = Binding<Float>(get: { return 0.8 },
                                   set: { _ in })
        PlayerSlider(value: value, in: 0...1)
    }
    
}
