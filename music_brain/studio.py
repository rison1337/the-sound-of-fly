"""Modern file-only Music Studio front end."""
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import tkinter as tk
from tkinter import filedialog, messagebox

import customtkinter as ctk

from instance_lock import acquire_instance

HERE = Path(__file__).resolve().parent
PYTHON = HERE.parent / ".venv/Scripts/python.exe"


class Studio:
    BG = "#0b1019"
    CARD = "#121a27"
    CARD_2 = "#172235"
    TEXT = "#edf3ff"
    MUTED = "#94a5c4"
    ACCENT = "#6d8cff"

    def __init__(self, root: ctk.CTk):
        self.root = root
        self.worker = None
        self.messages = queue.SimpleQueue()
        self.project = None
        self.pending_project = None
        self.cancelled = False
        root.title("Droffel / Music Studio")
        root.geometry("900x760")
        root.minsize(780, 650)
        root.configure(fg_color=self.BG)
        self.source = tk.StringVar()
        self.start = tk.StringVar(value="0")
        self.duration = tk.StringVar(value="0")
        self.resolution = tk.StringVar(value="3840 x 2160")
        self.fps = tk.StringVar(value="60")
        self.with_brain = tk.BooleanVar(value=False)
        self.status = tk.StringVar(value="Choose music to begin")
        self._make_theme()
        self._build()
        self.restore()
        root.after(100, self.poll)
        root.protocol("WM_DELETE_WINDOW", self.close)

    def _make_theme(self):
        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("blue")

    def _label(self, parent, text, size=13, color=None, **kwargs):
        return ctk.CTkLabel(parent, text=text, font=("Segoe UI", size), text_color=color or self.TEXT, **kwargs)

    def _button(self, parent, text, command, primary=False, **kwargs):
        return ctk.CTkButton(parent, text=text, command=command, height=38, corner_radius=10,
                             fg_color=self.ACCENT if primary else self.CARD_2,
                             hover_color="#819bff" if primary else "#22324d",
                             text_color="#ffffff", font=("Segoe UI", 12, "bold"), **kwargs)

    def _build(self):
        shell = ctk.CTkFrame(self.root, fg_color=self.BG)
        shell.pack(fill="both", expand=True, padx=28, pady=12)
        header = ctk.CTkFrame(shell, fg_color="transparent")
        header.pack(fill="x", pady=(0, 14))
        self._label(header, "DROFFEL", 28).pack(anchor="w")
        self._label(header, "MUSIC STUDIO", 14, self.ACCENT).pack(anchor="w", pady=(1, 0))
        self._label(header, "Audio file  /  fixed fly brain  /  motion design", 12, self.MUTED).pack(anchor="w", pady=(8, 0))

        source_card = ctk.CTkFrame(shell, fg_color=self.CARD, corner_radius=16)
        source_card.pack(fill="x", pady=(0, 14))
        self._label(source_card, "SOURCE AUDIO", 11, self.MUTED).pack(anchor="w", padx=18, pady=(12, 4))
        source_row = ctk.CTkFrame(source_card, fg_color="transparent")
        source_row.pack(fill="x", padx=18, pady=(0, 12))
        ctk.CTkEntry(source_row, textvariable=self.source, height=38, corner_radius=9,
                     fg_color="#0e1623", border_color="#2c3c57", text_color=self.TEXT).pack(side="left", fill="x", expand=True)
        self._button(source_row, "Choose audio", self.choose).pack(side="left", padx=(10, 0))

        timing = ctk.CTkFrame(shell, fg_color=self.CARD, corner_radius=16)
        timing.pack(fill="x", pady=(0, 14))
        self._label(timing, "TIMING", 11, self.MUTED).pack(anchor="w", padx=18, pady=(12, 5))
        timing_row = ctk.CTkFrame(timing, fg_color="transparent")
        timing_row.pack(fill="x", padx=18, pady=(0, 12))
        self._label(timing_row, "Start", 12, self.MUTED).pack(side="left", padx=(0, 6))
        ctk.CTkEntry(timing_row, textvariable=self.start, width=74, height=38, corner_radius=9, fg_color="#0e1623").pack(side="left")
        self._label(timing_row, "Length", 12, self.MUTED).pack(side="left", padx=(14, 6))
        ctk.CTkEntry(timing_row, textvariable=self.duration, width=74, height=38, corner_radius=9, fg_color="#0e1623").pack(side="left")

        actions = ctk.CTkFrame(shell, fg_color="transparent")
        actions.pack(fill="x", pady=(0, 10))
        self.process_button = self._button(actions, "1  Process music", self.prepare, primary=True)
        self.process_button.pack(side="left")
        self.open_button = self._button(actions, "Open processed project", self.open_project)
        self.open_button.pack(side="left", padx=(10, 0))

        export_card = ctk.CTkFrame(shell, fg_color=self.CARD, corner_radius=16)
        export_card.pack(fill="x", pady=(0, 14))
        self._label(export_card, "VIDEO EXPORT", 11, self.MUTED).pack(anchor="w", padx=18, pady=(12, 6))
        export_row = ctk.CTkFrame(export_card, fg_color="transparent")
        export_row.pack(fill="x", padx=18, pady=(0, 8))
        ctk.CTkOptionMenu(export_row, variable=self.resolution,
            values=["1280 x 720", "1920 x 1080", "2560 x 1440", "3840 x 2160"],
            height=38, width=178, corner_radius=9, fg_color="#0e1623",
            button_color="#263a5c", button_hover_color="#38588b").pack(side="left")
        ctk.CTkOptionMenu(export_row, variable=self.fps, values=["30", "60"], height=38, width=84,
            corner_radius=9, fg_color="#0e1623", button_color="#263a5c", button_hover_color="#38588b").pack(side="left", padx=10)
        self.brain_check = ctk.CTkCheckBox(export_row, text="Brain overlay", variable=self.with_brain,
            height=38, corner_radius=7, border_color="#536887", hover_color="#819bff", fg_color=self.ACCENT)
        self.brain_check.pack(side="left", padx=(8, 0))
        self.export_button = self._button(export_card, "3  Export MP4 with audio", self.export, primary=True)
        self.export_button.configure(state="disabled")
        self.export_button.pack(anchor="w", padx=18, pady=(0, 12))

        progress_card = ctk.CTkFrame(shell, fg_color=self.CARD, corner_radius=16)
        progress_card.pack(fill="x", pady=(0, 14))
        self._label(progress_card, "JOB STATUS", 11, self.MUTED).pack(anchor="w", padx=18, pady=(12, 5))
        self.progress = ctk.CTkProgressBar(progress_card, height=10, corner_radius=5, fg_color="#0e1623", progress_color=self.ACCENT)
        self.progress.set(0)
        self.progress.pack(fill="x", padx=18, pady=(0, 6))
        self.status_label = self._label(progress_card, "Choose music to begin", 12, self.MUTED, anchor="w", justify="left", wraplength=800)
        self.status_label.configure(textvariable=self.status)
        self.status_label.pack(fill="x", padx=18, pady=(0, 10))

        footer = ctk.CTkFrame(shell, fg_color="transparent")
        footer.pack(fill="x")
        self.cancel_button = self._button(footer, "Cancel job", self.cancel)
        self.cancel_button.configure(state="disabled", fg_color="#1b2535")
        self.cancel_button.pack(side="left")
        self._button(footer, "Open logs", lambda: os.startfile(HERE / "logs")).pack(side="left", padx=10)
        (HERE / "logs").mkdir(exist_ok=True)

    def choose(self):
        path = filedialog.askopenfilename(title="Choose music", filetypes=[("Audio / video", "*.wav *.mp3 *.flac *.ogg *.m4a *.aac *.mp4 *.webm"), ("All files", "*.*")])
        if path:
            self.source.set(path)

    def restore(self):
        try:
            data = json.loads((HERE / "runtime/studio.json").read_text())
            self.source.set(data.get("source", ""))
            if data.get("project"):
                self.set_project(Path(data["project"]))
        except (OSError, ValueError, KeyError):
            pass

    def set_project(self, path):
        data = json.loads(path.read_text(encoding="utf-8"))
        if not data.get("complete"):
            raise ValueError("Project is incomplete")
        if data.get("voice_readout") != "connectome_downstream_calibrated_2_3_hop" or not data.get("voice_timing_calibrated", False):
            raise ValueError("Reprocess this music to calibrate downstream timing")
        self.project = path
        self.export_button.configure(state="normal")
        self.status.set(f"Ready  ·  {data['source_name']}  ·  {data['duration']:.1f} s")
        (HERE / "runtime").mkdir(exist_ok=True)
        (HERE / "runtime/studio.json").write_text(json.dumps({"source": self.source.get(), "project": str(path)}), encoding="utf-8")

    def open_project(self):
        path = filedialog.askopenfilename(title="Open processed project", initialdir=HERE / "runtime/projects", filetypes=[("Music Brain project", "project.json")])
        if path:
            try:
                self.set_project(Path(path))
            except (OSError, ValueError, KeyError) as exc:
                messagebox.showerror("Project", str(exc))

    def prepare(self):
        try:
            source = Path(self.source.get())
            start, duration = float(self.start.get()), float(self.duration.get())
            if not source.is_file():
                raise ValueError("Choose an existing audio file")
            if start < 0 or duration < 0:
                raise ValueError("Start and length must be nonnegative")
            self.run([str(PYTHON), str(HERE / "prepare.py"), str(source), "--start", str(start), "--duration", str(duration), "--separation", "demucs"])
        except (ValueError, OSError) as exc:
            messagebox.showerror("Process music", str(exc))

    def export(self):
        if not self.project:
            return
        destination = filedialog.asksaveasfilename(title="Export video", defaultextension=".mp4", filetypes=[("MP4 video", "*.mp4")])
        if not destination:
            return
        width, height = [x.strip() for x in self.resolution.get().split("x")]
        command = [str(PYTHON), str(HERE / "export_video.py"), str(self.project), destination, "--fps", self.fps.get(), "--width", width, "--height", height]
        if self.with_brain.get():
            command.append("--brain")
        self.run(command)

    def run(self, command):
        if self.worker:
            return
        self.cancelled = False
        self.pending_project = None
        self.progress.set(0)
        env = os.environ.copy()
        env.update(PYTHONUTF8="1", PYTHONUNBUFFERED="1")
        self.worker = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", env=env, creationflags=0x08000000)
        for button in (self.process_button, self.open_button, self.export_button):
            button.configure(state="disabled")
        self.cancel_button.configure(state="normal")
        self.status.set("Starting…")

        def read(process):
            with (HERE / "logs/studio_job.log").open("w", encoding="utf-8") as log:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    try:
                        self.messages.put(json.loads(line))
                    except ValueError:
                        pass
            self.messages.put({"exit": process.wait()})

        threading.Thread(target=read, args=(self.worker,), daemon=True).start()

    def poll(self):
        while not self.messages.empty():
            event = self.messages.get()
            if "exit" in event:
                self.worker = None
                self.cancel_button.configure(state="disabled")
                self.process_button.configure(state="normal")
                if event["exit"] and not self.cancelled:
                    self.status.set("Job failed · see Open logs")
                    messagebox.showerror("Music Studio", "Processing failed. Open logs for details.")
                if self.pending_project and not self.cancelled:
                    self.set_project(Path(self.pending_project))
                elif self.project:
                    self.export_button.configure(state="normal")
            else:
                self.progress.set(event.get("progress", 0))
                self.status.set(f"{event.get('stage', 'Working')}  ·  {event.get('progress', 0) * 100:.0f}%")
                if event.get("project"):
                    self.pending_project = event["project"]
                if event.get("video"):
                    self.status.set("Exported  ·  " + event["video"])
        self.root.after(100, self.poll)

    def cancel(self):
        if self.worker and self.worker.poll() is None:
            subprocess.run(["taskkill", "/PID", str(self.worker.pid), "/T", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=0x08000000)
            self.cancelled = True
            self.status.set("Cancelled · completed projects remain available")

    def close(self):
        self.cancel()
        self.root.destroy()


def main():
    (HERE / "runtime").mkdir(exist_ok=True)
    lock = acquire_instance(HERE / "runtime/studio.lock")
    if lock is None:
        return
    try:
        root = ctk.CTk()
        Studio(root)
        root.mainloop()
    finally:
        lock.close()


if __name__ == "__main__":
    main()
