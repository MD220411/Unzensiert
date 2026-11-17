"""I2C bus interface of the climate logger and the error the sensor drivers raise."""


class SensorError(Exception):
    """The sensor reports a fault or delivers no valid data."""


class Bus:
    """Interface of an I2C bus. Real buses and the test doubles implement it.

    A device that does not answer (no ACK) raises OSError, as smbus2 does.
    """

    def read(self, address, register, length):
        """Read `length` bytes starting at `register` of the device at `address`."""
        raise NotImplementedError

    def write(self, address, register, data):
        """Write the bytes `data` starting at `register` of the device at `address`."""
        raise NotImplementedError
