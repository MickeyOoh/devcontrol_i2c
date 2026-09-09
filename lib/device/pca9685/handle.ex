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
  alias DevcontrolI2c.PCA9685tbl

  @type bus_name() :: String.t()
  @type address() :: integer()
	@type percent() :: non_neg_integer()	# 0-100%
	@type counter() :: non_neg_integer()	# 0-4095, 4096 pulses
	@type channel() :: non_neg_integer()	# 0-15 ledn

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
  :ledout      percent(0-100%)
  :multi_led   [percent, ...]
  #:read_reg    count
  """
  def api_format() do
    @req_apis
  end 

  @spec wait_req({{bus_name(), integer()}, Bus.t()}) :: none()
  def wait_req({ {_bus_name, address} = fsm_id, bus}) do
    receive do
      {eve, from, ch_no, data} -> 
				case eve do
      	  :ledout ->
						ch_base = ch_no
      	    chdata_list = get_kind(fsm_id, ch_base, data)
      	    bindata = Enum.reduce(chdata_list, <<>>, fn {ch_no, kind, percent}, acc -> 
      	      acc <> setbyperc(kind, ch_no, percent)
      	      end)
						regno = 6 + ch_base * 4
      	    Circuits.I2C.write(bus, address, <<regno::8>> <> bindata)
            wait_req({fsm_id, bus})
					:set_counter ->
						bindata = ledoutto_bin(data)
						regno = 6 + ch_no * 4
      	    Circuits.I2C.write(bus, address, <<regno::8>> <> bindata)
					:get_counter ->
						regno = 6 + ch_no * 4
            {:ok, bindata} = Circuits.I2C.write_read(bus, address, <<regno::8>>, 4)
            data = Device.binto_perc(:duty, bindata)
            send(from, {:data, self(), data}) 
					:get_ledout -> 
            ch_num = if data <= 0, do: 1, else: data
            ch_num = if ch_num <= 16 - ch_no, do: ch_num, else: 16 - ch_no
            regno = 6 + ch_no * 4
            {:ok, bindata} = Circuits.I2C.write_read(bus, address, <<regno::8>>, ch_num * 4) 
            {:ok, fsm_id} = self_fsmid() 
            kinds = PCA9685tbl.get_devtable(fsm_id)
                    |> Enum.map( fn {kind, _, _} -> kind end)
            sdata = Enum.to_list(ch_no..(ch_no + ch_num - 1))
                    |> Enum.into( [], fn no -> {no, Enum.at(kinds, no)} end)
                    |> Enum.into( [], fn {no, kind} -> {no, kind, binary_part(bindata,(no - ch_no) * 4, 4)} end)
                    |> Enum.into( [], fn {no, kind, bin} -> {no, kind, Device.binto_perc(kind, bin)} end) 
            sdata = if length(sdata) == 1, do: Enum.at(sdata, 0), else: sdata
						send(from, {:data, self(), ch_no, sdata})
            wait_req({fsm_id, bus})
      	  _ -> Logger.warning("event code error {eve:#{eve}, from:#{from}, ch_no:#{ch_no}, data:#{inspect data}")
            wait_req({fsm_id, bus})
      	end
			msg -> Logger.warning("illegal data received #{inspect msg}")
    end
  end

  @spec setbyperc(atom(), channel(), percent()) :: bitstring()
  def setbyperc(:duty, ch_no, percent) do
    {ontime, offtime} = Device.percto_duty(ch_no, percent)  # ch_no for shift pulse
    Device.set_ledpat(ontime, offtime)
  end
  def setbyperc(:servo, ch_no, percent) do
    {ontime, offtime} = Device.percto_servo(ch_no, percent)  # ch_no for shift pulse
    Device.set_ledpat(ontime, offtime)
  end
  def setbyperc(_kind, _ch_no, _data) do
    Device.set_ledpat(0, 0x1000)	# all off
  end

  defp get_kind(fsm_id, ch_no, percent) when is_integer(percent) do
    {kind, _, _msg} = PCA9685tbl.get_chtable(fsm_id, ch_no)
		[{ch_no, kind, percent}]
	end
	defp get_kind(fsm_id, ch_base, percents) when is_list(percents) do 
		kinds = PCA9685tbl.get_devtable(fsm_id)
						|> Enum.map( fn {kind, _, _msg} -> kind end)
		Enum.with_index(percents, fn perc, index -> 
													{ch_base + index, Enum.at(kinds, ch_base + index), perc} end)
  end

	defp ledoutto_bin(counter) when is_tuple(counter), do: ledoutto_bin([counter])
	defp ledoutto_bin(counters) when is_list(counters) do
		check = Enum.all?(counters, 
					fn {on, off} when is_integer(on) and is_integer(off) -> true
						 _				-> false
				end)
		if check == true do
			Enum.reduce(counters, <<>>, 
										fn {ontime, offtime}, acc -> 
														acc <> Device.set_ledpat(ontime, offtime) end)
		else
			<<>>
		end
	end
	defp ledoutto_bin(_), do: <<>>

	# for checking from outside
	def gblget_kind(fsm_id, ch_no, percent), do: get_kind(fsm_id, ch_no, percent)

  #defp loc_mtx() do
  #  {:ok, {bus_name, _}} = self_fsmid() 
  #  pid = get_fsmpid(bus_name)    # parent bus name
  #  send(pid, {:lock, self(), "locking"})
  #  receive do
  #    {:lock, ^pid, _msg} -> :ok
  #  end
  #end

  #defp unl_mtx() do
  #  {:ok, {bus_name, _}} = self_fsmid() 
  #  pid = get_fsmpid(bus_name)    # parent bus name
  #  send(pid, {:unlock, self(), "unlocking"})
  #  receive do
  #    {:unlock, ^pid, _msg} -> :ok
  #  end
  #end
  #
  @spec read_reg(atom()) :: keyword()
  defp read_reg(regname) do
    {regno, num, format, _msg} = Device.get_reginfo(regname)
    w_dt = <<regno::8>>
    {{_bus_name, address}, bus} = get_elm(:vars)
    {:ok, data} = Circuits.I2C.write_read(bus, address, w_dt, num)
    Device.parse(data, format)
  end
	
  @spec read_rawreg(integer(), integer()) :: bitstring()
  defp read_rawreg(regno, num) do
    w_dt = <<regno::8>>
    {{_bus_name, address}, bus} = get_elm(:vars)
    {:ok, data} = Circuits.I2C.write_read(bus, address, w_dt, num)
		data
  end
	
  @spec read_ledout(channel(), integer()) :: {counter(), counter()}
  defp read_ledout(ch_base, ch_num) do
		regno = 6 + ch_base * 4
    w_dt = <<regno::8>>
    {{_bus_name, address}, bus} = get_elm(:vars)
    {:ok, bindata} = Circuits.I2C.write_read(bus, address, w_dt, ch_num * 4)
		if ch_num == 1 do
			{ontime, offtime} = Device.parse_led(bindata)
			Device.dutyto_perc({ontime, offtime})
		else

		end
  end

end
