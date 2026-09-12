"""RARS process infrastructure only; no FOCAL semantic implementation."""

from dataclasses import dataclass
import hashlib
from pathlib import Path
import shutil
import subprocess

EXACT = "exact"
LEGACY_SUBSTRING = "legacy-substring"
BASELINE_RARS_SHA256 = "780F730EB457B1BA609E968ACCC2C8B77D8F92C3D9DBF30CC7FDB3CFB14E8C24"
NORMAL_TERMINATION = "Program terminated by calling exit"


class RunnerEnvironmentError(Exception):
    """A prerequisite prevents the suite from starting."""


@dataclass(frozen=True)
class Environment:
    java: str
    jar: Path
    sha256: str

    @property
    def rars_id(self):
        if self.sha256.upper() == BASELINE_RARS_SHA256:
            return "RARS 1.6 (verified baseline SHA-256)"
        return "unrecognized JAR hash; RARS 1.6 CLI required"


@dataclass(frozen=True)
class RunResult:
    category: str
    detail: str
    stdout: str = ""
    stderr: str = ""
    returncode: int | None = None

    @property
    def passed(self):
        return self.category == "PASS"


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def check_environment(jar_value, template):
    if not jar_value or not jar_value.strip():
        raise RunnerEnvironmentError("RARS_JAR is not set")
    jar = Path(jar_value).expanduser().resolve()
    if not jar.is_file():
        raise RunnerEnvironmentError(f"RARS JAR is not a file: {jar}")
    java = shutil.which("java")
    if not java:
        raise RunnerEnvironmentError("Java executable 'java' was not found in PATH")
    if not template.is_file():
        raise RunnerEnvironmentError(f"ASM template is not a file: {template}")
    try:
        checksum = sha256_file(jar)
    except OSError as error:
        raise RunnerEnvironmentError(f"Cannot read RARS JAR: {error}") from error
    return Environment(java, jar, checksum)


def git_head(root):
    """Metadata is useful but Git is not a runtime dependency of the suite."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=root, capture_output=True,
            text=True, encoding="utf-8", errors="replace", timeout=10,
            stdin=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return "unavailable"


def normalize_newlines(value):
    return value.replace("\r\n", "\n")


def compare_output(actual, expected, mode=EXACT):
    actual = normalize_newlines(actual)
    expected = normalize_newlines(expected)
    if mode == EXACT:
        # Spaces and final newlines belong to the exact contract.
        return actual == expected
    if mode == LEGACY_SUBSTRING:
        # Deliberately retain the seven original fixtures' comparison contract.
        return expected.strip() in actual.strip()
    raise ValueError(f"Unknown comparison mode: {mode}")


def _text(value):
    # TimeoutExpired may contain bytes even with text=True.
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value or ""


def run_rars(environment, asm_path, expected, *, comparison=EXACT, timeout=30,
             stdin_text=None):
    """Run a batch fixture; check diagnostics before comparing program output.

    ae2/se3 replace RARS 1.6's zero default error exit codes. me separates
    simulator diagnostics from stdout. subprocess.run kills and reaps its
    child on timeout; the returned failure retains partial output.
    """
    command = [environment.java, "-jar", str(environment.jar),
               "nc", "me", "ae2", "se3", str(asm_path)]
    try:
        result = subprocess.run(
            command, cwd=asm_path.parent, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout,
            **({"stdin": subprocess.DEVNULL} if stdin_text is None
               else {"input": stdin_text}),
        )
    except subprocess.TimeoutExpired as error:
        return RunResult("TIMEOUT", f"RARS exceeded {timeout}s",
                         _text(error.stdout), _text(error.stderr))
    except OSError as error:
        return RunResult("ENVIRONMENT", f"Cannot launch Java/RARS: {error}")

    stdout, stderr, code = result.stdout, result.stderr, result.returncode
    if code == 2:
        return RunResult("ASSEMBLY", "RARS assembly failed", stdout, stderr, code)
    if code == 3:
        return RunResult("SIMULATION", "RARS runtime exception", stdout, stderr, code)
    if code != 0:
        return RunResult("ENVIRONMENT", f"Java/RARS exited with code {code}", stdout, stderr, code)
    # Do not suppress warnings, step-limit termination or JVM registry errors.
    diagnostics = [line for line in normalize_newlines(stderr).split("\n")
                   if line and line != NORMAL_TERMINATION]
    if diagnostics:
        return RunResult("RARS_DIAGNOSTIC", "Unexpected RARS/JVM diagnostics", stdout, stderr, code)
    if not compare_output(stdout, expected, comparison):
        return RunResult("MISMATCH", f"Output differs ({comparison})", stdout, stderr, code)
    return RunResult("PASS", comparison, stdout, stderr, code)
