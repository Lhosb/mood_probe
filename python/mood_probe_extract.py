#!/usr/bin/env python3
"""Extract Essentia mood features as newline-delimited JSON."""

import argparse
import json
import sys
from pathlib import Path

_EMBEDDING_MODEL_FILENAME = "msd-musicnn-1.pb"
_EMBEDDING_OUTPUT_NODE = "model/dense/BiasAdd"
_HEAD_MODELS = {
    "danceability": ("danceability-msd-musicnn-1.pb", 0),
    "mood_acoustic": ("mood_acoustic-msd-musicnn-1.pb", 0),
    "mood_relaxed": ("mood_relaxed-msd-musicnn-1.pb", 1),
    "mood_happy": ("mood_happy-msd-musicnn-1.pb", 0),
}
_HEAD_OUTPUT_NODE = "model/Softmax"
_VALENCE_AROUSAL_MODEL_FILENAME = "emomusic-msd-musicnn-2.pb"
_VALENCE_AROUSAL_OUTPUT_NODE = "model/Identity"


def load_models(models_dir: Path):
    import essentia.standard as es

    embedding = es.TensorflowPredictMusiCNN(
        graphFilename=str(models_dir / _EMBEDDING_MODEL_FILENAME),
        output=_EMBEDDING_OUTPUT_NODE,
    )
    heads = {
        key: (
            es.TensorflowPredict2D(
                graphFilename=str(models_dir / filename), output=_HEAD_OUTPUT_NODE
            ),
            positive_index,
        )
        for key, (filename, positive_index) in _HEAD_MODELS.items()
    }
    valence_arousal = es.TensorflowPredict2D(
        graphFilename=str(models_dir / _VALENCE_AROUSAL_MODEL_FILENAME),
        output=_VALENCE_AROUSAL_OUTPUT_NODE,
    )
    return es, embedding, heads, valence_arousal


def load_audio(audio_path: Path, essentia_standard):
    return essentia_standard.MonoLoader(
        filename=str(audio_path), sampleRate=16000, resampleQuality=4
    )()


def analyze(audio, loaded_models) -> dict:
    es, embedding_model, head_models, valence_arousal_model = loaded_models
    embeddings = embedding_model(audio)

    result: dict = {}
    for key, (model, positive_index) in head_models.items():
        predictions = model(embeddings)
        result[key] = float(predictions.mean(axis=0)[positive_index])

    va_predictions = valence_arousal_model(embeddings)
    va_mean = va_predictions.mean(axis=0)
    result["valence"] = float((va_mean[0] - 1.0) / 8.0)
    result["arousal"] = float((va_mean[1] - 1.0) / 8.0)
    return result


def emit(payload: dict) -> None:
    print(json.dumps(payload), flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("audio_paths", nargs="*")
    parser.add_argument("--models-dir", required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()

    if not args.verify and not args.audio_paths:
        parser.error("at least one audio path is required")

    try:
        loaded_models = load_models(Path(args.models_dir))
    except Exception as exc:
        print(f"mood_probe configuration failed: {exc}", file=sys.stderr)
        return 2

    if args.verify:
        return 0

    try:
        for raw_path in args.audio_paths:
            try:
                audio = load_audio(Path(raw_path), loaded_models[0])
            except Exception as exc:
                emit(
                    {
                        "path": raw_path,
                        "error": {
                            "type": "unreadable_audio",
                            "message": str(exc),
                        },
                    }
                )
                continue

            features = analyze(audio, loaded_models)
            emit({"path": raw_path, "features": features})
    except Exception as exc:
        print(f"mood_probe backend crashed: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
