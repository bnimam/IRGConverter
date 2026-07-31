/// The shipped version, in one place.
///
/// `build_app.sh` reads the string out of this file with `sed` to stamp the app
/// bundle's `Info.plist` and to name the release archive, and `irgconvert
/// --version` prints it. Bumping it here is the whole job.
public enum IRGConverterVersion {
    public static let current = "1.0.0"
}
