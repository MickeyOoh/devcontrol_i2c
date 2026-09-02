defmodule DevcontrolI2c.PCA9685.DeviceTest do
  use ExUnit.Case
  doctest DevcontrolI2c.PCA9685.Device
  alias DevcontrolI2c.PCA9685.Device

  
  test "read reg" do
    reg = Device.mode1_sleep()
    assert(Keyword.get_values(reg, :sleep) == [1])
    reg = Device.mode1_restart()
    assert(Keyword.get_values(reg, :sleep) == [0])
    assert(Keyword.get_values(reg, :restart) == [1])
    reg = Device.mode2_data()
  end
  
  test "set_reg() and get_reg() test" do
    
  end

end
