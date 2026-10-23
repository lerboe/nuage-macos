//
//  Helpers.swift
//  Nuage
//
//  Created by Laurin Brandner on 22.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import URLImage
import SoundCloud

private var durationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .positional
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.zeroFormattingBehavior = .pad
    
    return formatter
}()

func format<Time: BinaryFloatingPoint>(time: Time) -> String {
    return durationFormatter.string(from: TimeInterval(time)) ?? "00:00:00"
//    guard var text = durationFormatter.string(from: TimeInterval(time)) else {
//        return "00:00"
//    }
//    
//    let idx = text.index(text.startIndex, offsetBy: 3)
//    if text.prefix(upTo: idx) == "00:" {
//        text = String(text.suffix(from: idx))
//    }
//    
//    return text
}

private var countFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 1
    formatter.usesGroupingSeparator = false

    return formatter
}()

func format(count: Int) -> String {
    if count < 1_000 { return String(count) }

    let value = Double(count)
    let (scaled, suffix): (Double, String)
    switch value {
    case 1_000_000_000...: (scaled, suffix) = (value / 1_000_000_000, "B")
    case 1_000_000...:     (scaled, suffix) = (value / 1_000_000, "M")
    default:               (scaled, suffix) = (value / 1_000, "K")
    }

    return (countFormatter.string(from: NSNumber(value: scaled)) ?? String(count)) + suffix
}

extension AnyCancellable {
    
    func store<T: Hashable>(in dictionary: inout Dictionary<T, AnyCancellable>, key: T) {
        dictionary[key] = self
    }
    
}

protocol Filterable {
    
    func contains(_ text: String) -> Bool
    
}

extension User: Filterable {
    
    func contains(_ text: String) -> Bool {
        return username.containsCaseInsensitive(text) || name.containsCaseInsensitive(text)
    }
    
}

extension Track: Filterable {
    
    func contains(_ text: String) -> Bool {
        return title.containsCaseInsensitive(text) || (description?.containsCaseInsensitive(text) ?? false)
    }
    
}

extension Post: Filterable {
    
    func contains(_ text: String) -> Bool {
        return user.contains(text) || tracks.contains { $0.contains(text) }
    }
    
}

extension UserPlaylist: Filterable {
    
    func contains(_ text: String) -> Bool {
        let contained = title.containsCaseInsensitive(text) || (description?.containsCaseInsensitive(text) ?? false)
        if let tracks = tracks {
            return contained || tracks.contains { $0.contains(text) }
        }
        return contained
        
    }
}

extension SystemPlaylist: Filterable {
    
    func contains(_ text: String) -> Bool {
        let contained = title.containsCaseInsensitive(text) || (description?.containsCaseInsensitive(text) ?? false)
        if let tracks = tracks {
            return contained || tracks.contains { $0.contains(text) }
        }
        return contained
        
    }
}

extension Like: Filterable where T: Filterable {
    
    func contains(_ text: String) -> Bool {
        return item.contains(text)
    }
    
}

extension Some: Filterable {
    
    func contains(_ text: String) -> Bool {
        switch self {
        case .track(let track): return track.contains(text)
        case .userPlaylist(let playlist): return playlist.contains(text)
        case .systemPlaylist(let playlist): return playlist.contains(text)
        case .user(let user): return user.contains(text)
        }
    }
    
}

extension Comment: Filterable {
    
    func contains(_ text: String) -> Bool {
        return body.contains(text) || user.contains(text)
    }
    
}

extension HistoryItem: Filterable {
    
    func contains(_ text: String) -> Bool {
        return track.contains(text)
    }
    
}

extension Recommendation: Filterable {
    
    func contains(_ text: String) -> Bool {
        return user.contains(text)
    }
    
}

extension String {
    
    fileprivate func containsCaseInsensitive(_ text: String) -> Bool {
        return range(of: text, options: .caseInsensitive) != nil
    }
    
}

protocol DateComparable: Comparable {
    
    var date: Date { get }
    
}

extension DateComparable {
    
    public static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.date < rhs.date
    }
    
}

extension HistoryItem: DateComparable {}
extension Post: DateComparable {}
extension Track: DateComparable {}
extension UserPlaylist: DateComparable {}

@ViewBuilder func RemoteImage(url: URL?, cornerRadius: CGFloat) -> some View {
    let placeholder = Rectangle()
        .foregroundColor(Color(NSColor.underPageBackgroundColor))
        .cornerRadius(cornerRadius)
    
    if let url = url {
        URLImage(url: url,
                 empty: { placeholder },
                 inProgress: { _ in placeholder },
                 failure: { _, _ in placeholder },
                 content: { image in
            image.resizable()
                .cornerRadius(cornerRadius)
        })
        .id(url)
    }
    else {
        placeholder
    }
}

extension Color {
    
    init(hex: UInt, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 08) & 0xff) / 255
        let blue = Double((hex >> 00) & 0xff) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
    
}

extension View {
    
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
}

extension String {
    
    func withAttributedLinks(useAppURLScheme: Bool = true) -> AttributedString {
        var linkRanges = [(NSRange, URL)]()
        var handleRanges = [(NSRange, URL)]()
        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            detector.enumerateMatches(in: self, range: NSMakeRange(0, count)) { result, _, _ in
                if let match = result,
                    var url = match.url {
                    if url.absoluteString.contains("soundcloud") && useAppURLScheme {
                        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
                        components?.scheme = "nuage"
                        url = components?.url ?? url
                    }
                    linkRanges.append((match.range, url))
                }
            }
            
            let handle = /@([a-zA-Z0-9_-]{3,})/
            for match in self.matches(of: handle) {
                let range = NSRange(match.range, in: self)
                let username = match.output.1
                let scheme = useAppURLScheme ? "nuage" : "https"
                let url = URL(string: "\(scheme)://soundcloud.com/\(username)")!

                handleRanges.append((range, url))
            }
        }
        catch {
            print("Failed to parse text: \(error)")
        }
        
        let attributedText = NSMutableAttributedString(string: self)
        for (range, url) in (linkRanges + handleRanges)  {
            let attributes: [NSAttributedString.Key: Any] = [
                .link: url,
                .foregroundColor: NSColor.controlAccentColor,
            ]
            
            attributedText.addAttributes(attributes, range: range)
        }
        
        return AttributedString(attributedText)
    }

}

extension UserDefaults {

    /// Decodes a cached value, treating any failure as a cache miss.
    ///
    /// These caches are a launch-time convenience, the real content is
    /// refetched from the API. A stale or malformed entry left behind by an
    /// older build must not crash the app.
    func cachedValue<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }

        do {
            return try JSONDecoder().decode(type, from: data)
        }
        catch {
            print("Failed to decode cached \(type) for '\(key)', discarding: \(error)")
            removeObject(forKey: key)
            return nil
        }
    }

    func cache<T: Encodable>(_ value: T, forKey key: String) {
        do {
            set(try JSONEncoder().encode(value), forKey: key)
        }
        catch {
            print("Failed to encode \(T.self) for '\(key)': \(error)")
        }
    }

}
