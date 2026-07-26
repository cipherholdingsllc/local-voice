#!/usr/bin/env bash
# Install Parakeet MLX for Local Flow dual-engine STT (#4)
# Creates a dedicated venv at ~/.config/open-wispr/parakeet-venv — same Python the daemon uses.
set -euo pipefail

CONFIG_DIR="${HOME}/.config/open-wispr"
VENV_DIR="${CONFIG_DIR}/parakeet-venv"
PYTHON_MARKER="${CONFIG_DIR}/parakeet-python.txt"

echo "Local Flow — Parakeet installer"
echo "Requires: ffmpeg, Python 3.10+"

if ! command -v ffmpeg >/dev/null; then
  echo "Installing ffmpeg..."
  brew install ffmpeg
fi

mkdir -p "${CONFIG_DIR}"

if command -v uv >/dev/null; then
  echo "Creating Parakeet venv at ${VENV_DIR}..."
  export UV_VENV_CLEAR=1
  uv venv "${VENV_DIR}" --python python3 --clear
  echo "Installing parakeet-mlx into venv..."
  uv pip install --python "${VENV_DIR}/bin/python" parakeet-mlx
else
  echo "Creating Parakeet venv via python3 -m venv..."
  python3 -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/pip" install --upgrade pip
  "${VENV_DIR}/bin/pip" install parakeet-mlx
fi

VENV_PYTHON="${VENV_DIR}/bin/python"
echo "${VENV_PYTHON}" > "${PYTHON_MARKER}"

echo "Verifying import..."
"${VENV_PYTHON}" -c "from parakeet_mlx import from_pretrained; print('parakeet-mlx OK')"

echo ""
echo "Done."
echo "  Python: ${VENV_PYTHON}"
echo "  Marker: ${PYTHON_MARKER}"
echo "First transcribe downloads ~2.5GB model to HF cache."
echo "Restart Local Flow — English dictation will auto-select Parakeet."
