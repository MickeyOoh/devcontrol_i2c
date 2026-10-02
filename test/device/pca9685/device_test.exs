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

  test "set_ledpat validity check" do
    assert(Device.set_ledpat(0, 0) == <<0, 0, 0, 16>>)
    assert(Device.set_ledpat(2047, -20) == <<255, 7, 0, 0>>)
    assert(Device.set_ledpat(-1, 2047) == <<0, 0, 255, 7>>)
    assert(Device.set_ledpat(2047, 0x1001) == <<0, 0, 0, 16>>)
    assert(Device.set_ledpat(0x3000, 2047) == <<0, 16, 0, 0>>)
    assert(Device.set_ledpat(0, 256) == <<0, 0, 0, 1>>)
  end

  test "get_reginfo() check" do
    assert_raise(ArgumentError, fn -> Device.get_reginfo(:mode1) end)
    reg_map = Device.get_regallinfo()
    regmap_values = Device.get_regallinfo(:values)
    assert(Map.values(reg_map) == regmap_values)
    regmap_keys = Device.get_regallinfo(:keys)
    assert(Map.keys(reg_map) == regmap_keys)
    Enum.with_index(regmap_keys, 
          fn key, index ->
            assert(Device.get_reginfo(key) == Enum.at(regmap_values, index))     
          end
    )
  end

end
