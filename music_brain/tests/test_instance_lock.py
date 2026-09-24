import os
from pathlib import Path
import subprocess
import sys

import pytest

pytestmark = pytest.mark.skipif(sys.platform != 'win32', reason='Windows launcher lock')


def test_second_instance_exits_cleanly_and_lock_can_be_reacquired(tmp_path):
    from music_brain.instance_lock import acquire_instance
    path = tmp_path / 'instance.lock'
    first = acquire_instance(path)
    assert first is not None
    code = ('import sys; from pathlib import Path; '
            'from music_brain.instance_lock import acquire_instance; '
            'lock=acquire_instance(Path(sys.argv[1])); '
            'print("busy" if lock is None else "acquired")')
    env = os.environ.copy()
    env['PYTHONPATH'] = str(Path(__file__).resolve().parents[2])
    duplicate = subprocess.run([sys.executable, '-c', code, str(path)], env=env,
                               capture_output=True, text=True, timeout=5)
    assert duplicate.returncode == 0, duplicate.stderr
    assert duplicate.stdout.strip() == 'busy'
    first.close()
    next_instance = acquire_instance(path)
    assert next_instance is not None
    next_instance.close()
