#!/usr/bin/env python3
"""Build the online-only Ballistica static libraries for the iOS VR target."""

from __future__ import annotations

import os
import hashlib
import json
import re
import shutil
import shlex
import subprocess
import tempfile
import urllib.error
import urllib.request
import zlib
from pathlib import Path


APP_ROOT = Path(__file__).resolve().parents[1]
WORKSPACE_ROOT = APP_ROOT.parent
BALLISTICA_ROOT = WORKSPACE_ROOT / "ballistica"
BALLISTICA_SRC = BALLISTICA_ROOT / "src"
BRIDGE_ROOT = APP_ROOT / "BallisticaBridge"
RAW_SDK_NAME = os.environ.get("SDK_NAME") or os.environ.get("PLATFORM_NAME", "")
APPLE_SDK_NAME = "iphoneos" if RAW_SDK_NAME.startswith("iphoneos") else "iphonesimulator"
PYTHON_ROOT = BALLISTICA_ROOT / "build" / f"python_apple_{APPLE_SDK_NAME}_arm64"
BUILD_FLAVOR = "online"
BUILD_ROOT = BALLISTICA_ROOT / "build" / "ios_vr_native" / f"{APPLE_SDK_NAME}-arm64"
OBJ_ROOT = BUILD_ROOT / "obj"
LIB_PATH = BUILD_ROOT / "libballistica_ios_vr.a"
BUILD_FLAVOR_PATH = BUILD_ROOT / "build-flavor.txt"
PLUS_SOURCE_RELATIVE = Path(
    "build/prefab/lib/mac_arm64_gui/release/libballisticaplus.a"
)
PLUS_SOURCE_PATH = BALLISTICA_ROOT / PLUS_SOURCE_RELATIVE
PLUS_BUILD_ROOT = (
    BALLISTICA_ROOT / "build" / "ios_vr_plus" / f"{APPLE_SDK_NAME}-arm64"
)
PLUS_LIB_PATH = PLUS_BUILD_ROOT / "libballisticaplus_ios.a"
EFROCACHE_MAP = BALLISTICA_ROOT / ".efrocachemap"
PROJECT_CONFIG = BALLISTICA_ROOT / "pconfig" / "projectconfig.json"
CONFIG_HEADER = BRIDGE_ROOT / "BallisticaBuildConfigIOS.h"
CMAKE_FILE = BALLISTICA_ROOT / "ballisticakit-cmake" / "CMakeLists.txt"
AUDIO_BUILD_ROOT = BALLISTICA_ROOT / "build" / "ios_vr_audio"
AUDIO_SOURCE_ROOT = AUDIO_BUILD_ROOT / "sources"
OGG_SOURCE_ROOT = AUDIO_SOURCE_ROOT / "libogg-1.3.6"
VORBIS_SOURCE_ROOT = AUDIO_SOURCE_ROOT / "libvorbis-1.3.7"
OPENAL_BUILD_ROOT = BALLISTICA_ROOT / "build" / "openal-apple"
OPENAL_ARTIFACTS_ROOT = OPENAL_BUILD_ROOT / "artifacts"
OPENAL_INCLUDE_ROOT = OPENAL_ARTIFACTS_ROOT / "include"
OPENAL_XCFRAMEWORK = OPENAL_ARTIFACTS_ROOT / "OpenALSoft.xcframework"
AUDIO_ARCHIVES = (
    (
        "libogg-1.3.6.tar.gz",
        "https://ftp.osuosl.org/pub/xiph/releases/ogg/libogg-1.3.6.tar.gz",
        "83e6704730683d004d20e21b8f7f55dcb3383cdf84c0daedf30bde175f774638",
    ),
    (
        "libvorbis-1.3.7.tar.xz",
        "https://ftp.osuosl.org/pub/xiph/releases/vorbis/libvorbis-1.3.7.tar.xz",
        "b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b",
    ),
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as infile:
        for chunk in iter(lambda: infile.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _download_audio_archive(name: str, url: str, expected_hash: str) -> Path:
    downloads = AUDIO_BUILD_ROOT / "downloads"
    archive = downloads / name
    if archive.exists() and _sha256(archive) == expected_hash:
        return archive
    if archive.exists():
        archive.unlink()

    print(f"Downloading open-source audio dependency: {url}")
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read()
    except (OSError, urllib.error.URLError) as exc:
        raise RuntimeError(f"Unable to download audio dependency {name}.") from exc
    actual_hash = hashlib.sha256(data).hexdigest()
    if actual_hash != expected_hash:
        raise RuntimeError(
            f"Audio dependency hash mismatch for {name}: expected "
            f"{expected_hash}, got {actual_hash}"
        )
    _atomic_write(archive, data)
    return archive


def _prepare_audio_sources() -> None:
    stamp_text = "libogg-1.3.6+libvorbis-1.3.7\n"
    stamp = AUDIO_SOURCE_ROOT / ".stamp"
    if (
        stamp.exists()
        and stamp.read_text(encoding="utf-8") == stamp_text
        and (OGG_SOURCE_ROOT / "src" / "framing.c").exists()
        and (VORBIS_SOURCE_ROOT / "lib" / "vorbisfile.c").exists()
    ):
        return

    AUDIO_BUILD_ROOT.mkdir(parents=True, exist_ok=True)
    archives = [
        _download_audio_archive(name, url, expected_hash)
        for name, url, expected_hash in AUDIO_ARCHIVES
    ]
    with tempfile.TemporaryDirectory(
        prefix="audio-sources-", dir=AUDIO_BUILD_ROOT
    ) as temp_dir:
        extracted = Path(temp_dir) / "extracted"
        extracted.mkdir()
        for archive in archives:
            subprocess.check_call(["tar", "-xf", str(archive), "-C", str(extracted)])
        if not (
            (extracted / OGG_SOURCE_ROOT.name / "src" / "framing.c").exists()
            and (extracted / VORBIS_SOURCE_ROOT.name / "lib" / "vorbisfile.c").exists()
        ):
            raise RuntimeError("Audio dependency archives have an unexpected layout.")
        if AUDIO_SOURCE_ROOT.exists():
            shutil.rmtree(AUDIO_SOURCE_ROOT)
        os.replace(extracted, AUDIO_SOURCE_ROOT)
    _atomic_write(stamp, stamp_text.encode())


def _audio_source_files() -> list[Path]:
    ogg_sources = ["bitwise.c", "framing.c"]
    vorbis_sources = [
        "mdct.c",
        "smallft.c",
        "block.c",
        "envelope.c",
        "window.c",
        "lsp.c",
        "lpc.c",
        "analysis.c",
        "synthesis.c",
        "psy.c",
        "info.c",
        "floor1.c",
        "floor0.c",
        "res0.c",
        "mapping0.c",
        "registry.c",
        "codebook.c",
        "sharedbook.c",
        "lookup.c",
        "bitrate.c",
        "vorbisfile.c",
    ]
    return [OGG_SOURCE_ROOT / "src" / name for name in ogg_sources] + [
        VORBIS_SOURCE_ROOT / "lib" / name for name in vorbis_sources
    ]


def _prepare_openal() -> None:
    """Build the latest upstream OpenAL Soft Apple dependency when needed."""
    if (
        OPENAL_XCFRAMEWORK.exists()
        and (OPENAL_INCLUDE_ROOT / "AL" / "al.h").exists()
    ):
        return

    pcommand = BALLISTICA_ROOT / "tools" / "pcommand"
    if not pcommand.exists():
        raise RuntimeError(f"Missing Ballistica pcommand at {pcommand}")
    print("Building the upstream OpenAL Soft Apple dependency...", flush=True)
    subprocess.check_call([str(pcommand), "openal_apple_test_build"], cwd=BALLISTICA_ROOT)


def _run(args: list[str]) -> str:
    return subprocess.check_output(args, text=True).strip()


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as outfile:
        tmp_path = Path(outfile.name)
        outfile.write(data)
    os.replace(tmp_path, path)


def _ensure_private_plus_source() -> None:
    cache_map = json.loads(EFROCACHE_MAP.read_text(encoding="utf-8"))
    cache_key = PLUS_SOURCE_RELATIVE.as_posix()
    expected_hash = cache_map.get(cache_key)
    if not isinstance(expected_hash, str):
        raise RuntimeError(f"Missing {cache_key} in {EFROCACHE_MAP}")

    metadata = b'{"e":false}'
    prefix = b"efca" + len(metadata).to_bytes(1, "big") + metadata
    if PLUS_SOURCE_PATH.exists():
        actual_hash = hashlib.md5(
            prefix + PLUS_SOURCE_PATH.read_bytes(), usedforsecurity=False
        ).hexdigest()
        if actual_hash == expected_hash:
            return
        PLUS_SOURCE_PATH.unlink()

    hash_subpath = "/".join(
        (expected_hash[:2], expected_hash[2:4], expected_hash[4:])
    )
    local_cache_path = (
        BALLISTICA_ROOT / ".cache" / "efrocache" / Path(hash_subpath)
    )
    if not local_cache_path.exists():
        project_config = json.loads(PROJECT_CONFIG.read_text(encoding="utf-8"))
        repository_url = project_config.get("efrocache_repository_url")
        if not isinstance(repository_url, str):
            raise RuntimeError(
                f"Missing efrocache_repository_url in {PROJECT_CONFIG}"
            )
        url = f"{repository_url}/{hash_subpath}"
        print(f"Downloading private Ballistica Plus build dependency: {url}")
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                cache_data = response.read()
        except (OSError, urllib.error.URLError) as exc:
            raise RuntimeError(
                "Unable to download Ballistica Plus. Check network access or "
                f"place the matching archive at {PLUS_SOURCE_PATH}."
            ) from exc
        _atomic_write(local_cache_path, cache_data)

    cache_data = local_cache_path.read_bytes()
    if cache_data[:4] != b"efca" or len(cache_data) < 6:
        raise RuntimeError(f"Invalid efrocache data at {local_cache_path}")
    metadata_length = cache_data[4]
    cache_prefix = cache_data[: 5 + metadata_length]
    try:
        source_data = zlib.decompress(cache_data[5 + metadata_length :])
    except zlib.error as exc:
        raise RuntimeError(
            f"Corrupt efrocache data at {local_cache_path}"
        ) from exc
    actual_hash = hashlib.md5(
        cache_prefix + source_data, usedforsecurity=False
    ).hexdigest()
    if actual_hash != expected_hash:
        raise RuntimeError(
            f"Ballistica Plus hash mismatch: expected {expected_hash}, "
            f"got {actual_hash}"
        )
    _atomic_write(PLUS_SOURCE_PATH, source_data)


def _prepare_private_plus() -> None:
    _ensure_private_plus_source()
    if (
        PLUS_LIB_PATH.exists()
        and PLUS_LIB_PATH.stat().st_mtime >= PLUS_SOURCE_PATH.stat().st_mtime
        and PLUS_LIB_PATH.stat().st_mtime >= Path(__file__).stat().st_mtime
    ):
        return

    sdk_version = _run(
        ["xcrun", "--sdk", APPLE_SDK_NAME, "--show-sdk-version"]
    )
    ar = _run(["xcrun", "--sdk", APPLE_SDK_NAME, "--find", "ar"])
    libtool = _run(["xcrun", "--sdk", APPLE_SDK_NAME, "--find", "libtool"])
    vtool = _run(["xcrun", "--find", "vtool"])
    platform = "ios" if APPLE_SDK_NAME == "iphoneos" else "iossim"

    PLUS_BUILD_ROOT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="adapt-", dir=PLUS_BUILD_ROOT
    ) as temp_dir:
        temp_root = Path(temp_dir)
        extracted_root = temp_root / "extracted"
        adapted_root = temp_root / "adapted"
        extracted_root.mkdir()
        adapted_root.mkdir()
        subprocess.check_call(
            [ar, "-x", str(PLUS_SOURCE_PATH)], cwd=extracted_root
        )

        adapted_objects: list[Path] = []
        for source_object in sorted(extracted_root.glob("*.o")):
            adapted_object = adapted_root / source_object.name
            subprocess.check_call(
                [
                    vtool,
                    "-set-build-version",
                    platform,
                    "16.0",
                    sdk_version,
                    "-replace",
                    "-output",
                    str(adapted_object),
                    str(source_object),
                ]
            )
            adapted_objects.append(adapted_object)
        if not adapted_objects:
            raise RuntimeError(
                f"No object files found in {PLUS_SOURCE_PATH}"
            )

        temp_library = temp_root / PLUS_LIB_PATH.name
        subprocess.check_call(
            [libtool, "-static", "-o", str(temp_library)]
            + [str(path) for path in adapted_objects]
        )
        os.replace(temp_library, PLUS_LIB_PATH)


def _extract_cmake_block(start_re: str) -> list[str]:
    lines = CMAKE_FILE.read_text(encoding="utf-8").splitlines()
    out: list[str] = []
    in_block = False
    start = re.compile(start_re)
    for line in lines:
        stripped = line.strip()
        if not in_block:
            if start.match(stripped):
                in_block = True
            continue
        if stripped == ")":
            break
        item = line.split("#", 1)[0].strip()
        if item:
            out.append(item)
    return out


def _expand_cmake_path(item: str) -> Path:
    item = item.replace("${BA_SRC_ROOT}", str(BALLISTICA_SRC))
    item = item.replace(
        "${ODE_SRC_ROOT}", str(BALLISTICA_SRC / "external" / "open_dynamics_engine-ef")
    )
    return Path(item)


def _excluded(path: Path) -> bool:
    rel = path.relative_to(BALLISTICA_SRC).as_posix()
    excluded_exact = {
        "ballistica/base/app_adapter/app_adapter_headless.cc",
        "ballistica/base/app_adapter/app_adapter_sdl.cc",
        "ballistica/base/app_adapter/app_adapter_vr.cc",
        "ballistica/base/app_platform/linux/app_platform_linux.cc",
        "ballistica/base/app_platform/windows/app_platform_windows.cc",
        "ballistica/base/graphics/gl/gl_sys_windows.cc",
        "ballistica/core/platform/linux/platform_linux.cc",
        "ballistica/core/platform/windows/platform_windows.cc",
    }
    excluded_prefixes = (
        "ballistica/base/platform/android/",
        "ballistica/core/platform/android/",
    )
    if rel in excluded_exact:
        return True
    return any(rel.startswith(prefix) for prefix in excluded_prefixes)


def _source_files() -> list[Path]:
    ode_items = _extract_cmake_block(r"add_library\(ode\b")
    ba_items = _extract_cmake_block(r"set\(BALLISTICA_SOURCES\b")
    files: list[Path] = []
    for item in ode_items + ba_items:
        path = _expand_cmake_path(item)
        if path.suffix not in {".c", ".cc", ".cpp"}:
            continue
        if not path.exists():
            raise RuntimeError(f"Missing source from CMake list: {path}")
        if path.is_relative_to(BALLISTICA_SRC) and _excluded(path):
            continue
        files.append(path)

    files.extend(_audio_source_files())
    return files


def _obj_path(src: Path) -> Path:
    try:
        rel = src.relative_to(WORKSPACE_ROOT)
    except ValueError:
        rel = Path(src.name)
    return OBJ_ROOT / (rel.as_posix().replace("/", "__") + ".o")


def _dep_path(obj: Path) -> Path:
    return obj.with_suffix(".d")


def _read_dependencies(dep_path: Path) -> list[Path]:
    """Read the source/header paths from a Clang make dependency file."""
    contents = dep_path.read_text(encoding="utf-8").replace("\\\n", " ")
    _, separator, dependencies = contents.partition(":")
    if not separator:
        raise ValueError(f"Invalid dependency file: {dep_path}")
    return [Path(value) for value in shlex.split(dependencies)]


def _needs_rebuild(obj: Path, src: Path) -> bool:
    if not obj.exists():
        return True
    dep_path = _dep_path(obj)
    if not dep_path.exists():
        return True
    try:
        dependencies = _read_dependencies(dep_path)
    except (OSError, ValueError):
        return True
    obj_mtime = obj.stat().st_mtime
    dependencies.append(Path(__file__).resolve())
    return any(
        not dependency.exists() or dependency.stat().st_mtime > obj_mtime
        for dependency in dependencies
    )


def main() -> int:
    if not CMAKE_FILE.exists():
        print(f"Missing Ballistica checkout at {BALLISTICA_ROOT}", file=os.sys.stderr)
        return 1
    if not (PYTHON_ROOT / "include" / "Python.h").exists():
        print(
            f"Missing {APPLE_SDK_NAME} Python headers. Run "
            "`cd ../ballistica && tools/pcommand python_build_apple "
            f"{APPLE_SDK_NAME}.arm64`.",
            file=os.sys.stderr,
        )
        return 1
    if not (PYTHON_ROOT / "libpython_merged.a").exists():
        print(f"Missing libpython_merged.a for {APPLE_SDK_NAME}.", file=os.sys.stderr)
        return 1

    _prepare_audio_sources()
    _prepare_openal()

    _prepare_private_plus()

    sdk = _run(["xcrun", "--sdk", APPLE_SDK_NAME, "--show-sdk-path"])
    clang = _run(["xcrun", "--sdk", APPLE_SDK_NAME, "--find", "clang"])
    clangxx = _run(["xcrun", "--sdk", APPLE_SDK_NAME, "--find", "clang++"])
    libtool = _run(["xcrun", "--sdk", APPLE_SDK_NAME, "--find", "libtool"])

    BUILD_ROOT.mkdir(parents=True, exist_ok=True)
    OBJ_ROOT.mkdir(parents=True, exist_ok=True)

    common_flags = [
        "-arch",
        "arm64",
        "-isysroot",
        sdk,
        "-miphoneos-version-min=16.0"
        if APPLE_SDK_NAME == "iphoneos"
        else "-mios-simulator-version-min=16.0",
        "-fPIC",
        "-fvisibility=hidden",
        "-Wno-deprecated-declarations",
        "-Wno-unused-command-line-argument",
        "-include",
        str(CONFIG_HEADER),
        "-I",
        str(BRIDGE_ROOT),
        "-I",
        str(BALLISTICA_SRC),
        "-I",
        str(BALLISTICA_SRC / "external" / "open_dynamics_engine-ef"),
        "-I",
        str(PYTHON_ROOT / "include"),
        "-I",
        str(OGG_SOURCE_ROOT / "include"),
        "-I",
        str(VORBIS_SOURCE_ROOT / "include"),
        "-I",
        str(VORBIS_SOURCE_ROOT / "lib"),
        "-I",
        str(OPENAL_INCLUDE_ROOT / "AL"),
    ]
    c_flags = common_flags + ["-std=c17"]
    cxx_flags = common_flags + ["-std=c++23", "-stdlib=libc++"]

    objects: list[Path] = []
    sources = _source_files()
    for index, src in enumerate(sources, start=1):
        obj = _obj_path(src)
        obj.parent.mkdir(parents=True, exist_ok=True)
        objects.append(obj)
        if not _needs_rebuild(obj, src):
            continue
        compiler = clang if src.suffix == ".c" else clangxx
        flags = c_flags if src.suffix == ".c" else cxx_flags
        dep = _dep_path(obj)
        print(f"[{index:03d}/{len(sources):03d}] {src.relative_to(WORKSPACE_ROOT)}")
        subprocess.check_call(
            [
                compiler,
                *flags,
                "-MMD",
                "-MF",
                str(dep),
                "-MT",
                str(obj),
                "-c",
                str(src),
                "-o",
                str(obj),
            ]
        )

    lib_needs_rebuild = not LIB_PATH.exists()
    if BUILD_FLAVOR_PATH.exists():
        lib_needs_rebuild = (
            lib_needs_rebuild
            or BUILD_FLAVOR_PATH.read_text(encoding="utf-8") != BUILD_FLAVOR
        )
    else:
        lib_needs_rebuild = True
    if not lib_needs_rebuild:
        lib_mtime = LIB_PATH.stat().st_mtime
        lib_needs_rebuild = any(obj.stat().st_mtime > lib_mtime for obj in objects)
    if lib_needs_rebuild:
        tmp = LIB_PATH.with_suffix(".a.tmp")
        if tmp.exists():
            tmp.unlink()
        subprocess.check_call([libtool, "-static", "-o", str(tmp), *map(str, objects)])
        os.replace(tmp, LIB_PATH)
        BUILD_FLAVOR_PATH.write_text(BUILD_FLAVOR, encoding="utf-8")

    print(f"Built {LIB_PATH}")
    print(f"Built {PLUS_LIB_PATH} (online)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
