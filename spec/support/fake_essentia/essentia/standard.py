"""Small test double for the subset of essentia.standard used by the CLI."""

import os


class Prediction:
    def __init__(self, values):
        self.values = values

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

    def __call__(self, audio):
        if "crash" in audio[0]:
            raise RuntimeError("unexpected inference crash")
        return [audio]


class TensorflowPredict2D:
    def __init__(self, graphFilename, output):
        self.graph_filename = graphFilename

    def __call__(self, embeddings):
        if "danceability" in self.graph_filename:
            return Prediction([0.7, 0.3])
        if "mood_acoustic" in self.graph_filename:
            return Prediction([0.2, 0.8])
        if "mood_relaxed" in self.graph_filename:
            return Prediction([0.2, 0.8])
        if "mood_happy" in self.graph_filename:
            return Prediction([0.5, 0.5])
        if "emomusic" in self.graph_filename:
            return Prediction([4.2, 5.8])
        raise ValueError("unknown model")
