"""Sample an exported video at a fixed cadence for visual review.

Frame differences describe change, not beauty or beat alignment. The contact
sheet is the primary artifact; adjacent crops must be inspected by a person.
"""
import argparse
from fractions import Fraction
import json
import math
from pathlib import Path
import subprocess

import numpy as np
from PIL import Image, ImageDraw


def review(video, output, start=6., duration=10., fps=10.):
    video, output = Path(video).resolve(), Path(output).resolve()
    if start < 0 or duration <= 0 or fps <= 0:
        raise ValueError('Use nonnegative start and positive duration/cadence')
    info = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_streams', '-show_format',
        '-of', 'json', str(video)], text=True))
    stream = next(s for s in info['streams'] if s['codec_type'] == 'video')
    source_fps = float(Fraction(stream['avg_frame_rate']))
    stride = max(1, round(source_fps / fps))
    cadence = source_fps / stride
    span = min(duration, float(info['format']['duration']) - start)
    if span <= 0:
        raise ValueError('Start is beyond the end of the video')
    count = math.ceil(span * cadence - 1e-6)
    width, height, columns, label = 320, 180, 10, 22
    canvas = Image.new('RGB', (columns*width, math.ceil(count/columns)*(height+label)), '#11141c')
    draw = ImageDraw.Draw(canvas)
    command = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-ss', str(start),
               '-i', str(video), '-t', str(span), '-an', '-vf',
               f'select=not(mod(n\\,{stride})),scale={width}:{height}',
               '-fps_mode', 'vfr', '-f', 'rawvideo', '-pix_fmt', 'rgb24', 'pipe:1']
    previous = None
    changes, frames = [], []
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          creationflags=0x08000000) as process:
        for i in range(count):
            raw = process.stdout.read(width*height*3)
            if not raw:
                break
            if len(raw) != width*height*3:
                raise RuntimeError('Incomplete decoded frame')
            image = Image.frombytes('RGB', (width, height), raw)
            x, y = (i % columns)*width, (i // columns)*(height+label)
            canvas.paste(image, (x, y))
            t = start + i/cadence
            draw.text((x+6, y+height+3), f'{t:.2f} s', fill='#e1e8f3')
            current = np.asarray(image, dtype=np.float32)/255.
            difference = None if previous is None else float(np.mean(np.abs(current-previous)))
            if difference is not None:
                changes.append(difference)
            frames.append({'time_s': t, 'mean_absolute_change': difference})
            previous = current
        # Drain remaining output before wait (rounding may add one frame).
        _, error = process.communicate()
        if process.returncode:
            raise RuntimeError(error.decode(errors='replace'))
    output.mkdir(parents=True, exist_ok=True)
    canvas.save(output/'contact.png')
    report = {'video': str(video), 'requested_fps': fps, 'sample_fps': cadence,
              'source_fps': source_fps, 'frames': frames, 'source_stream': stream,
              'change_percentiles_10_50_90': np.percentile(changes, [10, 50, 90]).tolist() if changes else [],
              'note': 'Frame change is not a measure of aesthetic quality or audiovisual synchronization.'}
    (output/'review.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return {'contact': str(output/'contact.png'), 'frames': len(frames),
            'cadence_ms': 1000/cadence, 'changes': report['change_percentiles_10_50_90']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('video', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--start', type=float, default=6.)
    parser.add_argument('--duration', type=float, default=10.)
    parser.add_argument('--fps', type=float, default=10.)
    args = parser.parse_args()
    print(json.dumps(review(args.video, args.output, args.start, args.duration, args.fps)))
