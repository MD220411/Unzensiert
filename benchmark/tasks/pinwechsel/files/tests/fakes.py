"""A stand-in for RPi.GPIO that records what the code does."""


class FakeGPIO:
    """Records setup and output calls; input() returns the levels in `levels`."""

    BCM, OUT, IN, HIGH, LOW, PUD_UP, PUD_DOWN = "BCM", "OUT", "IN", 1, 0, "PUD_UP", "PUD_DOWN"

    def __init__(self, levels=None):
        self.levels = dict(levels or {})
        self.modes = {}
        self.pulls = {}
        self.outputs = []

    def setmode(self, mode):
        self.mode = mode

    def setup(self, pin, mode, initial=None, pull_up_down=None):
        self.modes[pin] = mode
        self.pulls[pin] = pull_up_down

    def output(self, pin, value):
        if self.modes.get(pin) != self.OUT:
            raise RuntimeError(f"GPIO{pin} is not set up as output")
        self.outputs.append((pin, value))

    def input(self, pin):
        if self.modes.get(pin) != self.IN:
            raise RuntimeError(f"GPIO{pin} is not set up as input")
        return self.levels.get(pin, self.HIGH)
