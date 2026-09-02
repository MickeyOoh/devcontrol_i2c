defmodule DevcontrolI2c.PCA9685.Handle do
  @moduledoc """
  PCA9685 Handler State Machine

  ```mermaid
  stateDiagram-v2
  [*] --> init()
  init() --> intial_chip()
  intial_chip() --> restart()
  restart() --> wait_req()
  wait_req() --> ledout() : ledout
  ledout() --> wait_req()
  wait_req() --> multi_ledout() : multi_led
  multi_ledout() --> wait_req()
  ```

  """
  use FsmDiagram
  require Logger
  alias DevcontrolI2c.PCA9685.Device
  alias DevcontrolI2c.PCA9685tbl, as: Table

  @type bus_name() :: String.t()
  @type address() :: integer()

  @spec start({bus_name(), address()}, Bus.t()) :: {:ok, pid}
  def start({bus_name, address} = fsm_id,  bus) do
      fsm_start(fsm_id, :init, {{bus_name, address}, bus})
  end

  defp move_to(func, argv) do
    #lists = Map.keys(@state_table)
    #if func in lists do
      func = Function.capture(__MODULE__, func, 1)
      update_fnc(func, argv)
    #else
    #  false
    #end
  end
  
  def init({{_bus_name, _address} = fsm_id, bus} = argv) do
    # read sleep bit on, if on set prescale, off: set sleep first
    put_vars({fsm_id, bus})  # set bus and address for funcs of device
    move_to(:initial_chip, argv)
  end
  
  def initial_chip({{_bus_name, address}, bus} = argv) do
    # set sleep mode for prescale
    dt_pat = Device.mode1_sleep()     # default value included with sleep 
    data = Device.set_reg(:regmode1, dt_pat)
    Circuits.I2C.write(bus, address, data)

    dt_pat = Device.mode2_data()      # default
    data = Device.set_reg(:regmode2, dt_pat)
    Circuits.I2C.write(bus, address, data)

    # 0 clear all led data
    {regno, _num, _format, _msg} = Device.get_reginfo(:regled_all)
    data = <<regno::8>> <> Device.set_ledpat(0, 0x1000)
    Circuits.I2C.write(bus, address, data)

    # set prescale 
    prescale = Device.prescale_data()
    {regno, _num, _format, _msg} = Device.get_reginfo(:regprescale)
    data = <<regno::8, prescale::8>>
    Circuits.I2C.write(bus, address, data)
    # write 
    move_to(:restart, argv)
  end 

  def restart({{_bus_name, address}, bus} = argv) do
    dt_pat = Device.mode1_restart()
    data = Device.set_reg(:regmode1, dt_pat)
    Circuits.I2C.write(bus, address, data)
    Process.sleep(10)
    move_to(:wait_req, argv)
  end
  
  @req_apis """
  interface of message to request this module
  send(pid, {eve, from, ch_no, data}) 
  pid: FsmDiagram.get_fsmpid({bus_name, 0x40})
  from: self() 
  ch_no: 0-15 led number
  eve          data
  #:set_reg    regpattern
  :ledout      percentage(0-100%)
  :multi_led   [percentage1, ...]
  #:read_reg    count
  """
  def api_format() do
    @req_apis
  end 

  @spec wait_req({{bus_name(), integer()}, Bus.t()}) :: none()
  def wait_req({ {bus_name, address} = fsmid, bus} = argv) do
    receive do
      {eve, from, ch_no, data} -> 
      case eve do
          #:set_reg ->  
          #  result = write_reg(regno, data) 
          #  send(from, {result, :setting})
        :ledout ->
          validity_check(ch_no, data)
          {kind, _, _msg} = Table.get_chtable(fsmid, ch_no)
          data = setbyperc(kind, ch_no, data)
          Circuits.I2C.write(bus, address, <<ch_no::8>> <> data)

         # move_to(:ledout, {ch_no, data})
        :multi_led -> 
          validity_check(ch_no, data)
          data = Enum.reduce(data, <<>>, fn perc, acc -> 
            acc <> setbyperc(:duty, ch_no, data)
            end)
          Circuits.I2C.write(bus, address, <<ch_no::8>> <> data)
        true -> 
          send(from, {:error, :unknown_command})
          wait_req(argv)
      end
    end
  end

  @spec setbyperc(atom, integer(), integer()) :: bitstring()
  def setbyperc(:duty, ch_no, percentage) do
    {ontime, offtime} = Device.percto_duty(ch_no, percentage)  # ch_no for shift pulse
    Device.set_ledpat(ontime, offtime)
  end
  def setbyperc(:servo, ch_no, percentage) do
    {ontime, offtime} = Device.percto_servo(ch_no, percentage)  # ch_no for shift pulse
    Device.set_ledpat(ontime, offtime)
  end
  def setbyperc(_kind, _ch_no, _data) do
    Device.set_ledpat(0, 0x1000)
  end

  defp validity_check( ch_no, data) when is_integer(data) do
    if 0 <= ch_no and ch_no < 16, do: :ok, else: :error
  end

  #def ledout({ch_no, {ontime, offtime}}) do
  #  loc_mtx()
  #  data = Device.led_output(ch_no, ontime, offtime) 
  #  {{_bus_name, address}, bus} = get_elm(:vars)
  #  Circuits.I2C.write(bus, address, data)
  #  move_to(:wait_req, [])
  #  unl_mtx()
  #end

  #def multi_ledout({bus, address, ch_no, datalist}) do
  #  :ok = loc_mtx()
  #  regno = 6 + ch_no * 4
  #  w_dt = Enum.reduce(datalist, <<regno::8>>, 
  #    fn {ontime, offtime}, acc ->
  #      w_dt = Device.set_ledpat(ontime, offtime)
  #      acc <> w_dt
  #    end)
  #  Device.led_out(bus, address, w_dt)
  #  move_to(:wait_req, {bus, address})
  #  :ok = unl_mtx()
  #end

  defp loc_mtx() do
    {:ok, {bus_name, _}} = self_fsmid() 
    pid = get_fsmpid(bus_name)    # parent bus name
    send(pid, {:lock, self(), "locking"})
    receive do
      {:lock, ^pid, _msg} -> :ok
    end
  end

  defp unl_mtx() do
    {:ok, {bus_name, _}} = self_fsmid() 
    pid = get_fsmpid(bus_name)    # parent bus name
    send(pid, {:unlock, self(), "unlocking"})
    receive do
      {:unlock, ^pid, _msg} -> :ok
    end
  end
  
  @spec read_reg(atom()) :: keyword()
  def read_reg(regname) do
      {regno, num, format, _msg} = Device.get_reginfo(regname)
      w_dt = <<regno::8>>
      {{_bus_name, address}, bus} = get_elm(:vars)
      {:ok, data} = Circuits.I2C.write_read(bus, address, w_dt, num)
      Device.parse(data, format)
  end

end
