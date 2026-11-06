# Human speech test fixtures

The eight test clips are human recordings from Google FLEURS (`ja_jp`, `fr_fr`, `en_us`, `cmn_hans_cn`, test split), distributed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution: **Google FLEURS contributors**; dataset paper [FLEURS: Few-shot Learning Evaluation of Universal Representations of Speech](https://arxiv.org/abs/2205.12446), and [dataset card at the fixture revision](https://huggingface.co/datasets/google/fleurs/blob/d7c758a6dceecd54a98cac43404d3d576e721f07/README.md).

`manifest.json` retains the exact source archive revision, source clip name, reference transcription, duration and SHA-256. The clips are fetched unchanged; the media regression harness also creates a temporary 48 kHz stereo conversion for resampling tests. No audio or model weights are committed to the project.

The current dataset viewer returned `Scan size limit exceeded` for the Japanese/French Parquet groups on 2026-11-06. The fixtures were therefore read from the official pre-Parquet repository revision `d7c758a6dceecd54a98cac43404d3d576e721f07`. The download helper streams only enough of each archive to obtain these clips and verifies the committed checksums.

English and Mandarin were added from the same immutable revision. For each of their archives, the first two encountered distinct reference texts with a duration of 4–12 seconds were selected **before inference**, with no selection based on model accuracy. Actual WAV sample rate (16 kHz), mono channel count, decoded duration, source metadata, and SHA-256 were checked. The Mandarin configuration is `cmn_hans_cn` (Mainland Mandarin, simplified reference text); this does not validate Cantonese, other Chinese varieties, or consistent simplified/traditional output.

| Fixture | Duration | Source language |
|---|---:|---|
| ja_jp-0 / ja_jp-1 | 10.44 / 14.22 s | Japanese |
| fr_fr-0 / fr_fr-1 | 10.20 / 8.28 s | French |
| en_us-0 / en_us-1 | 10.56 / 8.76 s | US English |
| cmn_hans_cn-0 / cmn_hans_cn-1 | 10.38 / 8.28 s | Mandarin Chinese |

Optional developer setup: `python3 Scripts/fetch-test-audio.py`. This uses Python's standard library and system curl for test-data acquisition only. Neither the App, its inference engine, nor its Xcode build requires Python. The default output is `/tmp/live-caption-verification-audio`; an alternate destination can be supplied as a positional argument. Existing clips are reused only after SHA-256 verification; missing or corrupted selected clips are fetched and verified before replacing their final path.

To fetch only the new languages, use `python3 Scripts/fetch-test-audio.py --language en_us --language cmn_hans_cn`. The option is repeatable; unknown languages are rejected. `fixtures.json` in the output directory retains the complete catalog, with paths adjusted for that directory; unselected clips may not have been downloaded.

These eight clean, short read-speech recordings provide a reproducible functional smoke test, not a measurement of film/anime/lecture accuracy, long-run stability, or iPad performance. Reference text is test data only and is never used to populate App captions. `Scripts/score-fixtures.swift` uses character error rate for Japanese/Chinese and word error rate for English/French; it accepts the same repeatable `--language` filter for result subsets. Missing selected results remain errors. The primary Chinese CER does not convert traditional/simplified characters; a separately named `simplifiedScriptDiagnostic` reports CER after applying Foundation's ICU Traditional-Simplified transform to both texts. Actual captions and the primary score are unchanged. Numeral words are not normalized to digits.

`bash Scripts/make-video-fixture.sh` creates `/tmp/live-caption-verification-audio/fr-native-video.mp4` from the real `fr_fr-0.wav` speech. It uses public AVFoundation/CoreVideo APIs to add a neutral solid 640×360 H.264 video track, then exports the original spoken content as AAC. No subtitles or other text are rendered into the video. This allows native video-player and media-time tests without substituting a fabricated transcript. Provenance and the verification artifact's hash are in `derived-video.json`; generated MP4 bytes may differ with encoder/runtime versions. The generator is development-only Swift and requires no ffmpeg or Python.
