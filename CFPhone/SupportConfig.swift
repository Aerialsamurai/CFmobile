import Foundation

/// Where "support the project" buttons point. Links set to nil are simply hidden in the app.
enum Support {
    static let repoURL = URL(string: "https://github.com/Aerialsamurai/cfmobile")!
    static let downloadURL = URL(string: "https://github.com/Aerialsamurai/cfmobile/releases/latest/download/CFMobile.ipa")!
    static let issuesURL = URL(string: "https://github.com/Aerialsamurai/cfmobile/issues")!

    // Fill these in to show the buttons, e.g. URL(string: "https://buymeacoffee.com/yourname").
    static let buyMeACoffee: URL? = nil
    static let koFi: URL? = nil
    static let githubSponsors: URL? = nil   // e.g. https://github.com/sponsors/Aerialsamurai (after enabling Sponsors)
}
