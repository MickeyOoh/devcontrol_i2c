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
  #alias DevcontrolI2c.PCA9685tbl

  @type bus_name() :: String.t()
  @type address() :: integer()
	@type percent() :: non_neg_integer()	# 0-100%
	@type counter() :: non_neg_integer()	# 0-4095, 4096 pulses
	@type led_no() :: non_neg_integer()	# 0-15 ledn

  #def table1(), do: PCA9685tbl.table1()
  #def table2(), do: PCA9685tbl.table2()
  
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

  def restart({{bus_name, address}, bus} = argv) do
    dt_pat = Device.mode1_restart()
    data = Device.set_reg(:regmode1, dt_pat)
    Circuits.I2C.write(bus, address, data)

    pid = FsmDiagram.get_fsmpid(bus_name)
    if is_pid(pid) do
      send(pid, {:init_end, self(), address, :restart})
    end
    Process.sleep(10)
    move_to(:wait_req, argv)
  end
  
  @req_apis """
  API to request this module
  
  send(pid, {eve, from, ledn, data}) 
  ----
  pid:  FsmDiagram.get_fsmpid({bus_name, 0x40})
  from: self()  
  ledn: 0-15 led number

  | eve          |     data                |
  |--------------|-------------------------|
  | :servo_out   | percent or              |
  |              |   [percent, ...]        |
  | :duty_out    | percent or              |
  |              | [percent, ...]          |
  | :set_counter | {ontime, offtime} or    |
  |              | [{ontime, offtime},...] |
  | :get_counter | number                  | 
  """
  def api_format() do
    @req_apis
  end 

  @spec wait_req({{bus_name(), integer()}, Bus.t()}) :: none()
  def wait_req({ {_bus_name, address} = fsm_id, bus}) do
    receive do
      {eve, from, ledn, data} -> 
				case eve do
          :duty_out ->      # {:duty_out, {_from, _ev_reply}, ledn, percent | [percent, ...] }
            percents = data
            bindata = percentto_bin(ledn, percents, &Device.percto_duty/2) 
						regno = 6 + ledn * 4
      	    Circuits.I2C.write(bus, address, <<regno::8>> <> bindata)
            wait_req({fsm_id, bus})
          :servo_out ->      # {:sarvo_out, {_from, _ev_reply}, ledn, percent | [percent, ...] }
            percents = data
            bindata = percentto_bin(ledn, percents, &Device.percto_servo/2) 
						regno = 6 + ledn * 4
      	    Circuits.I2C.write(bus, address, <<regno::8>> <> bindata)
            wait_req({fsm_id, bus})  
          :set_counter ->
            counters = data
						bindata = ledoutto_bin(counters)
						regno = 6 + ledn * 4
      	    Circuits.I2C.write(bus, address, <<regno::8>> <> bindata)
            wait_req({fsm_id, bus})  
          :get_counter ->
            counters = read_ledout({fsm_id, bus}, ledn, data)
            if length(counters) == 1 do
              [counter] = counters
              send(from, {:reply, self(), ledn, counter}) 
            else 
              send(from, {:reply, self(), ledn, counters})
            end
            wait_req({fsm_id, bus})
      	  _ -> Logger.warning("#{inspect get_elm(:func)} received unknown event #{inspect eve}")
            wait_req({fsm_id, bus})
      	end
			msg -> Logger.warning("#{inspect get_elm(:func)} received format error #{inspect msg}")
            wait_req({fsm_id, bus})
    end
  end

  @spec percentto_bin(led_no(), percent(), fun()) :: bitstring()
  def percentto_bin(ledn, percents, fnc_convert) when is_list(percents) do
    len = length(percents)
    Enum.to_list(ledn..(ledn + len - 1))    #[ledn, ledn + 1, ledn +2,...]
    |> Enum.zip( percents)            #[{ledn, p0}, {ledn + 1, p1},...]
    |> Enum.into( [], fn {n, p} -> fnc_convert.(n, p) end) # [{on,off},...] 
    |> ledoutto_bin( )                # <<ledn0bin::32, ledn1bin1::32, ...>>
  end
  def percentto_bin(ledn, percent, fnc_convert), do: percentto_bin(ledn, [percent], fnc_convert) 
  
  @doc """
  converts counters to bitstring 
     counters :: {ontime, offtime} | [{ontime, offtime}, ...]

  # Example

     iex> ledoutto_bin({0x0123, 0x0321})
     <<35, 1, 33, 3>>
     iex> ledoutto_bin([{0x100, 0x200}, {0x300, 0x400}, {0x500, 0x600}])
     <<0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6>>
     iex> ledoutto_bin({0x0123})
     <<>>

  """ 
  @spec ledoutto_bin({counter(), counter()} | [{counter(), counter()}, ...])  
                                :: bitstring()
	def ledoutto_bin({_ontime, _offtime} = counter), do: ledoutto_bin([counter])
	def ledoutto_bin(counters) when is_list(counters) do
		check = Enum.all?(counters, 
					    fn {on, off} when is_integer(on) and is_integer(off) -> true
						 _				-> false
				    end)
		if check == true do
			Enum.reduce(counters, <<>>, 
										fn {ontime, offtime}, acc -> 
                      acc <> Device.set_ledpat(ontime, offtime) 
                    end)
		else
			<<>>
		end
	end
	def ledoutto_bin(_), do: <<>>

  #defp loc_mtx() do
  #  {:ok, {bus_name, _}} = self_fsmid() 
  #  pid = get_fsmpid(bus_name)    # parent bus name
  #  send(pid, {:lock, self(), :loc_mtx, "locking"})
  #  receive do
  #    {:lock, ^pid, _msg1, _msg2} -> :ok
  #  end
  #end

  #defp unl_mtx() do
  #  {:ok, {bus_name, _}} = self_fsmid() 
  #  pid = get_fsmpid(bus_name)    # parent bus name
  #  send(pid, {:unlock, self(), :unl_mtx, "unlocking"})
  #  receive do
  #    {:unlock, ^pid, _msg1, _msg2} -> :ok
  #  end
  #end
  #
  #@spec read_reg(atom()) :: keyword()
  #defp read_reg(regname) do
  #  {regno, num, format, _msg} = Device.get_reginfo(regname)
  #  w_dt = <<regno::8>>
  #  {{_bus_name, address}, bus} = get_elm(:vars)
  #  {:ok, data} = Circuits.I2C.write_read(bus, address, w_dt, num)
  #  Device.parse(data, format)
  #end
	#
  #@spec read_rawreg(integer(), integer()) :: bitstring()
  #defp read_rawreg(regno, num) do
  #  w_dt = <<regno::8>>
  #  {{_bus_name, address}, bus} = get_elm(:vars)
  #  {:ok, data} = Circuits.I2C.write_read(bus, address, w_dt, num)
	#	data
  #end
	
  @spec read_ledout({{bus_name(), address()}, Bus.t()}, led_no(), integer()) 
                                  :: [{counter(), counter()}, ...]
  defp read_ledout({{_bus_name, address}, bus}, ledn, led_num) do
    led_num = case led_num do
               n when n < 1 -> 1
               n when n > 16 - ledn -> 16 - ledn
               n -> n
             end
   	regno = 6 + ledn * 4
    regnum = led_num * 4 
    {:ok, bindata} = Circuits.I2C.write_read(bus, address, <<regno::8>>, regnum)
    Enum.to_list(0..(led_num - 1))     # [0, 1, 2, 3,..] 
    |> Enum.map( fn n -> n * 4 end)   # [0, 4, 8, 12,..]
    |> Enum.map( fn loc -> binary_part(bindata, loc, 4) end)  # [<<bin::32>>,...] 
    |> Enum.map( fn bit32 -> Device.parse_led(bit32) end)   #[{ontime, offtime},...]
  end

end
