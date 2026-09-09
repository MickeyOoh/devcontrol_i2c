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
  get_addlist() --> start_device()
  start_device() --> wait_req()
  wait_req() --> wait_unlock() : lock
  wait_unlock() --> wait_req() : unlock
  ```

  """
  alias DevcontrolI2c.DevTable 

  use FsmDiagram
  @type bus_name() :: String.t()

  #@busadd_table  %{
  #  0x40 => {DevcontrolI2c.PCA9685.Handle, []},
  #}
  
  @spec start(bus_name()) :: {:ok, pid()}
  def start(bus_name) do
    {:ok, _pid} = fsm_start(bus_name, :bus_open, {bus_name})
  end

  def moveto(func, argv) do
    func = Function.capture(__MODULE__, func, 1)
    update_fnc(func, argv)
  end

  def bus_open({bus_name}) do
    Logger.debug("bus_open(#{bus_name})")
    ret  = Circuits.I2C.open(bus_name)
    case ret do
      {:ok, bus} -> moveto(:get_addlist, {bus_name, bus})
      {:error, _} ->  Process.sleep(1000)
                      Circuits.I2C.open({bus_name})
    end
  end

  def get_addlist({bus_name, bus} = argv) do
    soft_reset(bus)
    Process.sleep(200)      # wait 200ms of reset devices
    addlist = Circuits.I2C.detect_devices(bus)
    if Enum.empty?(addlist) do
      Process.sleep(3000)
      get_addlist(argv)
    else
      argv = {bus_name, bus, addlist}
      moveto(:start_device, argv)
    end
  end

  def start_device({bus_name, bus, addlist}) do
    Enum.each(addlist, fn add -> 
        hdmod = DevTable.get_handler({bus_name, add})
        if is_atom(hdmod) do
          activate_device(hdmod, {bus_name, add}, bus)
        end
      end)
    moveto(:wait_req, [])
  end 

  def wait_req(_argv) do
    receive do
      {:lock, from, msg} -> 
        #Logger.debug("lock #{inspect(from)}")
          send(from, {:lock, self(), msg})
          moveto(:wait_unlock, from)
    end
  end

  def wait_unlock(waitpid) do
    receive do
      {:unlock, ^waitpid, msg} -> 
        #Logger.debug("unlock: #{inspect(waitpid)}")
          send(waitpid, {:unlock, self(), msg})
          moveto(:wait_req, waitpid)
    end
  end

  defp activate_device(mod, {bus_name, add}, bus) do
    #MemPool.cre_mpf({ {{bus_name, add}, :device}, bus, %{}}) 
    mod.start({bus_name, add}, bus)
    receive do
      {:init_end, _from, state} ->
          Logger.debug("#{bus_name} #{add} state:#{state} initialized")
      after 100 -> :timeout
    end
  end

  @spec soft_reset(Bus.t()) :: none()
  defp soft_reset(bus) do
    Circuits.I2C.write(bus, 0x00, <<0x06>>)
    Process.sleep(200)
  end

end
