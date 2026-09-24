import importlib.util
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('music_export', Path(__file__).parents[1] / 'export_video.py')
exporter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(exporter)


def test_locked_video_keeps_new_and_playing_versions(tmp_path, monkeypatch):
    output = tmp_path / 'video.mp4'
    output.write_bytes(b'playing version')
    temp = tmp_path / 'rendering.mp4'
    temp.write_bytes(b'validated new render')
    replace = exporter.os.replace

    def locked_replace(source, destination):
        if destination == output:
            raise PermissionError('video is open in a player')
        return replace(source, destination)

    monkeypatch.setattr(exporter.os, 'replace', locked_replace)
    published = exporter.publish_render(temp, output)
    assert published != output
    assert published.read_bytes() == b'validated new render'
    assert output.read_bytes() == b'playing version'
    assert not temp.exists()
