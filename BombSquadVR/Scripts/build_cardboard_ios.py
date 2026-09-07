#!/usr/bin/env python3
"""Build the iOS Cardboard static libraries without nesting xcodebuild.

The Cardboard repository ships an Xcode project and a CocoaPods workspace,
but starting xcodebuild from an Xcode run-script phase can crash
SWBBuildService.  This small builder performs the same source compilation and
static-archive steps directly with the Apple toolchain instead.
"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
CARDBOARD = ROOT / "ThirdParty" / "cardboard"
SDK_ROOT = CARDBOARD / "sdk"
PROTO_ROOT = CARDBOARD / "proto"
PODS_ROOT = CARDBOARD / "Pods"
PROTOBUF_SOURCE_ROOT = PODS_ROOT / "Protobuf-C++" / "src"
OUTPUT_ROOT = ROOT / "Build" / "Cardboard"
OBJECT_ROOT = ROOT / "Build" / "CardboardObjects"


# This is the iOS source set from Cardboard's sdk target.  Android-only and
# Vulkan sources are intentionally left out.
CARDBOARD_SOURCES = (
    "sdk/rendering/opengl_es3_distortion_renderer.cc",
    "sdk/polynomial_radial_distortion.cc",
    "sdk/distortion_mesh.cc",
    "sdk/sensors/lowpass_filter.cc",
    "sdk/sensors/neck_model.cc",
    "sdk/sensors/ios/sensor_event_producer.mm",
    "sdk/util/is_initialized.cc",
    "sdk/sensors/mean_filter.cc",
    "sdk/sensors/gyroscope_bias_estimator.cc",
    "sdk/screen_params/ios/screen_params.mm",
    "sdk/sensors/ios/device_gyroscope_sensor.mm",
    "sdk/unity/xr_unity_plugin/cardboard_input_api.cc",
    "sdk/util/matrixutils.cc",
    "sdk/screen_params/ios/sdk_bundle_finder.mm",
    "proto/cardboard_device.pb.cc",
    "sdk/sensors/median_filter.cc",
    "sdk/head_tracker.cc",
    "sdk/util/matrix_4x4.cc",
    "sdk/sensors/ios/device_accelerometer_sensor.mm",
    "sdk/qrcode/ios/qr_scan_view_controller.mm",
    "sdk/cardboard.cc",
    "sdk/unity/xr_unity_plugin/metal_renderer.mm",
    "sdk/unity/xr_provider/input.cc",
    "sdk/unity/xr_provider/display.cc",
    "sdk/rendering/ios/metal_distortion_renderer.mm",
    "sdk/unity/xr_provider/math_tools.cc",
    "sdk/qrcode/ios/device_params_helper.mm",
    "sdk/rendering/opengl_es2_distortion_renderer.cc",
    "sdk/util/vectorutils.cc",
    "sdk/qrcode/cardboard_v1/cardboard_v1.cc",
    "sdk/unity/xr_provider/main.cc",
    "sdk/unity/xr_unity_plugin/opengl_es3_renderer.cc",
    "sdk/sensors/ios/sensor_helper.mm",
    "sdk/unity/xr_unity_plugin/opengl_es2_renderer.cc",
    "sdk/sensors/sensor_fusion_ekf.cc",
    "sdk/qrcode/ios/nsurl_session_data_handler.mm",
    "sdk/util/matrix_3x3.cc",
    "sdk/unity/xr_unity_plugin/cardboard_display_api.cc",
    "sdk/lens_distortion.cc",
    "sdk/qrcode/ios/qr_code.mm",
    "sdk/util/rotation.cc",
)


def run(command: list[str], *, cwd: Path | None = None) -> None:
    print("$", " ".join(command), flush=True)
    subprocess.check_call(command, cwd=cwd)


def sdk_kind() -> str:
    sdk_name = os.environ.get("SDK_NAME", "iphonesimulator")
    if sdk_name.startswith("iphoneos"):
        return "iphoneos"
    if sdk_name.startswith("iphonesimulator"):
        return "iphonesimulator"
    raise RuntimeError(f"Unsupported iOS SDK: {sdk_name}")


def sdk_path(kind: str) -> str:
    configured = os.environ.get("SDKROOT")
    if configured and configured != "auto":
        return configured
    return subprocess.check_output(
        ["xcrun", "--sdk", kind, "--show-sdk-path"], text=True
    ).strip()


def architectures() -> list[str]:
    requested = os.environ.get("ARCHS", "arm64").split()
    excluded = set(os.environ.get("EXCLUDED_ARCHS", "").split())
    result = [arch for arch in requested if arch not in excluded]
    return result or ["arm64"]


def source_paths() -> tuple[list[Path], list[Path]]:
    cardboard_sources = [CARDBOARD / path for path in CARDBOARD_SOURCES]
    protobuf_sources = sorted(PROTOBUF_SOURCE_ROOT.rglob("*.cc"))
    missing = [path for path in cardboard_sources + protobuf_sources if not path.is_file()]
    if missing:
        missing_text = "\n".join(str(path) for path in missing)
        raise RuntimeError(f"Cardboard source files are missing:\n{missing_text}")
    return cardboard_sources, protobuf_sources


def all_headers() -> list[Path]:
    return [
        *SDK_ROOT.rglob("*.h"),
        *PROTO_ROOT.rglob("*.h"),
        *sorted(PROTOBUF_SOURCE_ROOT.rglob("*.h")),
        *sorted((PODS_ROOT / "Headers" / "Private").rglob("*.h")),
        *sorted((PODS_ROOT / "Headers" / "Public").rglob("*.h")),
    ]


def archive_is_current(archive: Path, sources: list[Path], headers: list[Path]) -> bool:
    if not archive.is_file():
        return False
    archive_mtime = archive.stat().st_mtime_ns
    return all(path.stat().st_mtime_ns <= archive_mtime for path in sources + headers)


def object_name(source: Path, root: Path) -> str:
    relative = source.relative_to(root).as_posix()
    return relative.replace("/", "_").replace(".", "_") + ".o"


def compile_sources(
    sources: list[Path],
    root: Path,
    object_dir: Path,
    compiler: str,
    common_flags: list[str],
    *,
    objc_flags: list[str] | None = None,
) -> list[Path]:
    object_dir.mkdir(parents=True, exist_ok=True)
    objects: list[Path] = []
    for source in sources:
        object_path = object_dir / object_name(source, root)
        command = [compiler, *common_flags]
        if source.suffix == ".mm" and objc_flags:
            command.extend(objc_flags)
        command.extend(["-c", str(source), "-o", str(object_path)])
        run(command)
        objects.append(object_path)
    return objects


def build_for_arch(
    *,
    kind: str,
    sdk: str,
    arch: str,
    configuration: str,
    cardboard_sources: list[Path],
    protobuf_sources: list[Path],
    headers: list[Path],
) -> tuple[Path, Path]:
    platform_suffix = "-" + kind
    output_dir = OUTPUT_ROOT / f"{configuration}{platform_suffix}"
    arch_object_root = OBJECT_ROOT / f"{configuration}{platform_suffix}" / arch
    cardboard_object_dir = arch_object_root / "cardboard"
    protobuf_object_dir = arch_object_root / "protobuf"
    output_dir.mkdir(parents=True, exist_ok=True)

    clangxx = shutil.which("clang++") or subprocess.check_output(
        ["xcrun", "--sdk", kind, "--find", "clang++"], text=True
    ).strip()
    libtool = shutil.which("libtool") or subprocess.check_output(
        ["xcrun", "--sdk", kind, "--find", "libtool"], text=True
    ).strip()

    target = (
        f"{arch}-apple-ios12.0"
        if kind == "iphoneos"
        else f"{arch}-apple-ios12.0-simulator"
    )
    common_cardboard_flags = [
        "-target",
        target,
        "-std=c++17",
        "-stdlib=libc++",
        "-fmodules",
        "-fno-cxx-modules",
        "-fno-common",
        "-DGLES_SILENCE_DEPRECATION",
        "-DCOCOAPODS=1",
        "-isysroot",
        sdk,
        "-I",
        str(SDK_ROOT),
        "-I",
        str(PROTO_ROOT),
        "-I",
        str(CARDBOARD / "third_party" / "unity_plugin_api"),
        "-I",
        str(PODS_ROOT / "Headers" / "Public"),
        "-I",
        str(PODS_ROOT / "Headers" / "Public" / "Protobuf-C++"),
    ]
    if configuration.lower() == "debug":
        common_cardboard_flags.extend(["-O0", "-g", "-DDEBUG=1"])
    else:
        common_cardboard_flags.extend(["-O2", "-DNDEBUG"])

    min_version_flag = (
        "-miphoneos-version-min=12.0"
        if kind == "iphoneos"
        else "-mios-simulator-version-min=12.0"
    )
    common_cardboard_flags.append(min_version_flag)
    objc_flags = ["-fobjc-arc", "-fobjc-weak"]

    common_protobuf_flags = [
        "-target",
        target,
        "-std=gnu++14",
        "-stdlib=libc++",
        "-fno-common",
        "-DCOCOAPODS=1",
        "-DHAVE_PTHREAD=1",
        "-isysroot",
        sdk,
        "-I",
        str(PROTOBUF_SOURCE_ROOT),
        "-I",
        str(PODS_ROOT / "Headers" / "Private"),
        "-I",
        str(PODS_ROOT / "Headers" / "Private" / "Protobuf-C++"),
        "-I",
        str(PODS_ROOT / "Headers" / "Public"),
        "-I",
        str(PODS_ROOT / "Headers" / "Public" / "Protobuf-C++"),
        "-w",
    ]
    if configuration.lower() == "debug":
        common_protobuf_flags.extend(["-O0", "-g", "-DDEBUG=1", "-DPOD_CONFIGURATION_DEBUG=1"])
    else:
        common_protobuf_flags.extend(["-O2", "-DNDEBUG", "-DPOD_CONFIGURATION_RELEASE=1"])
    common_protobuf_flags.append(min_version_flag)

    cardboard_objects = compile_sources(
        cardboard_sources,
        CARDBOARD,
        cardboard_object_dir,
        clangxx,
        common_cardboard_flags,
        objc_flags=objc_flags,
    )
    protobuf_objects = compile_sources(
        protobuf_sources,
        PROTOBUF_SOURCE_ROOT,
        protobuf_object_dir,
        clangxx,
        common_protobuf_flags,
    )

    cardboard_archive = arch_object_root / "GfxPluginCardboard.a"
    protobuf_archive = arch_object_root / "libProtobuf-C++.a"
    run([libtool, "-static", "-o", str(cardboard_archive), *map(str, cardboard_objects)])
    run([libtool, "-static", "-o", str(protobuf_archive), *map(str, protobuf_objects)])
    return cardboard_archive, protobuf_archive


def make_universal(archives: list[Path], output: Path, lipo: str) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    if len(archives) == 1:
        shutil.copy2(archives[0], output)
    else:
        run([lipo, "-create", "-output", str(output), *map(str, archives)])


def main() -> int:
    kind = sdk_kind()
    sdk = sdk_path(kind)
    configuration = os.environ.get("CONFIGURATION", "Debug")
    archs = architectures()
    cardboard_sources, protobuf_sources = source_paths()
    headers = all_headers()

    output_dir = OUTPUT_ROOT / f"{configuration}-{kind}"
    cardboard_output = output_dir / "GfxPluginCardboard.a"
    protobuf_output = output_dir / "Protobuf-C++" / "libProtobuf-C++.a"
    if archive_is_current(cardboard_output, cardboard_sources, headers) and archive_is_current(
        protobuf_output, protobuf_sources, headers
    ):
        print(f"Cardboard libraries are current in {output_dir}")
        return 0

    print(
        f"Building Cardboard for {kind}, configuration {configuration}, "
        f"architectures: {', '.join(archs)}",
        flush=True,
    )
    per_arch = [
        build_for_arch(
            kind=kind,
            sdk=sdk,
            arch=arch,
            configuration=configuration,
            cardboard_sources=cardboard_sources,
            protobuf_sources=protobuf_sources,
            headers=headers,
        )
        for arch in archs
    ]
    lipo = shutil.which("lipo") or subprocess.check_output(
        ["xcrun", "--sdk", kind, "--find", "lipo"], text=True
    ).strip()
    make_universal([pair[0] for pair in per_arch], cardboard_output, lipo)
    protobuf_output.parent.mkdir(parents=True, exist_ok=True)
    make_universal([pair[1] for pair in per_arch], protobuf_output, lipo)
    print(f"Built {cardboard_output}")
    print(f"Built {protobuf_output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
