"""Frame-exact offline render with bounded RAM and FFmpeg backpressure.

Godot sends RGB frames over localhost, one frame at a time. The encoder ACKs
only after accepting the entire frame. No PNG mountain or dropped-frame queue.
"""
import argparse
import json
import math
import os
from pathlib import Path
import socket
import struct
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
GODOT = ROOT/'.tools/godot/Godot_v4.7.2-stable_win64.exe'


def app_command(project):
    project = Path(project).resolve()
    return [str(GODOT), '--path', str(HERE/'app'), '--', f'--project={project}',
            f'--asset-root={ROOT / "terrarium/data"}',
            f'--ensemble-map={project.parent / "ensemble_map_u8.bin"}']


def receive_exact(connection, count):
    data = bytearray(count)
    view = memoryview(data)
    offset = 0
    while offset<count:
        read = connection.recv_into(view[offset:])
        if not read: raise ConnectionError('Renderer closed before all frames were received')
        offset += read
    return data


def publish_render(temp, output):
    """Keep a finished render when a Windows player locks the previous video."""
    try:
        os.replace(temp, output)
        return output
    except PermissionError:
        if not output.is_file():
            raise
        # A fresh name also leaves the currently playing version untouched.
        alternate = output.with_name(f'{output.stem}-new-{time.time_ns()}{output.suffix}')
        os.replace(temp, alternate)
        return alternate


def export(project, output, fps=60, width=1920, height=1080, brain=False):
    project, output = Path(project).resolve(), Path(output).resolve()
    if not 1 <= fps <= 120 or width%2 or height%2 or min(width, height)<64:
        raise ValueError('Use 1–120 FPS and even dimensions >=64')
    manifest = json.loads(project.read_text(encoding='utf-8'))
    if not manifest.get('complete'): raise ValueError('Process the audio first')
    frames = math.ceil(manifest['duration']*fps)
    output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive temporary target; existing output is not touched until success.
    temp = output.with_name(output.stem+f'.rendering-{os.getpid()}.mp4')
    log_path = project.parent/'export.log'
    render = encoder = None
    validated = False
    started = time.monotonic()
    try:
        with socket.socket() as server, log_path.open('w', encoding='utf-8') as log:
            server.bind(('127.0.0.1', 0)); server.listen(1); server.settimeout(1.)
            port = server.getsockname()[1]
            command = app_command(project)
            # A hidden process window is used by the studio. Godot renders an
            # offscreen-capable tiny native window, preserving full viewport size.
            command[1:1] = ['--position', '0,0']
            command += [f'--export-port={port}', f'--export-fps={fps}',
                        f'--export-width={width}', f'--export-height={height}']
            if brain: command.append('--export-brain')
            render = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                      creationflags=0x08000000)
            deadline = time.monotonic()+90.
            while True:
                try:
                    connection, _ = server.accept(); break
                except socket.timeout:
                    if render.poll() is not None: raise RuntimeError(f'Renderer failed; see {log_path}')
                    if time.monotonic()>deadline: raise TimeoutError('Renderer startup timed out')
            with connection:
                connection.settimeout(90.)
                encoder = subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','error','-y',
                    '-f','rawvideo','-pix_fmt','rgb24','-s',f'{width}x{height}', '-r',str(fps),
                    '-i','pipe:0','-i',str(project.parent/'audio.wav'),
                    '-map','0:v:0','-map','1:a:0','-c:v','libx264','-preset','medium','-crf','18',
                    '-pix_fmt','yuv420p','-c:a','aac','-b:a','320k',
                    # Cover the final partial frame of the soundtrack. Using
                    # the unrounded audio duration here can discard a frame
                    # that the renderer has already delivered successfully.
                    '-t',str(frames/fps),'-movflags','+faststart',str(temp)],
                    stdin=subprocess.PIPE, stdout=log, stderr=log, creationflags=0x08000000)
                for i in range(frames):
                    count = struct.unpack('<I', receive_exact(connection,4))[0]
                    if count != width*height*3: raise ValueError(f'Unexpected frame size {count}')
                    frame = receive_exact(connection,count)
                    encoder.stdin.write(frame)
                    connection.sendall(b'K')
                    if i%30 == 0:
                        print(json.dumps({'stage':'render video','progress':(i+1)/frames,
                                          'frame':i+1,'frames':frames,'elapsed':time.monotonic()-started}), flush=True)
                encoder.stdin.close()
                if encoder.wait(timeout=120): raise RuntimeError(f'Encoder failed; see {log_path}')
                if render.wait(timeout=15): raise RuntimeError(f'Renderer failed; see {log_path}')
        diagnostic = log_path.read_text(encoding='utf-8', errors='replace')
        if 'SCRIPT ERROR:' in diagnostic or '\nERROR:' in diagnostic:
            raise RuntimeError(f'Render contains engine errors; see {log_path}')
        encoded_frames = int(subprocess.check_output([
            'ffprobe', '-v', 'error', '-select_streams', 'v:0',
            '-show_entries', 'stream=nb_frames',
            '-of', 'default=noprint_wrappers=1:nokey=1', str(temp)],
            text=True, creationflags=0x08000000).strip())
        if encoded_frames != frames:
            raise RuntimeError(f'Expected {frames} frames, encoded {encoded_frames}; see {log_path}')
        validated = True
        output = publish_render(temp, output)
        print(json.dumps({'stage':'exported','progress':1.,'video':str(output)}), flush=True)
        return output
    finally:
        for process in (render, encoder):
            if process is not None and process.poll() is None:
                process.terminate()
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
        # Partial/invalid frames can be discarded; a validated finished movie
        # must survive even if the filesystem cannot publish its final name.
        if not validated:
            temp.unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--fps',type=int,default=60)
    parser.add_argument('--width',type=int,default=1920)
    parser.add_argument('--height',type=int,default=1080)
    parser.add_argument('--brain',action='store_true')
    args=parser.parse_args()
    export(args.project,args.output,args.fps,args.width,args.height,args.brain)
