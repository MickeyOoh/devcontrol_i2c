defmodule DevcontrolI2c.DevTable do

  @type address() :: integer()
  @type fsm_id() :: {String.t(), address()} | String.t()
  @type dev_name() :: fsm_id()
  #
  #@drv_i2c_1 [ # {dev_name, handler, dev_table}
  #  {{"i2c-1", 0x40}, DevcontrolI2c.PCA9685.Handle, &DevcontrolI2c.PCA9685tbl.table1/0},
  #]
  #@drv_i2c_2 [ # {dev_name, handler, dev_table}
  #  {{"i2c-2", 0x40}, DevcontrolI2c.PCA9685.Handle, &DevcontrolI2c.PCA9685tbl.table2/0},
  #]
  #@drivers [ {"i2c-1", @drv_i2c_1}, {"i2c-2", @drv_i2c_2} ]

  @tbl_devices [
    # {dev_name, handler, dev_table}
    { {"i2c-1", 0x40}, DevcontrolI2c.PCA9685.Handle, &DevcontrolI2c.PCA9685tbl.table1/0},
    { {"i2c-2", 0x40}, DevcontrolI2c.PCA9685.Handle, &DevcontrolI2c.PCA9685tbl.table2/0},
  ]
  def tbl_devices(), do: @tbl_devices

  @spec get_table(dev_name()) :: {dev_name, fun(), fun()} | :error 
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

  @spec get_handler(d_name :: fsm_id()) :: module() | nil
  def get_handler(d_name) do
    return = get_table(d_name)
    case return do
      {_d_name, handler, _fnctable} -> handler
      _ -> nil 
    end
  end
end
