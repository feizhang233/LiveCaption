import Foundation

/// Multilingual, unquantized ggml weights published by the whisper.cpp maintainer.
/// The file size is exact; RAM figures are conservative planning estimates, not measurements.
struct WhisperModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let fileBytes: Int64
    let estimatedMemoryBytes: UInt64
    let recommendedRAMBytes: UInt64
    let sha256: String

    static let sourceRevision = "5359861c739e955e79d9a303bcbc70fb988958b1"
    var fileName: String { "ggml-\(id).bin" }
    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/\(Self.sourceRevision)/\(fileName)")!
    }
    var formattedFileSize: String { ByteCountFormatter.string(fromByteCount: fileBytes, countStyle: .file) }
    var formattedMemoryEstimate: String {
        ByteCountFormatter.string(fromByteCount: Int64(estimatedMemoryBytes), countStyle: .memory)
    }
    var formattedRecommendedRAM: String {
        ByteCountFormatter.string(fromByteCount: Int64(recommendedRAMBytes), countStyle: .memory)
    }

    func recommendation(physicalMemory: UInt64) -> String {
        if physicalMemory < recommendedRAMBytes {
            return "建議至少 \(formattedRecommendedRAM) 裝置記憶體。請先試 tiny、base 或 small；系統仍可能因記憶體不足終止大型模型。"
        }
        switch id {
        case "tiny": return "最快、用量最低，適合先測試裝置。日語與法語可再比較 base 或 small。"
        case "base": return "建議從此模型開始；再依實際字幕速度與辨識結果決定是否升級。"
        case "small": return "較多辨識細節，所需記憶體與運算量也較高。"
        case "large-v3-turbo": return "大型模型的較快版本；仍需在裝置上驗證即時速度。"
        default: return "運算量較高。即時速度依裝置與音訊而異，並非下載完成就能即時運行。"
        }
    }

    static let catalog: [WhisperModel] = [
        .init(id: "tiny", name: "Tiny", fileBytes: 77_691_713, estimatedMemoryBytes: 400 * 1_048_576,
              recommendedRAMBytes: 4 * 1_073_741_824,
              sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"),
        .init(id: "base", name: "Base", fileBytes: 147_951_465, estimatedMemoryBytes: 550 * 1_048_576,
              recommendedRAMBytes: 4 * 1_073_741_824,
              sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"),
        .init(id: "small", name: "Small", fileBytes: 487_601_967, estimatedMemoryBytes: 1_200 * 1_048_576,
              recommendedRAMBytes: 6 * 1_073_741_824,
              sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"),
        .init(id: "medium", name: "Medium", fileBytes: 1_533_763_059, estimatedMemoryBytes: 3 * 1_073_741_824,
              recommendedRAMBytes: 8 * 1_073_741_824,
              sha256: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208"),
        .init(id: "large-v3-turbo", name: "Large v3 Turbo", fileBytes: 1_624_555_275,
              estimatedMemoryBytes: 3 * 1_073_741_824, recommendedRAMBytes: 8 * 1_073_741_824,
              sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"),
        .init(id: "large-v3", name: "Large v3", fileBytes: 3_095_033_483,
              estimatedMemoryBytes: 5 * 1_073_741_824, recommendedRAMBytes: 12 * 1_073_741_824,
              sha256: "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2")
    ]
}

enum ModelInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double)
    case verifying
    case installed
    case failed(String)

    var isInstalled: Bool { self == .installed }
    var isBusy: Bool {
        switch self {
        case .downloading, .verifying: true
        default: false
        }
    }
    var statusText: String {
        switch self {
        case .notInstalled: "未下載"
        case .downloading(let progress): "下載中 \(Int(progress * 100))%"
        case .verifying: "驗證 SHA-256…"
        case .installed: "已安裝並驗證"
        case .failed(let message): message
        }
    }
}

enum ModelStoreError: LocalizedError, Equatable {
    case notInstalled
    case busy
    case inUse
    case insufficientSpace(required: Int64, available: Int64)
    case spaceUnavailable
    case badResponse(Int)
    case wrongSize(expected: Int64, actual: Int64)
    case checksumMismatch
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .notInstalled: "模型尚未安裝並通過驗證。請先到模型管理下載。"
        case .busy: "另一個模型正在下載或驗證。請等待完成或取消下載後重試。"
        case .inUse: "模型正在使用。請先停止字幕並釋放模型，再切換或刪除。"
        case .insufficientSpace(let required, let available):
            "空間不足：需 \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file))（含暫存餘量），目前可用 \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))。請釋放空間或選擇較小模型。"
        case .spaceUnavailable: "無法確認可用儲存空間。請重新開啟 App 後重試。"
        case .badResponse(let code): "模型伺服器回傳 HTTP \(code)。請檢查網路後重試。"
        case .wrongSize: "下載的檔案大小不符，未將模型設為可用。請重新下載。"
        case .checksumMismatch: "模型完整性校驗失敗，未將模型設為可用。請重新下載。"
        case .invalidFile: "模型檔案無效或不在 App 儲存區中。請重新下載。"
        }
    }
}
