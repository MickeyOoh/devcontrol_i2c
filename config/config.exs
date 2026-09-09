import Config

config :circuits_i2c, default_backend: CircuitsSim.I2C.Backend
config :circuits_sim,
  config: [
    {CircuitsSim.Device.PCA9685, bus_name: "i2c-1", address: 0x40},
    {CircuitsSim.Device.PCA9685, bus_name: "i2c-2", address: 0x40},
  ]
