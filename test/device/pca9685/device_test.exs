defmodule DevcontrolI2c.PCA9685.DeviceTest do
  use ExUnit.Case
  doctest DevcontrolI2c.PCA9685.Device, import: true
  alias DevcontrolI2c.PCA9685.Device
  
  test "read reg" do
    reg = Device.mode1_sleep()
    assert(Keyword.get_values(reg, :sleep) == [1])
    reg = Device.mode1_restart()
    assert(Keyword.get_values(reg, :sleep) == [0])
    assert(Keyword.get_values(reg, :restart) == [1])
    reg = Device.mode2_data()
    keys = Keyword.keys(reg)
    assert( keys == [:rev, :invrt, :och, :outdrv, :outne])
    kv_data = Device.d_sysinfo()
    prescale = Device.get_prescale(kv_data[:clock], kv_data[:cycle])
    assert( prescale == Device.prescale_data() )
  end

end
