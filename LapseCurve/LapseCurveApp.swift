//
//  LapseCurveApp.swift
//  LapseCurve
//
//  Created by Lars EBERHART on 14.10.26.
//

import SwiftUI
import AppKit

@main
struct LapseCurveApp: App {
    @State private var model = AppModel()

    init() {
        AppLogger.logLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1024, minHeight: 700)
                .task {
                    #if DEBUG
                    guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
                          ProcessInfo.processInfo.arguments.contains("-ui-testing-sequence") else { return }
                    do {
                        model.scanFolder(try makeUITestSequence())
                    } catch {
                        assertionFailure("Could not prepare UI test sequence: \(error)")
                    }
                    #endif
                }
        }
        .defaultSize(width: 1280, height: 820)
    }

        #if DEBUG
        private func makeUITestSequence() throws -> URL {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UITest-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                let image = NSImage(size: NSSize(width: 16, height: 16))
                image.lockFocus()
                NSColor.gray.setFill()
                NSRect(x: 0, y: 0, width: 16, height: 16).fill()
                image.unlockFocus()
                guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                            let jpeg = bitmap.representation(using: .jpeg, properties: [:]) else {
                        throw CocoaError(.fileWriteUnknown)
                }
                for index in 0...8 {
                        try jpeg.write(to: directory.appendingPathComponent("frame-\(index).jpg"))
                        let packet = """
                        <x:xmpmeta xmlns:x="adobe:ns:meta/">
                            <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                                <rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                                    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
                                    xmp:Rating="\([0, 4, 8].contains(index) ? 1 : 0)" crs:Exposure2012="\(index == 4 ? 4 : 0)"/>
                            </rdf:RDF>
                        </x:xmpmeta>
                        """
                        try Data(packet.utf8).write(to: directory.appendingPathComponent("frame-\(index).xmp"))
                }
                return directory
        }
        #endif
}
