"""Versioned, indexed binary neural recording. No pickle, no giant JSON arrays."""
import json
import struct
import zlib
from pathlib import Path


class TimelineWriter:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.file = (self.directory/'neural.bin').open('wb')
        self.index = []

    def append(self, state, frame):
        payload = zlib.compress(frame, 1)
        header = json.dumps({**state, 'frame_bytes': len(payload), 'frame_raw_bytes': len(frame),
                             'frame_encoding': 'deflate'}, separators=(',', ':'), allow_nan=False).encode()
        self.index.append({'time': state['sim_time'], 'offset': self.file.tell()})
        self.file.write(struct.pack('<II', len(header), len(payload)))
        self.file.write(header)
        self.file.write(payload)

    def close(self):
        self.file.close()
        (self.directory/'index.json').write_text(json.dumps(self.index, separators=(',', ':')), encoding='utf-8')


def read_record(stream, offset):
    stream.seek(offset)
    sizes = stream.read(8)
    if len(sizes) != 8: raise ValueError('Truncated neural record')
    header_size, frame_size = struct.unpack('<II', sizes)
    if not 1 <= header_size <= 65536 or not 0 <= frame_size <= 4194304:
        raise ValueError('Invalid neural record size')
    state = json.loads(stream.read(header_size))
    frame = zlib.decompress(stream.read(frame_size))
    if len(frame) != state['frame_raw_bytes']: raise ValueError('Truncated neural frame')
    return state, frame
