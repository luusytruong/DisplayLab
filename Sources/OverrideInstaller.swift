import Foundation

/// Manages macOS's own display override plist, which adds HiDPI "scale-resolutions":
/// /Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<hex>/DisplayProductID-<hex>
enum OverrideInstaller {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func url(vendor: UInt32, product: UInt32) -> URL {
        URL(fileURLWithPath: "/Library/Displays/Contents/Resources/Overrides")
            .appendingPathComponent(String(format: "DisplayVendorID-%x", vendor))
            .appendingPathComponent(String(format: "DisplayProductID-%x", product))
    }

    static func installedCount(vendor: UInt32, product: UInt32) -> Int? {
        (load(url(vendor: vendor, product: product))?["scale-resolutions"] as? [Data])?.count
    }

    /// Adds a 16-point HiDPI ladder (40%–100% of native width) to the plist, keeping existing entries.
    /// Returns how many entries were added (0 = already complete, nothing written).
    @discardableResult
    static func install(vendor: UInt32, product: UInt32, nativeWidth: Int, nativeHeight: Int) throws -> Int {
        guard nativeWidth > 0, nativeHeight > 0 else { throw Failure(errorDescription: L("Couldn't read the native resolution.")) }
        let dest = url(vendor: vendor, product: product)
        var dict = load(dest) ?? [:]
        dict["DisplayVendorID"] = vendor
        dict["DisplayProductID"] = product

        var entries = (dict["scale-resolutions"] as? [Data]) ?? []
        var seen = Set(entries)
        var added = 0
        var w = nativeWidth
        while w >= max(nativeWidth * 2 / 5, 640) {
            let h = Int((Double(w) * Double(nativeHeight) / Double(nativeWidth)).rounded())
            let entry = encode(w * 2, h * 2)
            if seen.insert(entry).inserted {
                entries.append(entry)
                added += 1
            }
            w -= 16
        }
        guard added > 0 else { return 0 }
        dict["scale-resolutions"] = entries

        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        // The Overrides folders are root-owned, so an atomic write (temp file + rename in that
        // folder) fails even when the plist itself is user-writable; overwrite in place instead.
        if FileManager.default.isWritableFile(atPath: dest.path), (try? data.write(to: dest)) != nil {
            return added
        }
        // Hand the bytes to root inline (base64 has no quote characters) rather than via a temp
        // file, so root never reads from a user-writable location that could be swapped for a symlink.
        // `dest` is built only from fixed path parts and the numeric vendor/product IDs.
        let shell = "mkdir -p '\(dest.deletingLastPathComponent().path)'"
            + " && printf %s '\(data.base64EncodedString())' | /usr/bin/base64 -D -o '\(dest.path)'"
            + " && chmod 644 '\(dest.path)'"
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(shell)\" with administrator privileges")?.executeAndReturnError(&error)
        if let error {
            let text = (error[NSAppleScript.errorMessage] as? String) ?? ""
            let cancelled = (error[NSAppleScript.errorNumber] as? Int) == -128
            throw Failure(errorDescription: cancelled ? L("The admin password prompt was cancelled.") : L("Couldn't write the override file. %@", text))
        }
        return added
    }

    private static func load(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private static func encode(_ w: Int, _ h: Int) -> Data {
        var be = (UInt32(w).bigEndian, UInt32(h).bigEndian)
        return Data(bytes: &be, count: 8)
    }
}
