import BackgroundAssets
import ExtensionFoundation
import StoreKit

/// StoreKit determines which Apple-hosted packs the customer is entitled to.
/// The app starts individual downloads or `Download all` explicitly, so the
/// extension declines unsolicited automatic downloads.
@main
struct LongWestAssetDownloader: StoreDownloaderExtension {
    func shouldDownload(_: AssetPack) -> Bool {
        false
    }
}
