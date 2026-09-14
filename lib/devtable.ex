defmodule DevcontrolI2c.DevTable do

  @type address() :: integer()
  @type fsm_id() :: {String.t(), address()} | String.t()
  @type dev_name() :: fsm_id()

  alias DevcontrolI2c.PCA9685 

  @tbl_devices [
    # {dev_name, start({bus_name, add}, bus), dev_table}
    { "i2c-1", DevcontrolI2c, nil}, 
    { "i2c-2", DevcontrolI2c, :table2_adds}, 
    { {"i2c-1", 0x40}, PCA9685.Handle, :table1},
    { {"i2c-2", 0x40}, PCA9685.Handle, :table2}, 
  ]
  def tbl_devices(), do: @tbl_devices

  #def tbl1_addresses() do
  #  [0x40]
  #end
  def tbl2_addresses() do
    [0x40]
  end
  @spec get_table(dev_name()) :: {dev_name, fun(), fun()} | :error 
  def get_devtable(d_name), do: get_devtable(@tbl_devices, d_name)
  def get_devtable([], _d_name), do: nil
  def get_devtable([devtable | t], d_name) do
    {dev_name, _module, _chtable} = devtable
    if dev_name == d_name do 
      devtable
    else 
      get_devtable(t, d_name)
    end
  end

  @spec get_module(d_name :: fsm_id()) :: module() | nil
  def get_module(d_name) do
    return = get_devtable(d_name)
    case return do
      {_d_name, module, _fnctable} -> module
      _ -> nil 
    end
  end

  @spec get_table(d_name :: fsm_id()) :: module() | nil
  def get_table(d_name) do
    return = get_devtable(d_name)
    case return do
      {_d_name, module, fnctable} when not is_nil(fnctable) -> 
              func = Function.capture(module, fnctable, 0)
              func.()
      _ -> nil 
    end
  end
end
