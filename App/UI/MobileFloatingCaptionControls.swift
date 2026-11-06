#if os(iOS)
import SwiftUI

struct MobileFloatingCaptionControls: View {
    @Bindable var session: SessionController

    private var preparing: Bool { session.isPreparingPictureInPicture || session.pictureInPicture.isStarting }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if session.pictureInPicture.isActive { session.pictureInPicture.stop() }
                else { Task { await session.startFloatingCaptions() } }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: session.pictureInPicture.isActive ? "pip.exit" : "pip.enter")
                        .font(.title2)
                    Text(session.pictureInPicture.isActive ? "關閉浮動字幕" : preparing ? "正在準備浮動字幕…" : "開啟浮動字幕")
                        .font(.headline)
                    Spacer(minLength: 0)
                    if preparing { ProgressView().tint(.white) }
                }
                .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("captions.floating.toggle")
            .disabled(preparing || session.isBusy || !session.pictureInPicture.isSupported || (!session.pictureInPicture.isActive && (!session.media.isReady || !session.hasReadyModel)))

            Text("以子母畫面顯示本 App 播放的字幕，可切到其他 App 繼續觀看。無法讀取其他 App 的聲音。")
                .font(.callout).foregroundStyle(.secondary)
            if session.media.isReady {
                CaptionPictureInPicturePreview(controller: session.pictureInPicture)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("子母畫面字幕預覽")
                Text("浮動模式會使用 CPU 辨識，速度與耗電依裝置和模型而異；建議使用 Tiny 或 Base。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("先匯入本機音訊或影片，並選擇可用模型。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(session.pictureInPicture.status).font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif
