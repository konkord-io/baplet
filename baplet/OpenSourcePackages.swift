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

    /// Identity for `ForEach` and the license sheet: the package name.
    var id: String { name }
}

extension OpenSourcePackage {
    /// Baplet itself: MIT licensed, with its source on GitHub. Shown in About's licence line;
    /// the text mirrors the repository's LICENSE file and must be kept in sync with it.
    static let baplet = OpenSourcePackage(
        name: "Baplet",
        license: "MIT",
        url: URL(string: "https://github.com/konkord-io/baplet")!,
        licenseText: """
        MIT License

        Copyright (c) 2026 Jakob Vad Nielsen

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    )

    /// Every third-party package Baplet ships with. Add an entry here whenever a dependency is
    /// added; the About tab's "Open Source" section is hidden while this list is empty.
    static let all: [OpenSourcePackage] = [
        OpenSourcePackage(
            name: "KeyboardShortcuts",
            license: "MIT",
            url: URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!,
            licenseText: """
            MIT License

            Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

            Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
            """
        ),
    ]
}
