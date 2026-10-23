//
//  Helpers.swift
//  Nuage
//
//  Created by Laurin Brandner on 22.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import Foundation
import SwiftUI
import URLImage
import SoundCloud

private let durationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .positional
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.zeroFormattingBehavior = .pad
    
    return formatter
}()

func format<Time: BinaryFloatingPoint>(time: Time) -> String {
    return durationFormatter.string(from: TimeInterval(time)) ?? "00:00:00"
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
        return body.containsCaseInsensitive(text) || user.contains(text)
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

extension HistoryItem: @retroactive Comparable, DateComparable {}
extension Post: @retroactive Comparable, DateComparable {}
extension Track: @retroactive Comparable, DateComparable {}
extension UserPlaylist: @retroactive Comparable, DateComparable {}

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

private let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

extension String {
    
    func withAttributedLinks(useAppURLScheme: Bool = true) -> AttributedString {
        var linkRanges = [(NSRange, URL)]()
        var handleRanges = [(NSRange, URL)]()
        if let detector = linkDetector {
            // NSRange is based on UTF-16 code units, not on Characters
            detector.enumerateMatches(in: self, range: NSRange(location: 0, length: utf16.count)) { result, _, _ in
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
        }
        
        let handle = /@([a-zA-Z0-9_-]{3,})/
        for match in self.matches(of: handle) {
            let range = NSRange(match.range, in: self)
            
            // Skip handles that are part of a link or an email address
            let previousCharacter = match.range.lowerBound > startIndex ? self[index(before: match.range.lowerBound)] : nil
            let isPartOfWord = previousCharacter.map { $0.isLetter || $0.isNumber } ?? false
            if isPartOfWord || linkRanges.contains(where: { NSIntersectionRange($0.0, range).length > 0 }) {
                continue
            }
            
            let username = match.output.1
            let scheme = useAppURLScheme ? "nuage" : "https"
            if let url = URL(string: "\(scheme)://soundcloud.com/\(username)") {
                handleRanges.append((range, url))
            }
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

    /// Encodes and stores a value. The type is explicit so that a write can't
    /// silently disagree with the type `cachedValue` reads back.
    func cache<T: Encodable>(_ value: T, as type: T.Type, forKey key: String) {
        do {
            set(try JSONEncoder().encode(value), forKey: key)
        }
        catch {
            print("Failed to encode \(type) for '\(key)', discarding: \(error)")
            removeObject(forKey: key)
        }
    }

}
