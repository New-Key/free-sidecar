//
//  SystemInfoUtils.swift
//  free-sidecar
//
//  Created by Ben Zhang on 2020-04-16.
//  Copyright © 2020 Ben Zhang. All rights reserved.
//

import Foundation

struct SystemVersion: Decodable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let build: String?

    init() {
        let v = ProcessInfo().operatingSystemVersion
        major = v.majorVersion
        minor = v.minorVersion
        patch = v.patchVersion
        // https://twitter.com/ingeration/status/1076240776915574785
        build = NSDictionary(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist")?["ProductBuildVersion"] as? String
    }

    init(major: Int, minor: Int, patch: Int, build: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.build = build
    }

    var description: String {
        return "\(major).\(minor).\(patch) (Build \(build ?? "unknown"))"
    }
}

func getXcodeCLTPath() -> String? {
    let task = Process()
    let outputPipe = Pipe()

    task.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    task.arguments = ["--print-path"]
    task.standardOutput = outputPipe

    do {
        try task.run()
    } catch {
        // task launched unsuccessfully
        return nil
    }

    task.waitUntilExit()
    if task.terminationStatus != 0 {
        return nil
    }

    return readToEOF(pipe: outputPipe).trimmingCharacters(in: .whitespacesAndNewlines)
}

func makeGetPackageInfoTask(pkgId: String) -> (Process, Pipe, Pipe) {
    let task = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    task.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
    task.arguments = ["--pkg-info=" + pkgId]
    task.standardOutput = outputPipe
    task.standardError = errorPipe

    return (task, outputPipe, errorPipe)
}

func getXcodeCLTVersion() -> String? {
    let (xcTask, xcOut, xcErr) = makeGetPackageInfoTask(pkgId: "com.apple.pkg.Xcode")
    let (cltTask, cltOut, cltErr) = makeGetPackageInfoTask(pkgId: "com.apple.pkg.CLTools_Executables")

    do {
        try xcTask.run()
        try cltTask.run()
    } catch {
        return nil
    }

    xcTask.waitUntilExit()
    cltTask.waitUntilExit()

    let outPipe: Pipe

    switch (xcTask.terminationStatus, cltTask.terminationStatus) {
    case (0, _):
        outPipe = xcOut
    case (_, 0):
        outPipe = cltOut
    default:
        print("No Xcode CLT version info:")
        print(readToEOF(pipe: xcErr))
        print(readToEOF(pipe: cltErr))
        return nil
    }

    let output = readToEOF(pipe: outPipe)
    if let versionRange = output.range(of: #"version: (\d+\.)+(\d)+"#, options: .regularExpression) {
        let lowerBound = output.index(versionRange.lowerBound, offsetBy: "version: ".count)
        return String(output[lowerBound..<versionRange.upperBound])
    } else {
        return nil
    }
}

func isSIPDisabled() -> Bool? {
    let task = Process()
    let outputPipe = Pipe()

    task.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
    task.arguments = ["status"]
    task.standardOutput = outputPipe

    do {
        try task.run()
    } catch {
        // task launched unsuccessfully
        return nil
    }

    task.waitUntilExit()
    if task.terminationStatus != 0 {
        return nil
    }

    let output = readToEOF(pipe: outputPipe)
    if let range = output.range(of: #"enabled|disabled"#, options: .regularExpression) {
        return output[range.lowerBound..<range.upperBound] == "disabled"
    } else {
        return nil
    }
}

func hasAppleSignature(filePath: String) -> Bool? {
    let task = Process()
    let outputPipe = Pipe()

    task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    task.arguments = ["-dv", "--verbose=4", filePath]
    // codesign uses stderr for its output
    task.standardError = outputPipe

    do {
        try task.run()
    } catch {
        // task launched unsuccessfully
        return nil
    }

    task.waitUntilExit()
    if task.terminationStatus != 0 {
        return nil
    }

    let output = readToEOF(pipe: outputPipe)
    return output.contains("Authority=Software Signing")
        && output.contains("Authority=Apple Code Signing Certification Authority")
        && output.contains("Authority=Apple Root CA")
}
