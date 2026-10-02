defmodule DevcontrolI2c.DevTable do
  @moduledoc """
    Table of i2c devices to refer from each device-handler  
    `@tbl_devices` is all table of this module.  
    data structure is  
      {dev_name : device name
       module : module of device  
       dev_table : function of getting table  
      }  

  """
  @type address() :: integer()
  @type module_name() :: {String.t(), address()} | String.t()
  @type dev_name() :: module_name()

  alias DevcontrolI2c.PCA9685 

  @tbl_busses [
    { "i2c-0", nil}, 
    { "i2c-1", []}, 
    { "i2c-2", [0x40]}, 
  ]
  @tbl_devices [
    # {dev_name, start({bus_name, add}, bus), dev_table}
    #{ {"i2c-1", 0x40}, PCA9685.Handle, :table1},
    #{ {"i2c-2", 0x40}, PCA9685.Handle, :table2}, 
    { {"i2c-0", 0x40}, PCA9685.Handle, nil},
    { {"i2c-1", 0x40}, PCA9685.Handle, nil},
    { {"i2c-2", 0x40}, PCA9685.Handle, nil}, 
  ]
  def tbl_busses(), do: @tbl_busses
  def tbl_devices(), do: @tbl_devices
  @doc """
    
  """
  def get_bussadds(bus_name) do
    List.first(for {^bus_name, addlist} <- @tbl_busses, do: addlist)
  end
  @doc """
    get a device whole table  
  """
  @spec get_table(dev_name()) :: {dev_name(), module(), fun()} | nil 
  def get_devtable(dev_name), do: get_devtable(@tbl_devices, dev_name)
  def get_devtable([], _dev_name), do: nil
  def get_devtable([devtable | t], dev_name) do
    {d_name, _module, _table} = devtable
    if dev_name == d_name do 
      devtable
    else 
      get_devtable(t, dev_name)
    end
  end

  @spec get_module(dev_name :: dev_name()) :: module() | nil
  def get_module(dev_name) do
    return = get_devtable(dev_name)
    case return do
      {_d_name, module, _fnctable} -> module
      _ -> nil 
    end
  end

  @spec get_table(dev_name :: dev_name()) :: module() | nil
  def get_table(dev_name) do
    return = get_devtable(dev_name)
    case return do
      {_dev_name, module, fnctable} when not is_nil(fnctable) -> 
              func = Function.capture(module, fnctable, 0)
              func.()
      _ -> nil 
    end
  end
end
