#! /usr/bin/env python

from huggingface_hub import snapshot_download


if __name__ == "__main__":
    import sys

    model_id = sys.argv[1]
    snapshot_download(
        repo_id=model_id,
        local_dir=model_id,
        local_dir_use_symlinks=False,
        revision="main",
    )
