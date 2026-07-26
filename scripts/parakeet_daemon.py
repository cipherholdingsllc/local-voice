#!/usr/bin/env python3
"""Long-lived Parakeet TDT daemon for Local Flow — JSON-lines protocol."""
# MIT License — Local Flow / Cipher Lab
import json
import sys


def main():
    try:
        from parakeet_mlx import from_pretrained
    except ImportError:
        print(json.dumps({"error": "parakeet-mlx not installed. Run: scripts/install-parakeet.sh"}), flush=True)
        sys.exit(1)

    model_id = "mlx-community/parakeet-tdt-0.6b-v3"
    sys.stderr.write(f"Loading {model_id}...\n")
    model = from_pretrained(model_id)
    print(json.dumps({"ready": True, "model": model_id}), flush=True)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            print(json.dumps({"error": "invalid json"}), flush=True)
            continue

        cmd = req.get("cmd")
        if cmd == "quit":
            break
        if cmd == "transcribe":
            path = req.get("path", "")
            try:
                result = model.transcribe(path)
                text = (result.text if hasattr(result, "text") else str(result)).strip()
                print(json.dumps({"text": text}), flush=True)
            except Exception as e:
                print(json.dumps({"error": str(e)}), flush=True)
        else:
            print(json.dumps({"error": f"unknown cmd: {cmd}"}), flush=True)


if __name__ == "__main__":
    main()
