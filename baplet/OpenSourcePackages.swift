//
//  OpenSourcePackages.swift
//  baplet
//

import Foundation

/// A third-party open-source package bundled with Baplet, credited in Settings → About.
struct OpenSourcePackage: Identifiable {
    let name: String
    let license: String
    let url: URL
    let licenseText: String

    var id: String { name }
}

extension OpenSourcePackage {
    /// Every third-party package Baplet ships with. Add an entry here whenever a dependency is
    /// added; the About tab's "Open Source" section is hidden while this list is empty.
    static let all: [OpenSourcePackage] = []
}
