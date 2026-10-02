defmodule DevcontrolI2c do
  @moduledoc """
  I2C bus control 
  1. open i2c bus with bus_name
  2. search devices addresss on the bus 
  3. starts all devices handler on table when address are found
  4. starts lock and unlock 
  ```mermaid
  stateDiagram-v2
  [*] --> bus_open()
  bus_open() --> get_addlist()
  bus_open() --> start_device() : exists addressses
  get_addlist() --> start_device()
  start_device() --> wait_req()
  wait_req() --> wait_unlock() : lock
  wait_unlock() --> wait_req() : unlock
  ```

  """
  use FsmDiagram

  alias DevcontrolI2c.DevTable 

  @type bus_name() :: String.t()

  @spec start(bus_name()) :: {:ok, pid()}
  def start(bus_name) do
    {:ok, _pid} = fsm_start(bus_name, :bus_open, {bus_name})
  end

  def moveto(func, argv) do
    func = Function.capture(__MODULE__, func, 1)
    update_fnc(func, argv)
  end

  @doc false
  # i2c bus open by bus_name 
  #
  @spec bus_open({bus_name()}) :: none()
  def bus_open({bus_name}) do
    #Logger.debug("bus_open(#{bus_name})")
    {result, bus}  = Circuits.I2C.open(bus_name)
    if result == :ok do
      addlist = DevTable.get_bussadds(bus_name)
      if addlist == [] or addlist == nil do
        moveto(:get_addlist, {bus_name, bus})
      else
        moveto(:start_device, {bus_name, bus, addlist})
      end
    else
      Process.sleep(1000) 
      bus_open(bus_name)
    end
  end
  @doc false
  # search addresses on i2c bus
  @spec get_addlist({bus_name(), Bus.t()}) :: none()
  def get_addlist({bus_name, bus} = argv) do
    soft_reset(bus)
    Process.sleep(200)      # wait 200ms of reset devices
    addlist = Circuits.I2C.detect_devices(bus)
    if Enum.empty?(addlist) do
      Process.sleep(3000)
      get_addlist(argv)
    else
      moveto(:start_device, {bus_name, bus, addlist})
    end
  end

  @doc false
  # activate each devices as  
  @spec start_device({bus_name(), Bus.t(), list()}) :: none()
  def start_device({bus_name, bus, addlist}) do
    put_vars(addlist)
    Enum.each(addlist, fn add -> 
        hdmod = DevTable.get_module({bus_name, add})
        if is_atom(hdmod) and not is_nil(hdmod) do
          activate_device(hdmod, {bus_name, add}, bus)
        end
      end)
    moveto(:wait_req, {bus_name, bus}) 
  end 

  @doc false
  # wait_req() - 
  #   wait for msg and do with each msg
  #   `{:lock, from. msg}` 
  @spec wait_req({bus_name(), Bus.t()}) :: none()
  def wait_req({bus_name, bus}) do
    receive do
      {:lock, from, msg, arg} -> 
          send(from, {:lock, self(), msg, arg})
          moveto(:wait_unlock, {bus_name, bus, from})
    end
  end

  @doc false
  #exclusive control for i2c bus by `lock` msg. release bus
  #by `unlock` msg and return back to wairt_req()
  @spec wait_unlock({bus_name(), Bus.t(), pid()}) :: none()
  def wait_unlock({bus_name, bus, waitpid}) do
    receive do
      {:unlock, ^waitpid, msg1, msg2} -> 
          send(waitpid, {:unlock, self(), msg1, msg2})
          moveto(:wait_req, {bus_name, bus})
    end
  end
  @doc false
  # start each device by `start({bus_name, address}, bus)` 
  # then wait until each device initialization ends by receiving :init_end msg.
  defp activate_device(mod, {bus_name, add}, bus) do
    mod.start({bus_name, add}, bus)   # start_link() is not supported
    receive do
      {:init_end, _from, ^add, state} ->
          Logger.debug("#{bus_name} #{add} state:#{state} initialized")
      after 100 -> :timeout
    end
  end
  @doc false
  # General call address commands
  # 0x06 - soft_reset() Reset/Write Programming Address
  # 0x04 - Write Programming Address
  # 0x00 - No Operation
  # 0x02 - Device ID
  @spec soft_reset(Bus.t()) :: none()
  defp soft_reset(bus) do
    Circuits.I2C.write(bus, 0x00, <<0x06>>)
    Process.sleep(100)
  end

end
