"""A bounded, binary GPU frame containing every neuron's measured model state."""
import numpy as np


class NeuralFrames:
    WIDTH = 512

    def __init__(self, count):
        self.count = count
        self.height = (count+self.WIDTH-1)//self.WIDTH
        self.counts = np.zeros(count, dtype=np.uint16)
        self.last_spike = np.full(count, -1000000, dtype=np.int64)
        self.pixels = np.zeros((self.height*self.WIDTH, 4), dtype=np.uint8)
        self.pixels[:, 3] = 255

    def observe(self, spikes, tick):
        self.counts += spikes
        self.last_spike[spikes] = tick

    def encode(self, rates, tick):
        # RG = uint16 rate in 1/32 Hz units; B = spikes since last frame;
        # A = age of the most recent spike, in 2 ms model steps (255 = older).
        quantized = np.clip(np.rint(np.nan_to_num(rates)*32.), 0, 65535).astype(np.uint16)
        self.pixels[:self.count, 0] = quantized & 255
        self.pixels[:self.count, 1] = quantized >> 8
        self.pixels[:self.count, 2] = np.minimum(self.counts, 255)
        self.pixels[:self.count, 3] = np.clip(tick-self.last_spike, 0, 255)
        data = self.pixels.tobytes()
        self.counts.fill(0)
        return data
