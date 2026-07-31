/// The shipped version, in one place.
///
/// `build_app.sh` reads the string out of this file with `sed` to stamp the app
/// bundle's `Info.plist`, and `irgconvert --version` prints it. The release archive is
/// deliberately not versioned, so the README's download link never goes stale.
/// Bumping it here is the whole job.
public enum IRGConverterVersion {
    public static let current = "1.1.0"
}
