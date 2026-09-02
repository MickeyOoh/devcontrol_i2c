defmodule DevcontrolI2c.DevTable do


  #@tbl_pca9685_1 [
  #  #ledno => {type, default, name}
  #    {:duty, 0, "frontleft_forward"},
  #    {:duty, 0, "frontleft_backward"},
  #    {:duty, 0, "rearleft_backward"},
  #    {:duty, 0, "rearleft_forward"},
  #    {:duty, 0, "rearright_forward"},
  #    {:duty, 0, "rearright_backward"},
  #    {:duty, 0, "frontright_forward"},
  #    {:duty, 0, "frontright_backword"},
  #    {:servo, 50, "swing left right"},
  #    {:servo, 50, "swing up down"},
  #    {:none, 0, ""},
  #    {:none, 0, ""},
  #    {:none, 0, ""},
  #    {:none, 0, ""},
  #    {:none, 0, ""},
  #    {:none, 0, ""},
  #  ]
  #@tbl_pca9685_2 []

  #def tbl_pca9685_1(), do: @tbl_pca9685_1
  #def tbl_pca9685_2(), do: @tbl_pca9685_2

  @tbl_devices [
    # {dev_name, handler, dev_table}
    { {"i2c-1", 0x40}, DevcontrolI2c.PCA9685.Handle, &DevcontrolI2c.PCA9685tbl.table1/0},
    { {"i2c-2", 0x40}, DevcontrolI2c.PCA9685.Handle, &DevcontrolI2c.PCA9685tbl.table2/0},
  ]
  def tbl_devices(), do: @tbl_devices

  def get_table(d_name), do: get_table(@tbl_devices, d_name)
  def get_table([], _d_name), do: :error
  def get_table([table | t], d_name) do
    {dev_name, _handler, _chtable} = table
    if dev_name == d_name do 
      table
    else 
      get_table(t, d_name)
    end
  end

end
