"""Small test double for the subset of essentia.standard used by the CLI."""

import os


def trace(event):
    path = os.environ.get("MOOD_PROBE_FAKE_TRACE")
    if path:
        with open(path, "a") as output:
            output.write(f"{event}\n")


class Prediction:
    def __init__(self, values, audio_path=None):
        self.values = values
        self.audio_path = audio_path

    def mean(self, axis):
        if axis != 0:
            raise ValueError("unexpected axis")
        return self.values


class MonoLoader:
    def __init__(self, filename, sampleRate, resampleQuality):
        self.filename = filename

    def __call__(self):
        if "bad" in self.filename:
            raise ValueError("decode failed")
        return [self.filename]


class TensorflowPredictMusiCNN:
    def __init__(self, graphFilename, output):
        if os.environ.get("FAKE_ESSENTIA_CONFIG_ERROR"):
            raise RuntimeError("fake model configuration failed")
        trace("TensorflowPredictMusiCNN.init")

    def __call__(self, audio):
        trace("TensorflowPredictMusiCNN.call")
        if "crash" in audio[0]:
            raise RuntimeError("unexpected inference crash")
        values = [0.25] * 200
        if "nan-vector" in audio[0]:
            values[17] = float("nan")
        elif "negative-infinity-vector" in audio[0]:
            values[17] = float("-inf")
        elif "infinity-vector" in audio[0]:
            values[17] = float("inf")
        return Prediction(values, audio_path=audio[0])


class TensorflowPredict2D:
    def __init__(self, graphFilename, output):
        self.graph_filename = graphFilename
        self.head = os.path.basename(graphFilename).split("-msd-musicnn")[0]
        trace(f"TensorflowPredict2D.init:{self.head}")

    def __call__(self, embeddings):
        trace(f"TensorflowPredict2D.call:{self.head}")
        audio_path = embeddings.audio_path
        if "danceability" in self.graph_filename:
            return Prediction([0.7, 0.3])
        if "mood_acoustic" in self.graph_filename:
            return Prediction([0.2, 0.8])
        if "mood_relaxed" in self.graph_filename:
            return Prediction([0.2, 0.8])
        if "mood_happy" in self.graph_filename:
            return Prediction([0.5, 0.5])
        if "emomusic" in self.graph_filename:
            if "nan" in audio_path:
                return Prediction([float("nan"), 5.8])
            if "infinity" in audio_path:
                return Prediction([4.2, float("inf")])
            return Prediction([4.2, 5.8])
        raise ValueError("unknown model")


class RhythmExtractor2013:
    def __init__(self, **params):
        self.params = params
        trace("RhythmExtractor2013.init")

    def __call__(self, audio):
        trace("RhythmExtractor2013.call")
        confidence = 0.9
        if "type-error-categorical" in audio[0]:
            confidence = {
                "label": "unstable",
                "distribution": {"unstable": object()},
            }
        elif "serialization-categorical" in audio[0]:
            confidence = {
                "label": "unstable",
                "distribution": {float("nan"): 0.5},
            }
        elif "categorical" in audio[0]:
            if "nan-categorical" in audio[0]:
                value = float("nan")
            elif "negative-infinity-categorical" in audio[0]:
                value = float("-inf")
            else:
                value = float("inf")
            confidence = {
                "label": "unstable",
                "distribution": {"unstable": value},
            }
        return (120.0, [0.5], confidence, [120.0], [0.5])
