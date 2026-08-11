#!/usr/bin/env python3
"""Extract Essentia mood features as newline-delimited JSON."""

import argparse
import json
import math
import re
import sys
from pathlib import Path

_SCHEMA_VERSION = 1
_MODEL_FILENAME = re.compile(r"^[A-Za-z0-9._-]+\.pb$")
_GRAPH_ALGORITHMS = {
    "TensorflowPredictMusiCNN",
    "TensorflowPredict2D",
}
_ALGORITHM_PARAMS = {
    "RhythmExtractor2013": {
        "method": str,
        "minTempo": (int, float),
        "maxTempo": (int, float),
    }
}


class PlanValidationError(ValueError):
    pass


def capabilities() -> dict:
    return {
        "schema_version": _SCHEMA_VERSION,
        "algorithms": sorted(_GRAPH_ALGORITHMS | _ALGORITHM_PARAMS.keys()),
    }


def validate_plan(plan: dict, models_dir: Path) -> dict:
    if not isinstance(plan, dict):
        raise PlanValidationError("plan must be an object")
    required_keys = {
        "schema_version",
        "loads",
        "graphs",
        "algorithms",
        "emit",
        "required_files",
    }
    missing_keys = required_keys - plan.keys()
    if missing_keys:
        missing = sorted(missing_keys)[0]
        raise PlanValidationError(f"plan.{missing} is required")
    extra_keys = plan.keys() - required_keys
    if extra_keys:
        extra = sorted(extra_keys)[0]
        raise PlanValidationError(f"plan.{extra} is not allowed")

    version = plan.get("schema_version")
    if (
        not isinstance(version, int)
        or isinstance(version, bool)
        or version != _SCHEMA_VERSION
    ):
        raise PlanValidationError(
            f"schema_version {version!r} is unsupported; expected {_SCHEMA_VERSION}"
        )

    root = models_dir.resolve()
    loads = require_list(plan["loads"], "plan.loads")
    load_rates = set()
    for index, load in enumerate(loads):
        location = f"loads[{index}]"
        require_keys(load, {"sample_rate"}, location)
        load_rates.add(require_positive_int(load["sample_rate"], f"{location}.sample_rate"))

    graphs = require_list(plan["graphs"], "plan.graphs")
    graph_refs = set()
    graph_files = []
    graph_rates = set()
    for index, graph in enumerate(graphs):
        location = f"graphs[{index}]"
        require_keys(
            graph,
            {"ref", "file", "algorithm", "output", "input"},
            location,
            optional={"sample_rate"},
        )
        ref = require_string(graph["ref"], f"{location}.ref")
        if ref in graph_refs:
            raise PlanValidationError(f"{location}.ref must be unique")
        algorithm = graph.get("algorithm")
        if algorithm not in _GRAPH_ALGORITHMS:
            raise PlanValidationError(f"{location}.algorithm is not allowed: {algorithm!r}")
        if graph.get("params"):
            raise PlanValidationError(f"{location}.params are not allowed")
        filename = graph.get("file")
        validate_model_path(filename, root, f"{location}.file")
        graph_files.append(filename)
        require_string(graph["output"], f"{location}.output")
        input_spec = require_dict(graph["input"], f"{location}.input")
        if set(input_spec) == {"audio"}:
            sample_rate = require_positive_int(
                input_spec["audio"], f"{location}.input.audio"
            )
            if graph.get("sample_rate") != sample_rate:
                raise PlanValidationError(
                    f"{location}.sample_rate must match {location}.input.audio"
                )
            graph_rates.add(sample_rate)
        elif set(input_spec) == {"graph"}:
            source_ref = require_string(input_spec["graph"], f"{location}.input.graph")
            if source_ref not in graph_refs:
                raise PlanValidationError(
                    f"{location}.input.graph must reference an earlier graph"
                )
        else:
            raise PlanValidationError(
                f"{location}.input must contain exactly one of audio or graph"
            )
        graph_refs.add(ref)

    algorithms = require_list(plan["algorithms"], "plan.algorithms")
    algorithm_refs = set()
    algorithm_rates = set()
    for index, algorithm in enumerate(algorithms):
        location = f"algorithms[{index}]"
        require_keys(
            algorithm,
            {"ref", "name", "params", "sample_rate"},
            location,
        )
        ref = require_string(algorithm["ref"], f"{location}.ref")
        require_unique_ref(ref, graph_refs | algorithm_refs, location)
        algorithm_refs.add(ref)
        name = algorithm.get("name")
        if name not in _ALGORITHM_PARAMS:
            raise PlanValidationError(f"{location}.name is not allowed: {name!r}")
        validate_params(algorithm.get("params", {}), _ALGORITHM_PARAMS[name], location)
        algorithm_rates.add(
            require_positive_int(algorithm["sample_rate"], f"{location}.sample_rate")
        )

    expected_rates = graph_rates | algorithm_rates
    if load_rates != expected_rates:
        raise PlanValidationError(
            f"plan.loads sample rates {sorted(load_rates)} do not match required rates "
            f"{sorted(expected_rates)}"
        )

    emits = require_list(plan["emit"], "plan.emit")
    known_refs = graph_refs | algorithm_refs
    for index, emit_spec in enumerate(emits):
        location = f"emit[{index}]"
        require_keys(
            emit_spec,
            {"id", "kind", "from", "take"},
            location,
            optional={"reduce"},
        )
        require_string(emit_spec["id"], f"{location}.id")
        require_string(emit_spec["kind"], f"{location}.kind")
        source_ref = require_string(emit_spec["from"], f"{location}.from")
        if source_ref not in known_refs:
            raise PlanValidationError(f"{location}.from references an unknown source")
        take = emit_spec["take"]
        if take is None:
            if source_ref not in graph_refs:
                raise PlanValidationError(
                    f"{location}.take is required for algorithm output"
                )
        elif not isinstance(take, dict):
            raise PlanValidationError(f"{location}.take must be an object or null")
        elif set(take) == {"index"}:
            if source_ref not in graph_refs:
                raise PlanValidationError(
                    f"{location}.take.index is only allowed for graph output"
                )
            if (
                not isinstance(take["index"], int)
                or isinstance(take["index"], bool)
                or take["index"] < 0
            ):
                raise PlanValidationError(
                    f"{location}.take.index must be a non-negative integer"
                )
        elif set(take) == {"output"}:
            if source_ref in graph_refs:
                raise PlanValidationError(
                    f"{location}.take.output is only allowed for algorithm output"
                )
            require_string(take["output"], f"{location}.take.output")
        else:
            raise PlanValidationError(
                f"{location}.take must contain exactly one of index or output"
            )
        if source_ref in graph_refs:
            if emit_spec.get("reduce") != "mean_over_frames":
                raise PlanValidationError(
                    f"{location}.reduce must be mean_over_frames for graph output"
                )
        elif "reduce" in emit_spec:
            raise PlanValidationError(f"{location}.reduce is not allowed for algorithm output")

    required_files = require_list(plan["required_files"], "plan.required_files")
    if not all(isinstance(filename, str) for filename in required_files):
        raise PlanValidationError("plan.required_files must contain only strings")
    if required_files != graph_files:
        raise PlanValidationError("plan.required_files must match graph files in order")

    return plan


def require_dict(value, location: str) -> dict:
    if not isinstance(value, dict):
        raise PlanValidationError(f"{location} must be an object")
    return value


def require_list(value, location: str) -> list:
    if not isinstance(value, list):
        raise PlanValidationError(f"{location} must be an array")
    return value


def require_keys(value, required: set, location: str, optional: set = frozenset()) -> None:
    require_dict(value, location)
    missing = required - value.keys()
    if missing:
        raise PlanValidationError(f"{location}.{sorted(missing)[0]} is required")
    extra = value.keys() - required - optional
    if extra:
        raise PlanValidationError(f"{location}.{sorted(extra)[0]} is not allowed")


def require_string(value, location: str) -> str:
    if not isinstance(value, str) or not value:
        raise PlanValidationError(f"{location} must be a non-empty string")
    return value


def require_positive_int(value, location: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise PlanValidationError(f"{location} must be a positive integer")
    return value


def require_unique_ref(ref: str, refs: set, location: str) -> None:
    if ref in refs:
        raise PlanValidationError(f"{location}.ref must be unique")
    refs.add(ref)


def validate_model_path(filename, root: Path, location: str) -> None:
    if (
        not isinstance(filename, str)
        or not _MODEL_FILENAME.fullmatch(filename)
        or ".." in filename
    ):
        raise PlanValidationError(f"{location} must be a bare .pb basename")

    path = root / filename
    if path.is_symlink():
        raise PlanValidationError(f"{location} must identify a regular non-symlink file")
    try:
        canonical = path.resolve(strict=True)
        canonical.relative_to(root)
    except (FileNotFoundError, ValueError):
        raise PlanValidationError(f"{location} must resolve inside the models directory")
    if not canonical.is_file():
        raise PlanValidationError(f"{location} must identify a regular non-symlink file")


def validate_params(params, allowed: dict, location: str) -> None:
    if not isinstance(params, dict):
        raise PlanValidationError(f"{location}.params must be an object")

    for key, value in params.items():
        parameter_location = f"{location}.params.{key}"
        expected = allowed.get(key)
        if expected is None:
            raise PlanValidationError(f"{parameter_location} is not allowed")
        if isinstance(value, bool) or not isinstance(value, expected):
            raise PlanValidationError(f"{parameter_location} has the wrong type")


def load_plan(plan_json, plan_file, models_dir: Path):
    if bool(plan_json) == bool(plan_file):
        raise PlanValidationError("exactly one of --plan-json or --plan-file is required")
    payload = plan_json if plan_json else Path(plan_file).read_text()
    return validate_plan(json.loads(payload), models_dir)


# Canonicalise/check/open for hostile wire-data paths is defence in depth, not Ruby-to-Python inode
# binding; check-then-open is TOCTOU. See https://github.com/Lhosb/mood_probe/issues/2.
def build_pipeline(plan: dict, models_dir: Path):
    import essentia.standard as es

    graphs = {}
    for graph in plan["graphs"]:
        filename = str(models_dir / graph["file"])
        if graph["algorithm"] == "TensorflowPredictMusiCNN":
            instance = es.TensorflowPredictMusiCNN(
                graphFilename=filename, output=graph["output"]
            )
        elif graph["algorithm"] == "TensorflowPredict2D":
            instance = es.TensorflowPredict2D(
                graphFilename=filename, output=graph["output"]
            )
        else:
            raise PlanValidationError(
                f"graph algorithm is not allowed: {graph['algorithm']!r}"
            )
        graphs[graph["ref"]] = instance

    algorithms = {}
    for algorithm in plan["algorithms"]:
        if algorithm["name"] == "RhythmExtractor2013":
            instance = es.RhythmExtractor2013(**algorithm["params"])
        else:
            raise PlanValidationError(
                f"algorithm is not allowed: {algorithm['name']!r}"
            )
        algorithms[algorithm["ref"]] = instance

    return es, graphs, algorithms


def load_plan_audio(audio_path: Path, plan: dict, essentia_standard) -> dict:
    return {
        load["sample_rate"]: essentia_standard.MonoLoader(
            filename=str(audio_path),
            sampleRate=load["sample_rate"],
            resampleQuality=4,
        )()
        for load in plan["loads"]
    }


def execute_plan(audio: dict, plan: dict, pipeline) -> dict:
    _es, graph_instances, algorithm_instances = pipeline
    graph_outputs = {}
    for graph in plan["graphs"]:
        input_spec = graph["input"]
        source = (
            audio[input_spec["audio"]]
            if "audio" in input_spec
            else graph_outputs[input_spec["graph"]]
        )
        graph_outputs[graph["ref"]] = graph_instances[graph["ref"]](source)

    algorithm_outputs = {}
    for algorithm in plan["algorithms"]:
        output = algorithm_instances[algorithm["ref"]](
            audio[algorithm["sample_rate"]]
        )
        if algorithm["name"] == "RhythmExtractor2013":
            algorithm_outputs[algorithm["ref"]] = {
                "bpm": output[0],
                "confidence": output[2],
            }

    values = {}
    for emit_spec in plan["emit"]:
        source_ref = emit_spec["from"]
        if source_ref in graph_outputs:
            value = graph_outputs[source_ref]
            if emit_spec.get("reduce") == "mean_over_frames":
                value = value.mean(axis=0)
            take = emit_spec["take"]
            if take:
                value = value[take["index"]]
        else:
            value = algorithm_outputs[source_ref][emit_spec["take"]["output"]]
        values[emit_spec["id"]] = json_value(value)
    return values


def json_value(value):
    if hasattr(value, "tolist"):
        return value.tolist()
    if hasattr(value, "item"):
        return value.item()
    if isinstance(value, (list, tuple)):
        return [json_value(item) for item in value]
    if isinstance(value, dict):
        return {key: json_value(item) for key, item in value.items()}
    return value


def find_non_finite(value, path: str):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        if math.isfinite(value):
            return None
        if math.isnan(value):
            return path, "NaN"
        return path, "Infinity" if value > 0 else "-Infinity"
    if isinstance(value, list):
        for index, item in enumerate(value):
            found = find_non_finite(item, f"{path}[{index}]")
            if found:
                return found
    if isinstance(value, dict):
        for key, item in value.items():
            found = find_non_finite(key, f"{path}.<key>")
            if found:
                return found
            found = find_non_finite(item, f"{path}.{key}")
            if found:
                return found
    return None


def emit(payload: dict) -> None:
    print(json.dumps(payload, allow_nan=False), flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("audio_paths", nargs="*")
    parser.add_argument("--models-dir")
    parser.add_argument("--plan-json")
    parser.add_argument("--plan-file")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--capabilities", action="store_true")
    args = parser.parse_args()

    if args.capabilities:
        emit(capabilities())
        return 0
    if not args.models_dir:
        parser.error("--models-dir is required")
    if not args.verify and not args.audio_paths:
        parser.error("at least one audio path is required")

    try:
        plan = load_plan(
            args.plan_json,
            args.plan_file,
            Path(args.models_dir),
        )
    except (OSError, json.JSONDecodeError, PlanValidationError) as exc:
        print(f"mood_probe plan invalid: {exc}", file=sys.stderr)
        return 2

    try:
        loaded_models = build_pipeline(plan, Path(args.models_dir))
    except Exception as exc:
        print(f"mood_probe configuration failed: {exc}", file=sys.stderr)
        return 2

    if args.verify:
        return 0

    try:
        for raw_path in args.audio_paths:
            try:
                audio = load_plan_audio(Path(raw_path), plan, loaded_models[0])
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

            try:
                features = execute_plan(audio, plan, loaded_models)
                non_finite = find_non_finite(features, "")
                if non_finite:
                    location, value_name = non_finite
                    emit(
                        {
                            "path": raw_path,
                            "error": {
                                "type": "malformed_output",
                                "message": f"non-finite descriptor value: "
                                f"{location.lstrip('.')} is {value_name}",
                            },
                        }
                    )
                    continue
            except Exception as exc:
                emit(
                    {
                        "path": raw_path,
                        "error": {
                            "type": "inference_error",
                            "message": str(exc),
                        },
                    }
                )
                continue

            try:
                emit({"path": raw_path, "features": features})
            except (TypeError, ValueError) as exc:
                emit(
                    {
                        "path": raw_path,
                        "error": {
                            "type": "malformed_output",
                            "message": f"descriptor serialization failed: {exc}",
                        },
                    }
                )
    except Exception as exc:
        print(f"mood_probe backend crashed: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
