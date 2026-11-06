import CaptionCore
import SwiftUI
import UniformTypeIdentifiers

struct CaptionExport {
    enum Format {
        case srt, text, alternativeText

        var contentType: UTType { self == .srt ? CaptionDocument.subRipType : .plainText }
        var filename: String {
            switch self {
            case .srt: "Live Caption.srt"
            case .text: "Live Caption.txt"
            case .alternativeText: "Live Caption - 其他辨識結果.txt"
            }
        }
    }

    let document: CaptionDocument
    let format: Format
    var contentType: UTType { format.contentType }
    var filename: String { format.filename }

    init(captions: [CaptionSegment], format: Format) {
        self.format = format
        document = CaptionDocument(text: format == .srt ? CaptionExporter.srt(captions) : CaptionExporter.txt(captions))
    }
}

struct CaptionDocument: FileDocument {
    /// A filename-tagged text type preserves .srt on macOS and iOS save panels.
    static let subRipType = UTType(filenameExtension: "srt", conformingTo: .plainText)!
    static var readableContentTypes: [UTType] { [.plainText, subRipType] }
    static var writableContentTypes: [UTType] { [.plainText, subRipType] }

    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
